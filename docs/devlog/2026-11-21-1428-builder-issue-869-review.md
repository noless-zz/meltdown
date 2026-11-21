# 2026-11-21 Builder, lane-c, issue #869 (review answer)

Scheduled Builder run in lane-c (chain 1). Named in Israel time (UTC+2).

## Pull requests checked

- #907 (closes #869): CI green and no conflict, but the Reviewer requested changes at
  46b48ec, after its last commit. The routine says to fix it first, so this run starts no
  new issue.
- #916 (closes #870, opened by the previous run): CI green, no conflict, no review yet.

## Issue

#869's third criterion says the validator sweep (seeds 1..1000) "stays under 15 s in CI".
The sweep is already 16.6 s in CI on `main`, and 17.0 s on #907.

## Summary

- Profiled `SeedSweep.run(1, 1000)` locally (Godot 4.7.2 headless) on `main` and on #907.
  `main` took 15511 ms and #907 took 15493 ms. About 75% of the time is `generate`
  (about 6.1 s) and `build` (about 5.7 s). `debris_escape` is about 2.0 s on both.
  #869's files (`opening_graph.gd`, `debris_escape.gd`) cannot bring the sweep under 15 s.
- Took the Reviewer's second option. I commented on #869 asking the planner or owner to
  change the criterion to "no slower than `main`", and opened #919 (triage) to own the
  validator sweep time, with the stage table. I changed #907's body to point at #919
  instead of #903, and answered the Reviewer on #907.
- No code change.

## Test results

No code changed. The local profile above gives `failed=0` on both trees.

## Open questions

- #907 stays blocked until the planner or owner changes #869's third criterion.

## Next suggested issue

#887 (seed sweep counts meltdown debris by kind). #870's PR #916 waits for review.
