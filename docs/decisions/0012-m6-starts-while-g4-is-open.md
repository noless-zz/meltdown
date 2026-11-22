# 0012 One-time pass: M6 starts while gate G4 is open

Date: 2026-11-22. Decided by the owner (issue #1295), relayed from his chat session. It takes
effect when he merges the pull request that adds this file.

## Decision

Work on M6 (Look, sound, speed) may start now, although gate G4 (#950) is still open. The
Planner may label M6 issues `ready` and plan M6 as the current milestone.

This is a single exception, not a change of rule:

- It covers G4 and M6 only. Every later gate stops planning as `docs/routines/planner.md`
  says, and M5 does not open before G6 is closed (decision record 0008).
- Away mode stays off (decision record 0003).
- G4 stays open and stays the owner's to close, after he has played full runs. Nobody
  else ticks or closes it.

## Why

Every M4 issue is closed and its automated half is green on `main`. The owner flew a
two-level run from the hub with different levels and "it felt good". What put him off
playing further is not in M4's scope: "home base was very basic graphic and im missing a
good sound and graphic touch to keep playing... menus were overwhelming because of the
text". He cannot test tonight and does not want the Builders idle while G4 waits for him.

## What the owner wants first in M6

From the same message, in this order:

1. **The hub and the menus.** Less text on screen at once, clear visual grouping, and a
   look that belongs to a game rather than a test panel (CRW-2, PLT-2, GFX). This is his
   main complaint.
2. **Sound.** Core events audible: weapons, hits taken and given, pickups, the reactor,
   the countdown, the menu (AUD-1).
3. **Materials, lighting and effects** in the mine (GFX-2 and after).

Music and the optimisation steps follow.

## Consequences

- G4's human half will be judged on a build that already has M6 work in it. That is what
  the owner asked for; his notes on #950 should say which build he flew.
- Playtest issues still go to the front of every lane, ahead of M6 features, as before.
  M4 faults he finds while playing M6 builds are fixed first.
- M6 brings assets. `CLAUDE.md` holds: free or AI-generated only, source and licence
  recorded in `docs/licences.md`, nothing from the original games (NAM-3).
