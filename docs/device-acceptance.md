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

The script first reads only the release's `.sha256` and compares it with the checksum of the
`base.apk` the headset holds (`pm path`, then `sha256sum` on the headset). When they match it
prints `Headset <serial> already has this build (checksum ... matches); skipping download and
install.` and goes straight to the suite (#1437). A missing package, a failed adb call or an
unreadable answer installs as before: it never skips on doubt. `-Force` (or
`MELTDOWN_FORCE_INSTALL=1`) installs anyway. Downloads are kept, one per checksum, in
`meltdown-apk-cache` under the temp folder, so a rerun after a failed install does not download
again; older builds there are deleted.

Before installing, the script waits up to `-DeviceWaitSeconds` (20 s) for the headset to
answer on adb. An install that fails with no reason, or with the headset `not found` or
`offline`, waits for it again and retries without streaming, at most twice (#589). A
headset that stays gone fails the run with "the headset dropped off USB for a moment".

## Choosing the headset

With one headset listed, that one is used. With more, the script takes `-Serial`, else
`ANDROID_SERIAL`, and skips if the named one is not listed. With neither, and the same
headset (same `ro.serialno`) on the cable and on ADB over Wi-Fi, it uses Wi-Fi and says so:
a USB reset then does not cut the run (#1436). Different headsets: the first one, said in
the output.

## When adb drops during a run

An adb command that cannot reach the headset is not a crash (#1436). When a log poll or the
`pidof` check fails and the headset does not answer `adb shell true`, the script prints
`the connection to the headset dropped at HH:MM:SS` and waits up to `-ReconnectSeconds`
(300 s) for the same headset on any of its serials (cable or Wi-Fi). When it is back it
prints `the headset is back at HH:MM:SS` and goes on until the exit line or `-TimeoutSeconds`.
The headset keeps its log buffer through a USB reset, so the end of `device.log` is filled
from it after the stream that the drop cut.

If the headset never comes back, the run fails with "the connection to the headset dropped
at HH:MM:SS", not with a step verdict from a partial log.

Before the start the script clears the game's report folder (`run-as` on the debug build,
`files/acceptance`). At the end it copies every `.json` there into `from-headset/` in the
artifact and adds any suite the log did not hold to the table; `acceptance_exit.json`
(#1444) stands in for a missing exit line. With no exit line and no exit file, the rows of
the suite that was running come from the `Meltdown: acceptance: step` lines, and the reason
says the table is partial.

## Unattended runs and the controllers

A scheduled workflow run, `-Suite nightly` or `-Unattended` starts the game with the intent
extra `meltdown_unattended=1`. Nobody wears the headset then and the controllers sleep, so
`m0/controllers_bound` reports **skipped** ("the left controller is not tracked; ...:
unattended run, the headset is not worn") instead of failed, as a locked headset skips. An
attended run still fails it, and tracked controllers with a missing binding fail either way.

## The USB reset about 60 s after the start

Three owner runs on 25 and 26 November lost adb about 60 s after `am start`: 22:50:55 to
22:51:54, 16:08:00 to 16:09:00 and 16:15:2x to 16:16:23. What the log shows each time:

- `[Highwind]: highwind.dap.usb: USB setup has been running for Ns`, every 10 s from the
  start, then `UsbDeviceManager: Setting USB config to` with `setUsbConfig(4294967297)` and
  `init: service xrspd requested start`. The battery level (2 and 96 percent) and the Meta
  Quest Developer Hub (closed in the third run) made no difference.
- A suite that ends before 60 s (`m2` on 25 November, 55 s) is not affected.
- Each run stopped at exactly 7 screenshots, which fits a fixed time rather than one step.

**Cause not found** from these logs. Highwind appears to be the headset's Quest Link side,
and the `USB setup has been running` lines suggest it keeps trying to set up a Link
connection over the cable and gives up by resetting USB, which drops adb. Things to try, one
at a time, each with a nightly run:

1. On the headset, Settings > System > Quest Link: turn Quest Link off for the run. On the
   PC, quit the Meta Quest Link app, so nothing answers a Link request over the cable.
2. Use ADB over Wi-Fi and pass its address with `-Serial` (or leave both connected: the
   script prefers Wi-Fi for the same headset), so a USB reset does not cut adb at all.
3. Stop screen recording or casting over USB during the run.

The script now waits out the reset either way, so a run that loses adb for a moment still
finishes with the full table.
