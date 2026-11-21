# 0010 Look-aim and aim assist

Date: 2026-11-21. Decided by the owner on issue #678 (his idea of 2026-11-20 17:26, answers
of 2026-11-21 02:04 and 02:06 Israel time, and a note of 03:23 tying it to the crafting
wording of #770), requested as a requirements change in issue #761.

Numbered 0010: issue #761 reserved 0008, but the crafting pull request for #770 (#771) took
0008, and 0009 is reserved for the menu issue #763.

## Decision

- **Look-aim** (CMB-6): the guns aim along the pilot's head direction within a cone around
  the nose, following it at a gimbal turn rate. Head, not eyes: the Quest 3 has no eye
  tracking.
- **Aim assist** (CMB-7): a shot bends towards a target within a small cone of where it is
  aimed. A separate ability from look-aim.
- **Both are utility modules** (CMB-8), in the utility slots of CRF-5, outside the four
  weapon slots, crafted and fitted like any other module (CRF-3, CRF-4). This replaces the
  Planner's proposed SLV-4 ("earned in a run as salvage, or unlocked at the hub"): the owner
  said on #678 that CRF-3 and CRF-4 cover it.
- **By preset** (comfort table):

  | | Preset 1 | Preset 2 | Presets 3 and 4 |
  | --- | --- | --- | --- |
  | Look-aim | On, no module | Pilot's option, no module | Crafted module |
  | Aim assist | Crafted module (open, see below) | Crafted module | Crafted module |

- **Same strength:** look-aim without a module has the same cone and gimbal rate as the
  crafted module. There is no weaker free version.
- **The aim follows the preset:** changing preset, including mid-run, sets look-aim to the
  new preset's value (on at 1, the pilot's choice at 2, off at 3 and 4) unless a look-aim
  module is fitted, in which case it stays on.
- **Co-op:** players on different presets in one crew may have different aim. Damage, speed
  and timers stay the same for all (CMF-6, COOP-6).

The owner's words:

> 1 & 2 free, 3 and 4 need to collect resources and craft. thats not balance as 1 can't aim
> without it... and 2 is optional for assist.
>
> not weaker, outside slots... maybe utility slots, which in future can have extended radar
> or miner scanner etc...
>
> cycle through presets will remove aim assist except if upgrade is present... in moving
> between presets it will dynamically adjust to correct value for the comfort preset

and, asked which ability "aim assist" meant there: "no head tracking was the correct, mark
aim assist with upgrade... maybe allow in preset 1 to toggle between 2 modes without module.
and preset 2 already need to craft it".

## Why this is parity, not balance

CMF-6 says presets change how motion is shown, not balance. Preset 1 turns the ship in snaps
and limits pitch, and preset 2 caps the turn rate; lining the nose up on a moving robot is
then much harder than on presets 3 and 4. Look-aim gives those pilots back the ability to
aim that the comfort limits took away. It is not stronger than what presets 3 and 4 can
craft, and damage, speed and timers are unchanged, so CMF-6 is reworded to say so rather
than carving out an exception.

## How it stays inside the architecture

ARC-3 and MP-2 hold. The preset, which lives in `xr/`, only decides whether look-aim is
offered. The aim direction is player input each tick, like thrust and fire: the client sends
it, the authoritative core clamps it to the cone and fires along it, and the replay records
it, so state hashes stay deterministic (ARC-2). `xr/` never writes simulation state.

## Left open

- **Aim assist on preset 1 without a module** (the owner's "maybe"): written in the comfort
  table as an open option, a mode the pilot toggles to instead of look-aim. The owner keeps
  it or strikes it before merging.
- **Cone width and gimbal rate:** data, tuned in play. The Planner's starting suggestion was
  about 30 to 40 degrees.
- **Custom mode** (CMF-1 exposes every row): whether the custom mode may switch look-aim on
  without a module. Not answered yet; until it is, custom mode follows presets 3 and 4.
- **Crafting** (components, recipes, the tech tree, weapons, shields and hull from
  components): M4, worded by #770 and its decision record.

## Consequences

- Merge after the crafting pull request (#771): CMB-8 names CRF-3, CRF-4 and CRF-5.
- After merging, the Planner files an M2 issue: aim direction in `ShipInput` and the replay,
  the core fires along it, default "nose" so existing replays keep their hashes. Then the
  preset hook in `xr/`, a world-locked reticle and visibly swivelling muzzles. Modules and
  crafting wait for M4.
