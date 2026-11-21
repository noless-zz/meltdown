# 0008 Components, crafting and a tech tree; look and sound before co-op

Date: 2026-11-21. Decided by the owner (issue #770). Wording drafted from his chat
session; it takes effect when he merges the pull request that adds this file.

## Decision 1: components, crafting and a tech tree join M4

New requirements CRF-1 to CRF-7:

- Robots drop components as well as the part they used (CRF-1).
- Components are banked on each escape and kept when a later level is lost (CRF-2, RUN-7).
- At the hub the player crafts permanent upgrades (weapons, shields, hull, engines,
  utility modules) and fits them before a run (CRF-3, CRF-4, CMB-1, CRW-2).
- Ships get utility slots outside the four weapon slots (CRF-5).
- Upgrades form a tech tree whose higher tiers need components from deeper levels
  (CRF-6, CRF-7).

## Why

The owner wants progress between runs to come from what he collects: "weapons and
shielding + hull should be craftable from components picked up from destroyed bot", an
"upgrade tech tree and resources to progress in levels", and utility slots that can later
hold "extended radar or miner scanner". Without wording, M4 would be planned with crew
benefits as the only permanent progression.

## Choices the draft made (the owner may change any of them)

1. **Banking at each escape**, not only at the end of a run. This is what makes "a lost
   run still feels rewarded" (gate G4) true, and it keeps the escape worth something.
2. **Crafted upgrades are fitted before the run**, so they change the starting loadout
   (CMB-1 reworded). The alternative, crafted items only joining the pool of robot drops,
   keeps every run starting equal but makes crafting feel like luck.
3. **CRW-3 still holds**: permanent progression widens options and never trivialises
   early levels. Tier costs and strengths are data and are tuned against the bot runs.
4. **Crafting and fitting are Must, the tree shape and depth-gated components are
   Should.** A flat list of craftable upgrades satisfies the Musts.
5. **Co-op is not decided here.** Whether crew members bring their own crafted ships or
   share the host's is a question for M5 planning.

Look-aim and aim assist (issue #678) are utility modules under CRF-5; their own wording
comes with that issue.

## Decision 2: M6 (Look, sound, speed) is worked before M5 (Co-op)

Milestone and gate numbers do not change, so earlier records and issues stay valid
(decision record 0007 still means gate G6). The order of work becomes M0 to M4, M6, M5,
M7, M8, M9. For the Planner's "one milestone ahead" rule, M6 follows M4 and M5 follows M6.

## Why

The owner wants to see and hear a better game before co-op: materials, effects, sound
effects and music matter to him and to the family testers sooner than a second headset
in the same mine.

## Consequences

- Gate G6's "VR-sensitive tester on preset 1" (0007) comes earlier, which is what that
  record wanted: the tester sees a polished game.
- M6's optimisation is done before the network code exists. PRF-9 (a hosting headset
  holds frame rate for four players) is still checked at gate G5, so some performance
  work will be revisited in M5.
- Audio and materials must stay out of `core/` (ARC-1), so moving them earlier does not
  change the simulation that co-op will replicate.
