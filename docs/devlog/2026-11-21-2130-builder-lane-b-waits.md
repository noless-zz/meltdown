# 2026-11-21 21:30 Builder, lane-b, no issue taken

Scheduled Builder run in lane-b (no chain line). Times in Israel time (UTC+2).

## Pull requests checked

- #1005 and #1006 both close #989 (two lane-b runs started on #989 a few seconds apart
  at 21:01). Both mergeable, XR smoke test green, unit tests still running. Nothing to fix.
  Only one of them should be merged; the other should be closed.

## Why no issue was taken

- #989 already has pull requests.
- #990 needs #989 merged first; it has not. Commented on #990.
- #1000 needs #990 merged first.

So this run takes no issue and does not start a chained run.

## Next suggested issue

#990, once one pull request for #989 has merged.
