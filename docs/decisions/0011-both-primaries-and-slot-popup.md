# 0011 Both primaries fire, a slot popup, and X retired

Date: 2026-11-22. Decided by the owner on issue #1218, in his answer of 2026-11-22 11:57
Israel time ([relayed here](https://github.com/noless-zz/meltdown/issues/1218#issuecomment-7077486114)),
which said decision record 0004 "needs a follow-up record". Recorded by a Builder run for
issue #1259 (CMB-1, PLT-5, SLV-1, DEV-4).

## Why now

Playtest #1210 found that nothing chose which primary slot fires: `ShipState.selected_primary`
was always slot 1, so a part slotted into slot 2 was carried but never fired. Issue #1218
asked the owner to pick one of three fixes. He chose none of them as written. His words on
the way there: "can we use the other trigger to fire secondary?", then "last gun trigger is
ambiguous... maybe keep left trigger for secondary and right trigger shoots all weapons for
now... Pressing thumbstick opens popup above stick to choose with stick which weapons to
replace".

## Decision

### Firing

| Control | Action |
| --- | --- |
| Right trigger | Fires **both** primary slots together, each on its own interval and energy cost |
| Left trigger | Stays reserved for secondary weapons; does nothing until they exist |

There is no selected primary for firing any more. CMB-1 is unchanged: the ship still has
two primary and two secondary slots, so `docs/requirements.md` needs no edit.

### Slotting (right stick click, as today)

| Situation | The click |
| --- | --- |
| Hold empty | Nothing |
| A part in the hold, a primary slot empty | Slots it at once, no popup (as today) |
| A part in the hold, both slots full | Opens a small popup above the right stick |

In the popup the right stick chooses instead of turning the ship:

| Stick | Result |
| --- | --- |
| Left | Replaces slot 2, the left gun |
| Right | Replaces slot 1, the right gun |
| Down | Dumps the held part |
| Click again | Cancels; the part stays in the hold |

- The replaced gun drops behind the ship, as it does today (SLV-1).
- The mine keeps running while the popup is open; it is meant as a one-flick choice.
- The choice reaches the simulation as recorded input (ARC-2): `ShipInput` carries which
  slot, or a dump, so replays carry it. The popup itself is view and xr code and writes no
  simulation state (MP-2).
- Every control here stays remappable in the layout file (PLT-5).

### Accepted gap

With a primary slot empty there is no way to dump an unwanted part: the click slots it at
once. The owner accepted this; the pilot slots it and replaces it later.

### X retired

X is no longer the comfort preset button. His words: "x can be deprecated to free for
future use as menu is good enough". The comfort preset is chosen in the menu (#748, CMF-4).
X is free for future use. The label diagram and the left-handed and paired layouts follow.

## What this amends in 0004

Decision record 0004 is not edited; this record overrides the parts listed here.

- **Still holds:** "Triggers fire: right primary, left secondary". The right trigger is the
  primary trigger and the left trigger stays reserved for secondaries.
- **No longer holds:** that the right trigger fires a *selected* primary. It fires both.
- **No longer holds:** "X is the comfort preset button" (0004, its 2026-11-19 amendment for
  #613, and the gripped-stick section's "X still changes the preset"). The X row of 0004's
  layout table, `ThumbstickMapping.PRESET_BUTTON` and the "comfort preset" label on X go.
- The right stick click, "Free" in 0004's table, slots a held part, as it already does, and
  opens the popup when both slots are full.

## Carried out by

- #1260 (lane-c): X no longer changes the preset; its binding and label go.
- #1261 (lane-b): the right trigger fires both primary slots; `selected_primary` is removed.
- #1262 (lane-b): `ShipInput` carries the slot choice (slot 1, slot 2, dump) as recorded
  input.
- #1263 (lane-b): the popup above the right stick.

## Headset check

Done in the issues above: both guns fire on the right trigger; with both slots full the
click opens the popup and one flick replaces or dumps; X does nothing and the preset still
changes from the menu.
