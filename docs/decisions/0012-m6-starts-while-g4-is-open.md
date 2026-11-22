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

## What M6 is for: game feel

Refined by the owner the same evening: "its not just hub and menu... overall graphic of
ship and surrounding environment should be added in M6. revisit all graphics assets
including designing a home base... now focus this gate on game feel... look/sound/speed
as stated in gate."

So M6 is judged as gate G6 says, "quality accepted in the headset", and covers all of:

- **Look.** Every graphic asset is revisited, not only the walls: the ship and its
  cockpit, the robots, weapons and their effects, pickups, miners, fire, the reactor, the
  mine itself (materials, lighting, GFX-2 and after), and the menus (less text on screen
  at once; "menus were overwhelming because of the text").
- **Sound.** Core events audible and placed in space (AUD-1), then music.
- **Speed.** The frame and memory budgets hold with all of the above (PRF).
- **The home base as a 3D place** (see below).

His sharpest complaint is the home base and the menus, so they should not come last,
but M6 is not a hub milestone: the gate is about how the whole game looks, sounds and
runs.

## The home base becomes a 3D room with terminals

CRW-2 already calls the hub "a small room". In M6 it becomes one: a modelled space the
pilot is in, with a terminal (a station) for each task the flat panel pages do today:
craft, fit, crew, logbook, resume, launch. The pages' rules and data do not change; what
changes is where and how they are shown.

Constraints for the Planner:

- It must work seated and at every comfort preset. Moving about the room may not use
  smooth locomotion on presets 1 and 2 (CMF-1, CMF-3); terminals arranged within reach or
  pointing distance of one spot is an acceptable first version. If a movement scheme is
  needed, ask the owner before building it.
- Presentation only: the room reads and changes the same profile and fitting through the
  same code paths (ARC-3, MP-2).
- Build it so a terminal can later hold more than a list.

## Direction noted for later (not M6 scope)

The owner wants the base to grow into something played, not read: "mini games and real
in game crafting and mounting/maintaining/rebuilding the ship and its components". That
is hands-on work at the terminals and on the ship itself. It is recorded here so the 3D
room is planned to support it; it needs its own requirement wording, merged by the
owner, before any of it is built.

## Consequences

- G4's human half will be judged on a build that already has M6 work in it. That is what
  the owner asked for; his notes on #950 should say which build he flew.
- Playtest issues still go to the front of every lane, ahead of M6 features, as before.
  M4 faults he finds while playing M6 builds are fixed first.
- M6 brings assets. `CLAUDE.md` holds: free or AI-generated only, source and licence
  recorded in `docs/licences.md`, nothing from the original games (NAM-3).
