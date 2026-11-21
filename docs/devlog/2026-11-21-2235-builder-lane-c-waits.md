# 2026-11-21 22:35 Builder, lane-c, no issue taken

Chained Builder run in lane-c (chain 1). Times in Israel time (UTC+2).

## Pull requests checked

- #1018 closes #964. Mergeable, every CI check green (unit tests, XR smoke test, Linux and
  Quest builds), no Reviewer comment yet. Nothing to fix.

## Why no issue was taken

- #963 is labelled `in-progress`: another lane-c Builder run commented "Builder run
  started" at 22:34, a few seconds before this run.
- #964 already has a pull request (#1018).
- #1012 needs #963 merged first; it has not. Commented on #1012.

So this run takes no issue and does not start a chained run.

## Test results

No code changed; tests not run.

## Next suggested issue

#1012, once #963's pull request has merged.
