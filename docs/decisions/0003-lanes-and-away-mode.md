# 0003 Builder lanes and away mode

Date: 2026-11-15. Decided by the owner in the setup conversation; answers issue #44.

## Three Builder lanes

Parallel Builder runs collided on 2026-11-14 because three runs picked the same issue.
From now on up to three Builders run at once, each restricted to a lane label
(`lane-a`, `lane-b`, `lane-c`). The Planner assigns every `ready` issue to exactly one
lane and keeps lanes from editing the same files. A run never chooses work outside its
lane, so no claim step is needed. The owner's fallback, if lanes cause trouble, is one
Builder at a time.

## Away mode: on from 2026-11-15, off when the owner says so

The owner is away for about three days and wants as much built as possible in that time.
While away mode is on:

- The Builders, Reviewer and Planner run on a faster schedule.
- An open milestone gate does not stop work. The Planner may open and plan up to two
  milestones past the oldest open gate. Gates are deferred, not skipped: only the owner
  closes them, after a headset session, and each gate issue collects what he must check.
- The Reviewer may merge workflow changes under the conditions in
  `docs/routines/reviewer.md`. Workflows that use the owner's self-hosted PC runner are
  never merged without him.

Consequences accepted by the owner: work past gate G1 is built on flight and comfort
behaviour nobody has felt in a headset, so some of it may need rework after his playtest.
To limit that, feel and comfort values live in data files.

Away mode ends when the owner comments on the Status issue or tells a session. The
Planner then returns to planning one milestone ahead and stopping at open gates.
