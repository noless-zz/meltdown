# 0004 Default controller layout for flight and M2 weapons

Date: 2026-11-16. Status: **Proposed; confirmed by the owner after a headset session.**
Recorded by a Builder run for issue #149 (PLT-5, FLT-2, CMB-1), from the owner's playtest.

## Why now

The playtest found boost on the left stick click awkward (the same thumb holds the stick
forward) and pressing boost alone did nothing. M2 needs the triggers for weapons (CMB-1),
and until now they moved the ship up and down. One complete layout now means the owner
relearns the controls once, not again at M2.

## Fixed by the owner

- Boost is **hold A**. Hold, not toggle: the energy pool lasts about four seconds and a
  hold cannot be left on by accident.
- Reset is **hold the left menu button for 1 s** (#162).
- **Y** stays the comfort preset button.
- **Triggers fire**: right primary, left secondary.
- Every action stays remappable (PLT-5): the layout is a data file
  (`game/xr/layouts/thumbsticks_default.json`).

## The layout (thumbsticks scheme, right-handed)

| Control | Action | Where it is read |
| --- | --- | --- |
| Left stick x | Strafe left / right | layout file |
| Left stick y | Forward / back | layout file |
| Right stick x | Yaw left / right | layout file |
| Right stick y | Nose up / down (`invert_pitch` flips) | layout file |
| Left grip | Roll left | layout file |
| Right grip | Roll right | layout file |
| Right trigger | Fire primary (`fire_primary`) | layout file |
| Left trigger | Fire secondary: unbound until secondaries exist | (M2) |
| A (right lower) | Boost, hold; also full forward thrust | layout file |
| B (right upper) | Up | layout file |
| X (left lower) | Down | layout file |
| Y (left upper) | Next comfort preset | `ComfortWiring` |
| Left stick click | Show / hide control labels | not wired yet (follow-up) |
| Right stick click | Free | |
| Left menu, hold 1 s | Reset to start | `ResetHold` (#162) |
| Right menu (Meta button) | System; never reaches the app | |

**Left-handed mode** swaps every left control with its right twin, as before: the right
stick flies and the left turns, the left trigger fires the primary, X boosts, Y moves up,
A moves down, B is the preset button and the right stick click shows or hides labels.
Reset stays on the left menu button, because the right menu button is the Meta system
button.

The paired layout (`thumbsticks_paired.json`, #82, both directions of a motion on one hand)
follows the same rules: B up and right grip down; X roll left and left grip roll right;
A boost and right trigger fire as in the default.

## Choices made here, and why

- **Lift on B (up) and X (down).** The triggers are taken by weapons and the grips by
  roll. The face buttons are the only controls left that both hands can reach without
  letting go of a stick. Up on the right hand and down on the left keeps the old split
  (right trigger up, left trigger down), so the owner's habit carries over. Lift becomes
  on/off rather than analogue; the tunnel combat in M2 mostly needs a quick dodge, and a
  remap can put it back on an analogue control.
- **Labels show / hide on the left stick click.** Toggling labels is rare and harmless if
  pressed by accident, so it can take the control that was awkward for boost. Boost no
  longer needs the left stick held forward, so that thumb is less loaded. Like the preset
  button it is not a flight action, so it is read outside the layout file. Wiring it needs
  `main.gd` (lane-b) and is left to a follow-up issue.
- **Boost gives full forward thrust.** While boost is held the ship thrusts forward at 1
  as well as burning the afterburner, so A alone moves the ship. A stick held forward part
  way is raised to full.
- **Pulling the stick back wins over boost.** If the left stick is pulled back, its
  reverse thrust is kept and boost does not add forward thrust; the afterburner stays on.
  A pilot pulling back asked to slow or reverse, and that must not be overridden by a
  button still held from a moment earlier.
- **Secondary fire stays unbound.** `ShipInput` has no `fire_secondary` and the
  simulation has no secondary weapons yet; adding it means a new replay column and core
  changes, which is not trivial. The left trigger is reserved for it in this table.

## The gripped-stick scheme

`GrippedStickMapping` keeps its own layout (boost on X there). It is not changed by this
record; aligning it is a separate decision once the thumbsticks layout is confirmed.

## Keyboard (flat build)

The keyboard follows the controls it stands in for: R / F press B / X (up / down), Shift
presses A (boost), Space pulls the right trigger (fire). Backspace stays the reset key.

## Headset check

One session for the whole layout: boost on A from a standstill, firing on the right
trigger, lift on B and X, and whether the labels read correctly on both hands.
