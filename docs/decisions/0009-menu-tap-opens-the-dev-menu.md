# 0009 A short tap of the left menu button opens the dev menu

Date: 2026-11-21. Status: **Proposed; confirmed by the owner after a headset session.**
Recorded by a Builder run for issue #763 (PLT-5, DEV-6, ARC-3, CMF-8, MP-2, DEV-7).
Amends decision record 0004 (default controller layout).

## Decided by the owner

On #748 (2026-11-21 01:58 Israel time): "menu button on the left stick is good, with the
short press". The in-headset dev menu (#753) opens on a short tap of the left menu button.

## What changes in the layout

| Control | Before | Now |
| --- | --- | --- |
| Left menu, tap (released before 1 s) | Ask for the update check, or choose "Update" | Open or close the dev menu |
| Left menu, hold 1 s | Reset to start (#162) | Unchanged |
| Right stick click | Slot the held part | Unchanged |

- A press is never both: a press held for `ResetHold.RESET_HOLD_SECONDS` is the reset and
  does not open the menu (`MenuTap`).
- The tap stays on the left menu button in left-handed mode, like the reset, because the
  right menu button is the Meta system button.
- The take-a-break prompt (#716) still takes a tap first while it shows.
- The tap does nothing during the first-launch flight test, which uses the menu hold to
  skip, or while the destroyed or escape screen is up.
- The control label of the left menu button reads "tap: menu, hold: reset".

## While the menu is open

The menu takes the controls, so the ship gets neutral input and drifts to a stop the way
the flight test holds it; nothing new in `core/`. The menu's named actions (#753) are read
from:

| Control | Menu action |
| --- | --- |
| Right stick up / down | Previous / next entry |
| Right stick left / right | Change the value (corner, level) |
| A | Confirm (the button that restarts after a loss) |
| B / Y | Seed +1 / -1 (the up / down buttons) |
| Right / left trigger | Seed +10 / -10 |

The flat build reaches the same actions through its keys: arrows for the right stick, Shift
for A, R / F for B / Y, Space for the right trigger, Backspace for the menu button.

Choosing a level or "Restart level" fades out, flies the choice from its start through
`restart_level` and fades back in (CMF-8). A corner change keeps the menu open so the panel
can be seen to move.

## The update prompt moves into the menu

The tap no longer reaches the update notice (#646, #703). When a newer build waits, the menu
shows "Update to <version>" as its first entry, and choosing it does what the tap did:
take the offered build, retry an install that waits, or, while the build downloads, cancel
it (the entry then reads "Cancel update to <version>"). Without a waiting build there is no
entry. The notice's choice line now reads "Update: open the menu", and the installer's
lines say to choose Update in the menu. A check the pilot asks for by hand is gone; the
start-up check stays.

## Headset check

Tap the left menu button: the menu appears in front, the stick moves through it, A picks;
a corner change moves the panel, a seed restarts through a fade; a hold still resets; an
update shows as an entry.
