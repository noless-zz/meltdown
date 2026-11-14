# Installing a build on a Quest

Every CI run of the `Quest APK (debug)` job uploads an artifact named
`meltdown-quest-debug`.

1. Open the run under the repository's **Actions** tab (or the **Checks** tab of a pull
   request), scroll to **Artifacts** and download `meltdown-quest-debug`. You must be
   signed in to GitHub.
2. Unzip it to get `meltdown-quest-debug.apk`.
3. With the headset connected and developer mode on, either drag the APK onto the headset
   in Meta Quest Developer Hub, or run:

   ```sh
   adb install -r meltdown-quest-debug.apk
   ```

   With two headsets connected, add `-s <serial>` using a serial from `adb devices`.
4. In the headset open **Library**, choose **Unknown Sources**, and start
   **Descent: Meltdown**.

Each CI build is signed with a fresh throwaway debug key. If an install fails because a
copy with a different signature is already present, remove the old one first:

```sh
adb uninstall io.github.nolesszz.meltdown
```

To build the same APK locally, see `tools/build.sh quest`.
