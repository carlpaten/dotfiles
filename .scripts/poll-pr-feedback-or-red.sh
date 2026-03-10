#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: poll-pr-feedback-or-red.sh <pr-number|url|branch> <timeout-seconds> [interval-seconds]

Poll a PR until one of these happens:
1) Actionable review feedback exists (unresolved non-self review-thread comments)
2) A status check turns red
3) All status checks are green

Exit codes:
0   Completed poll window (feedback, red checks, green checks, or timeout)
1   Usage or runtime error
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

pr_ref="$1"
timeout_seconds="$2"
interval_seconds="${3:-15}"

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds <= 0 )); then
  echo "error: timeout-seconds must be a positive integer" >&2
  exit 1
fi

if ! [[ "$interval_seconds" =~ ^[0-9]+$ ]] || (( interval_seconds <= 0 )); then
  echo "error: interval-seconds must be a positive integer" >&2
  exit 1
fi

viewer_login="$(gh api user --jq '.login')"
pr_url="$(gh pr view "$pr_ref" --json url --jq '.url')"

if [[ "$pr_url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)$ ]]; then
  repo_owner="${BASH_REMATCH[1]}"
  repo_name="${BASH_REMATCH[2]}"
  pr_number="${BASH_REMATCH[3]}"
else
  echo "error: could not parse PR URL: $pr_url" >&2
  exit 1
fi

snapshot() {
  local pr_json
  local review_threads_json

  pr_json="$(gh pr view "$pr_ref" --json comments,reviews,statusCheckRollup)"
  review_threads_json="$(
    gh api graphql \
      -f query='
        query($owner:String!, $name:String!, $number:Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100) {
                nodes {
                  isResolved
                  comments(first: 100) {
                    nodes {
                      id
                      body
                      createdAt
                      url
                      author {
                        login
                      }
                    }
                  }
                }
              }
            }
          }
        }
      ' \
      -F owner="$repo_owner" \
      -F name="$repo_name" \
      -F number="$pr_number"
  )"

  jq -n \
    --arg viewer "$viewer_login" \
    --argjson pr "$pr_json" \
    --argjson review_threads "$review_threads_json" '
      def summarize($body):
        $body
        | gsub("\\s+"; " ")
        | if length > 140 then .[:137] + "..." else . end;

      def failed_check_conclusion($value):
        ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "STALE"]
        | index($value) != null;

      def failed_status_state($value):
        ["FAILURE", "ERROR"]
        | index($value) != null;

      def pending_check($check):
        (
          $check.__typename == "CheckRun"
          and ($check.status // "") != "COMPLETED"
        )
        or
        (
          $check.__typename == "StatusContext"
          and (["EXPECTED", "PENDING"] | index($check.state // "")) != null
        );

      def green_check($check):
        (
          $check.__typename == "CheckRun"
          and ($check.status // "") == "COMPLETED"
          and (["SUCCESS", "NEUTRAL", "SKIPPED"] | index($check.conclusion // "")) != null
        )
        or
        (
          $check.__typename == "StatusContext"
          and (["SUCCESS"] | index($check.state // "")) != null
        );

      {
        feedbackItems: (
          [
            $review_threads.data.repository.pullRequest.reviewThreads.nodes[]? as $thread
            | select(($thread.isResolved // false) == false)
            | $thread.comments.nodes[]?
            | select((.author.login // "") != $viewer)
            | {
                id,
                source: "thread-comment",
                author: (.author.login // ""),
                createdAt: (.createdAt // ""),
                url: (.url // ""),
                state: "",
                summary: summarize(.body // "")
              }
          ]
          | sort_by(.createdAt, .id)
        ),
        redChecks: [
          $pr.statusCheckRollup[]?
          | select(
              (
                .__typename == "CheckRun"
                and failed_check_conclusion(.conclusion // "")
              )
              or
              (
                .__typename == "StatusContext"
                and failed_status_state(.state // "")
              )
            )
          | {
              name: (.name // .context // "unknown"),
              state: (.conclusion // .state // "UNKNOWN"),
              url: (.detailsUrl // .targetUrl // "")
            }
        ],
        totalChecks: ([$pr.statusCheckRollup[]?] | length),
        pendingCheckCount: (
          [$pr.statusCheckRollup[]? | select(pending_check(.))]
          | length
        ),
        greenCheckCount: (
          [$pr.statusCheckRollup[]? | select(green_check(.))]
          | length
        )
      }
    '
}

deadline=$((SECONDS + timeout_seconds))

while (( SECONDS < deadline )); do
  current="$(snapshot)"
  red_count="$(jq -r '.redChecks | length' <<<"$current")"
  total_checks="$(jq -r '.totalChecks' <<<"$current")"
  pending_check_count="$(jq -r '.pendingCheckCount' <<<"$current")"
  green_check_count="$(jq -r '.greenCheckCount' <<<"$current")"
  feedback_count="$(jq -r '.feedbackItems | length' <<<"$current")"

  if (( red_count > 0 )); then
    echo "signal=red-check"
    jq -r '.redChecks[] | "- \(.name): \(.state) \(.url)"' <<<"$current"
    exit 0
  fi

  if (( feedback_count > 0 )); then
    echo "signal=feedback"
    jq -r '.feedbackItems[] | "- [\(.source)] @\(.author) \(.createdAt) \(.url)\n  \(.summary)"' <<<"$current"
    exit 0
  fi

  if (( total_checks > 0 && pending_check_count == 0 && green_check_count == total_checks )); then
    echo "signal=green"
    echo "checks_green=$green_check_count"
    exit 0
  fi

  sleep "$interval_seconds"
done

echo "signal=timeout"
exit 0
