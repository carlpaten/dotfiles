---
name: gh
description: "Run GitHub PR workflow: semantic title, CI loop to green, accurate PR description, and thread cleanup."
---

# gh

## When to use
- Creating/updating PRs.
- Pushing commits tied to an open PR.
- Responding to review comments.

## Do this
1. Ensure semantic PR title.
   - Format: `<type>(scope): <description>`
   - Types: `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`
   - Check: `gh pr checks <pr-number>`
   - Fix title: `gh pr edit <pr-number> --title 'fix(scope): concise description'`
2. Keep branch current.
   - `git fetch origin dev && git merge origin/dev`
3. Push changes.
4. Run CI loop until green.
   - Run: `/home/carl/.scripts/poll-pr-feedback-or-red.sh <pr-number> 600 15`
   - If it prints `signal=red-check`, fix failures and repeat from step 2.
   - If it prints `signal=feedback`, respond to feedback and continue iteration.
   - If it prints `signal=timeout`, treat as no-news and continue.
5. After every push:
   - Update PR description to match current implementation.
   - Resolve addressed review threads.

## Output
- Current PR title validity.
- CI status and failing checks (if any).
- Confirmation PR description and threads were updated.
