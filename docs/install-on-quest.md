# Installing a build on a Quest

## Getting the APK

**Newest build from `main` (no login needed).** Every push to `main` publishes the APK to
the rolling `main-latest` pre-release:

<https://github.com/noless-zz/meltdown/releases/download/main-latest/meltdown-quest-debug.apk>

A checksum sits next to it as `meltdown-quest-debug.apk.sha256`. The desktop client
(`meltdown-desktop.x86_64`) and the dedicated server are published to the same release.

**A pull request build.** Every CI run of the `Quest APK (debug)` job, including runs on
pull requests, uploads an artifact named `meltdown-quest-debug`. Open the run under the
repository's **Actions** tab (or the **Checks** tab of a pull request), scroll to
**Artifacts** and download `meltdown-quest-debug`. You must be signed in to GitHub. Unzip
it to get `meltdown-quest-debug.apk`.

## One-step update

`tools/update_quest.sh` (Linux and macOS) and `tools/update_quest.ps1` (Windows) download
the APK and its checksum from the `main-latest` release, stop before installing if the
checksum does not match, install with `adb install -r` on every connected headset, and
print the commit and build time of the build they installed. They need only `adb` (and
`curl` for the bash script).

```sh
tools/update_quest.sh            # add --launch to start the game afterwards
```

```powershell
powershell -ExecutionPolicy Bypass -File tools\update_quest.ps1   # -Launch to start it without asking
```

The PowerShell script asks whether to start the game unless `-Launch` or
`-UninstallFirst` is given.

**Over Wi-Fi.** With the headset on the same network, connect it by USB once and run
`adb tcpip 5555`, unplug it, find its IP address in the headset's Wi-Fi settings and run
`adb connect <headset-ip>:5555`. `adb devices` should then list `<headset-ip>:5555 device`,
and the scripts update it like a cabled one. Every headset listed as `device` is updated;
ones listed as `offline` or `unauthorized` are skipped (put the headset on and allow USB
debugging).

**Different signature.** If a headset holds a copy signed with another key (an older
build), the update stops for that headset and says so. Run again with `--uninstall-first`
(`-UninstallFirst` in PowerShell) to remove that copy and install; its saved data is lost.

## Installing it

1. With the headset connected and developer mode on, either drag the APK onto the headset
   in Meta Quest Developer Hub, or run:

   ```sh
   adb install -r meltdown-quest-debug.apk
   ```

   With two headsets connected, add `-s <serial>` using a serial from `adb devices`.
2. In the headset open **Library**, choose **Unknown Sources**, and start
   **Descent: Meltdown**.

Builds from `main` are signed with a stable debug key, so `install -r` updates in place.
If an install fails because a copy with a different signature is already present (an
older build or a local build), remove the old one first; its saved data is lost:

```sh
adb uninstall io.github.nolesszz.meltdown
```

To build the same APK locally, see `tools/build.sh quest`.
