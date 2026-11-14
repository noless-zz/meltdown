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

## Installing it

1. With the headset connected and developer mode on, either drag the APK onto the headset
   in Meta Quest Developer Hub, or run:

   ```sh
   adb install -r meltdown-quest-debug.apk
   ```

   With two headsets connected, add `-s <serial>` using a serial from `adb devices`.
2. In the headset open **Library**, choose **Unknown Sources**, and start
   **Descent: Meltdown**.

Each CI build is signed with a fresh throwaway debug key. If an install fails because a
copy with a different signature is already present, remove the old one first:

```sh
adb uninstall io.github.nolesszz.meltdown
```

To build the same APK locally, see `tools/build.sh quest`.
