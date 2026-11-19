# Builder routine

One run implements exactly one issue and ends with an open pull request and a devlog entry.

## Lanes

Up to three Builder runs work at the same time, each in its own lane: `lane-a`, `lane-b` or
`lane-c`. The scheduled task that starts a run names its lane. A run only ever touches
issues carrying its lane label, and pull requests that close such issues. The Planner
assigns lanes so that different lanes do not edit the same files (decision record 0003).
A run that was given no lane behaves as `lane-a`.

## Steps

1. Read `CLAUDE.md`, `docs/requirements.md` and the three newest files in `docs/devlog/`.
2. List open pull requests whose issue is in your lane. If one has failing CI, a merge
   conflict with `main`, or a `Reviewer: changes requested` comment newer than its last
   commit, fix that pull request first (rebase on `main` for a conflict) and stop after
   pushing the fix. Do not start a new issue in the same run.
3. Otherwise pick the issue to work on: open, labelled `ready` and your lane, not labelled
   `needs-human` or `in-progress`, with no open pull request, in the earliest open
   milestone that has one, lowest issue number first. If there is
   none, write a devlog entry saying so and stop.
4. Add the `in-progress` label and comment "Builder run started".
5. Create branch `issue-<number>-<short-slug>` from the latest `main`.
6. Implement the acceptance criteria and nothing beyond them. Follow the layer rules in
   `CLAUDE.md`. Add or update unit tests for every criterion that can be tested. If the
   issue adds behaviour an acceptance suite can drive (a replay or scripted input), add
   or update its step in the milestone's suite under `game/acceptance/suites/`; if no
   suite can drive it yet, say so in the pull request (decision record 0005).
7. Run the tests exactly as CI does. Fix until green.
8. If the issue turns out too large for one run, implement the smallest coherent part,
   say so in the pull request, and open follow-up issues labelled `triage` for the rest.
9. Commit with messages that explain why. Push the branch.
10. Open a pull request titled `<issue title> (#<number>)` whose body lists: the issue it
    closes, the requirement IDs served, what changed, how it was tested, and anything a
    human must check in a headset.
11. Add `docs/devlog/<YYYY-MM-DD>-<HHMM>-builder-issue-<number>.md` to the same pull
    request: issue, summary, test results, open questions, next suggested issue.
12. Remove `in-progress` from the issue.

## Stop conditions

- CI fails twice on the same issue after your fixes: label the issue `needs-human`,
  comment with the failure and what you tried, and stop (DEV-5).
- The issue conflicts with `docs/requirements.md` or a decision record: comment on the
  issue, label it `needs-human`, and stop.
- The work would need a change to a protected path (`CLAUDE.md`, `docs/requirements.md`,
  `docs/routines/`, `.github/`) that the issue does not explicitly ask for: stop and
  comment.

## Never

Merge your own pull request, push to `main`, close a milestone, or mark a gate as passed.
