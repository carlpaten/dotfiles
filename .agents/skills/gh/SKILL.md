---
name: gh
description: "Open and monitor GitHub PR, loop on PR, CI loop to green"
---

# gh

## When to use
- Creating/updating PRs.
- Pushing commits tied to an open PR.
- Responding to review comments.

## Do this
0. Run `tmux rename-window "looping <PR #>..."
1. Ensure semantic PR title.
   - Format: `<type>(scope): <description>`
   - Types: `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`
   - Check: `gh pr checks <pr-number>`
   - Fix title: `gh pr edit <pr-number> --title 'fix(scope): concise description'`
2. Keep branch current.
   - `git fetch origin dev && git merge origin/dev`
3. Push changes.
4. Run CI loop until green.
   - Use this structure:
     1. Start `$HOME/.scripts/poll-pr-feedback-or-red.sh <pr-number> 600 15`.
     2. While that process is still running, wait on the same session in longer chunks (prefer `90` to `120` seconds at a time).
     3. When it exits:
        - `signal=red-check`: fix the failing CI and then restart the outer loop from step 2.
        - `signal=green`: stop polling; the checks are green and there is no unresolved review feedback.
        - `signal=feedback`: address the feedback or decide explicitly why not; in either case resolve the handled review thread(s). If you made code changes, restart the outer loop from step 2. If not, continue polling.
        - `signal=timeout`: treat as no-news and continue polling until all required checks are green and no actionable feedback remains.
5. After every push:
   - Update PR description to match current implementation.
   - Resolve addressed review threads.
6. Once this is all settled: run `tmux rename-window "done <PR #>"`

## Output
- Current PR title validity.
- CI status and failing checks (if any).
- Confirmation PR description and threads were updated.
