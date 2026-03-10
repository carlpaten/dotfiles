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

snapshot() {
  gh pr view "$pr_ref" --json comments,reviews,statusCheckRollup | jq --arg viewer "$viewer_login" '
      {
        externalCommentCount: (
          [.comments[]? | select((.author.login // "") != $viewer)] | length
        ),
        externalReviewCount: (
          [.reviews[]? | select((.author.login // "") != $viewer)] | length
        ),
        redChecks: [
          .statusCheckRollup[]?
          | select(
              (
                .__typename == "CheckRun"
                and (
                  [
                    "FAILURE",
                    "TIMED_OUT",
                    "STARTUP_FAILURE",
                    "ACTION_REQUIRED"
                  ]
                  | index(.conclusion)
                ) != null
              )
              or
              (
                .__typename == "StatusContext"
                and (["FAILURE", "ERROR"] | index(.state)) != null
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
baseline_comments="$(jq -r '.externalCommentCount' <<<"$baseline")"
baseline_reviews="$(jq -r '.externalReviewCount' <<<"$baseline")"

deadline=$((SECONDS + timeout_seconds))

while (( SECONDS < deadline )); do
  current="$(snapshot)"
  current_comments="$(jq -r '.externalCommentCount' <<<"$current")"
  current_reviews="$(jq -r '.externalReviewCount' <<<"$current")"
  red_count="$(jq -r '.redChecks | length' <<<"$current")"

  if (( red_count > 0 )); then
    echo "signal=red-check"
    jq -r '.redChecks[] | "- \(.name): \(.state) \(.url)"' <<<"$current"
    exit 0
  fi

  if (( current_comments > baseline_comments || current_reviews > baseline_reviews )); then
    echo "signal=feedback"
    echo "comments_before=$baseline_comments comments_now=$current_comments"
    echo "reviews_before=$baseline_reviews reviews_now=$current_reviews"
    exit 0
  fi

  sleep "$interval_seconds"
done

echo "signal=timeout"
exit 0
