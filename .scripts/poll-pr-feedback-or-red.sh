#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: poll-pr-feedback-or-red.sh <pr-number|url|branch> <timeout-seconds> [interval-seconds]

Poll a PR until one of these happens:
1) New feedback appears (new non-self PR comments or reviews)
2) A status check turns red

Exit codes:
0   Completed poll window (feedback, red checks, or timeout)
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

      {
        feedbackItems: (
          [
            $pr.comments[]?
            | select((.author.login // "") != $viewer)
            | {
                id,
                source: "issue-comment",
                author: (.author.login // ""),
                createdAt: (.createdAt // ""),
                url: (.url // ""),
                state: "",
                summary: summarize(.body // "")
              }
          ]
          +
          [
            $pr.reviews[]?
            | select(
                (.author.login // "") != $viewer
                and (
                  ((.body // "") | gsub("\\s+"; "") | length) > 0
                  or ((.state // "") != "APPROVED")
                )
              )
            | {
                id,
                source: "review",
                author: (.author.login // ""),
                createdAt: (.submittedAt // ""),
                url: "",
                state: (.state // ""),
                summary: summarize(.body // "")
              }
          ]
          +
          [
            $review_threads.data.repository.pullRequest.reviewThreads.nodes[]? as $thread
            | $thread.comments.nodes[]?
            | select((.author.login // "") != $viewer)
            | {
                id,
                source: (
                  if $thread.isResolved then
                    "resolved-thread-comment"
                  else
                    "thread-comment"
                  end
                ),
                author: (.author.login // ""),
                createdAt: (.createdAt // ""),
                url: (.url // ""),
                state: "",
                summary: summarize(.body // "")
              }
          ]
          | sort_by(.createdAt, .id)
        ),
        feedbackIds: (
          [
            $pr.comments[]?
            | select((.author.login // "") != $viewer)
            | .id
          ]
          +
          [
            $pr.reviews[]?
            | select(
                (.author.login // "") != $viewer
                and (
                  ((.body // "") | gsub("\\s+"; "") | length) > 0
                  or ((.state // "") != "APPROVED")
                )
              )
            | .id
          ]
          +
          [
            $review_threads.data.repository.pullRequest.reviewThreads.nodes[]?.comments.nodes[]?
            | select((.author.login // "") != $viewer)
            | .id
          ]
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
        ]
      }
    '
}

baseline="$(snapshot)"

deadline=$((SECONDS + timeout_seconds))

while (( SECONDS < deadline )); do
  current="$(snapshot)"
  red_count="$(jq -r '.redChecks | length' <<<"$current")"
  new_feedback="$(
    jq -n --argjson baseline "$baseline" --argjson current "$current" '
      ($baseline.feedbackIds // []) as $baseline_ids
      | [
          $current.feedbackItems[]?
          | . as $item
          | select(($baseline_ids | index($item.id)) == null)
        ]
    '
  )"
  new_feedback_count="$(jq -r 'length' <<<"$new_feedback")"

  if (( red_count > 0 )); then
    echo "signal=red-check"
    jq -r '.redChecks[] | "- \(.name): \(.state) \(.url)"' <<<"$current"
    exit 0
  fi

  if (( new_feedback_count > 0 )); then
    echo "signal=feedback"
    jq -r '.[] | "- [\(.source)] @\(.author) \(.createdAt) \(.url)\n  \(.summary)"' <<<"$new_feedback"
    exit 0
  fi

  sleep "$interval_seconds"
done

echo "signal=timeout"
exit 0
