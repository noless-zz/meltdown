# 2026-11-21 22:28 Builder, lane-b, no issue taken

Scheduled Builder run in lane-b (no chain line). Times in Israel time (UTC+2).

## Pull requests checked

- #1019 closes #990. Mergeable, every CI check green (unit tests, XR smoke test, Linux and
  Quest builds), no Reviewer comment yet. Nothing to fix.

## Why no issue was taken

- #990 already has a pull request (#1019).
- #1000 needs #990 merged first; it has not. Commented on #1000.
- #1011 needs #1000 (and #991, now merged) first.

So this run takes no issue and does not start a chained run.

## Test results

No code changed; tests not run.

## Next suggested issue

#1000, once #1019 has merged.
