# 0004 Default controller layout for flight and M2 weapons

Date: 2026-11-16. Status: **Proposed; confirmed by the owner after a headset session.**
Recorded by a Builder run for issue #149 (PLT-5, FLT-2, CMB-1), from the owner's playtest.
Amended 2026-11-19 for issue #613 (PLT-5, CMF-1): down moved from X to Y and the comfort
preset from Y to X, at the owner's request (see "Amendment" below).

## Why now

The playtest found boost on the left stick click awkward (the same thumb holds the stick
forward) and pressing boost alone did nothing. M2 needs the triggers for weapons (CMB-1),
and until now they moved the ship up and down. One complete layout now means the owner
relearns the controls once, not again at M2.

## Fixed by the owner

- Boost is **hold A**. Hold, not toggle: the energy pool lasts about four seconds and a
  hold cannot be left on by accident.
- Reset is **hold the left menu button for 1 s** (#162).
- **X** is the comfort preset button (#613; it was Y until 2026-11-19).
- **Down is on Y**, mirroring up on B (#613; it was X until 2026-11-19).
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
| Y (left upper) | Down | layout file |
| X (left lower) | Next comfort preset | `ThumbstickMapping.PRESET_BUTTON`, read by `ComfortWiring` |
| Left stick click | Show / hide control labels | not wired yet (follow-up) |
| Right stick click | Free | |
| Left menu, hold 1 s | Reset to start | `ResetHold` (#162) |
| Right menu (Meta button) | System; never reaches the app | |

**Left-handed mode** swaps every left control with its right twin, as before: the right
stick flies and the left turns, the left trigger fires the primary, X boosts, Y moves up,
B moves down, A is the preset button and the right stick click shows or hides labels.
Reset stays on the left menu button, because the right menu button is the Meta system
button.

The paired layout (`thumbsticks_paired.json`, #82, both directions of a motion on one hand)
follows the same rules: B up and right grip down; Y roll left and left grip roll right;
X the comfort preset, A boost and right trigger fire as in the default. Roll left moved from
X to Y with #613 so that X is free for the preset on every layout.

## Choices made here, and why

- **Lift on B (up) and Y (down)** (Y since #613; see the amendment). The triggers are taken by weapons and the grips by
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

The keyboard follows the controls it stands in for: R / F press B / Y (up / down), Shift
presses A (boost), Space pulls the right trigger (fire). Backspace stays the reset key.

## Headset check

One session for the whole layout: boost on A from a standstill, firing on the right
trigger, lift on B and X, and whether the labels read correctly on both hands.

## Amendment 2026-11-19 (#613)

From the owner's headset session of 2026-11-19 (build `4b82ccc`): "the down button is not
symmetrical with the up button on the other stick... move the down button from X to the Y
key", and for the preset button: "swap and make X comfort preset".

- Down moves from X to **Y**, so up (B) and down (Y) sit on the upper button of each hand.
- The comfort preset moves from Y to **X**. The button is named once, as
  `ThumbstickMapping.PRESET_BUTTON`; `ComfortWiring` and the control labels both read it, so
  the label and the button cannot disagree. X now carries a "comfort preset" label.
- Left-handed mode swaps each with its twin, as before: up on Y, down on B, preset on A,
  boost on X.
- In the paired layout roll left moves from X to Y, so no layout binds the preset button.
- The keyboard keys do not change: R is still up and F still down (F now presses Y).
- Up and down stay on/off buttons. The owner accepts this "for now"; an analogue lift may
  replace them later, through a remap or a new decision.
- The gripped-stick scheme (not wired into the game) still has boost on X; aligning it with
  the preset button is part of the separate decision on that scheme.

Headset check: down on Y and up on B feel symmetrical; X changes the preset and is hard to
press by accident.

## Gripped-stick scheme (#739), proposed until the owner's headset check

`--controls=gripped` (or the intent extra `meltdown_controls`) flies the gripped virtual
stick and throttle; the thumbsticks stay the default. The scheme's buttons:

- The afterburner moves from X to the throttle hand's **upper** face button, **Y** (B in
  left-handed mode), because X is now the comfort preset button (amendment above). The
  upper button is free in this scheme since lift comes from moving the throttle. It is named
  once, as `GrippedSampler.AFTERBURNER_BUTTON`.
- Fire stays on the stick hand's trigger; the left menu hold still resets, X still changes
  the preset and the left stick click still toggles the labels.

This is the Planner's choice for the owner to overrule. Headset check: Y boosts, X still
changes the preset, and boost on Y feels right with the left hand on the throttle.
