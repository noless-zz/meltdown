# Device acceptance on the headset

`tools/device_acceptance.ps1` runs an acceptance suite on the Quest 3 attached to the
owner's `quest-pc` runner (#154, DEV-6, decision record 0005). The workflow
`.github/workflows/device-acceptance.yml` calls it by hand and every night. By hand:

```powershell
powershell -ExecutionPolicy Bypass -File tools\device_acceptance.ps1 -Suite m1
```

## What the headset needs for an unattended run

The nightly run starts at about 03:23 with nobody wearing the headset. It can only run the
game if the headset is:

- **On its charger and connected** by USB (or ADB over Wi-Fi), with USB debugging allowed
  for the PC.
- **Left unlocked.** The script wakes the display, keeps it on while plugged in and covers
  the proximity sensor, but it cannot get past a lock screen. With a lock pattern or PIN
  set, every unattended run skips.

When the headset is locked or asleep, the run **skips** (exit 0, `status: skipped`) and says
"put the headset on and unlock it". It also skips when the game never reaches the
foreground and no step starts within `-ForegroundGraceSeconds` (60 s): that is a lock screen
the system flags do not report, or a system dialog in front of the game. A skip is never a
failure, so the nightly run does not open a `playtest` issue for it.

## What the report holds

In the `device-acceptance-headset` artifact:

- `result.json` and one `<suite>.json` per suite.
- `device.log`: the whole device log, streamed from just before the game starts, with the
  log buffer raised to 16 MB first, so the engine banner and `Meltdown: refresh rate ...`
  are in it.
- `screenshots/`: taken while the suite runs, on each `Meltdown: acceptance: step` line and
  every 5 s, never after the exit line. A file named `...-background.png` was taken while
  the game was not the foreground app. The summary warns when no screenshot shows the game.

## The install

Before installing, the script waits up to `-DeviceWaitSeconds` (20 s) for the headset to
answer on adb. An install that fails with no reason, or with the headset `not found` or
`offline`, waits for it again and retries without streaming, at most twice (#589). A
headset that stays gone fails the run with "the headset dropped off USB for a moment".
