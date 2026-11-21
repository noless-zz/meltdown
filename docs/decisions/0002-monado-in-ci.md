# 0002 Monado as a simulated headset in CI

Date: 2026-11-15. Result of the time-boxed experiment in issue #26 (PLT-2, ARC-1, DEV-3).
Recorded by a Builder run; the owner decides whether the job stays.

## Result: works, with limits

A GitHub-hosted `ubuntu-latest` runner can start the game in real OpenXR mode. The job
`XR smoke test (Monado)` installs Monado from the Ubuntu archive, starts its service with
a simulated headset, runs the game for 120 frames and checks one result line.

| Question | Answer |
| --- | --- |
| Does an OpenXR session start? | Yes: `session_begun` fires and `"session":true` is reported |
| Runtime | `Monado(XRT) by Collabora et al`, package `25.0.0+dfsg-2build1` on the hosted runner |
| Headset | Monado's built-in "Simulated HMD", chosen by itself when no hardware is attached |
| Views | 2 (primary stereo), 128 x 128 recommended render size per eye |
| Refresh rate | 20 Hz, the only rate the simulated display offers |
| Renderer | Godot Mobile renderer on Vulkan, software rendered by Mesa lavapipe 26.0.8 under Xvfb |
| Time for 120 frames | about 20 to 40 seconds, plus about 30 seconds of setup |

## How it is set up

- Packages: `monado-service`, `libopenxr1-monado`, `mesa-vulkan-drivers`, `xvfb`. Nothing
  is built from source and nothing is added to the repository (see `docs/licences.md`).
- `XRT_COMPOSITOR_NULL=1` selects Monado's null compositor, which is made for CI: it
  accepts frames and shows nothing, so the service needs no display.
- `XR_RUNTIME_JSON` points at the packaged Monado manifest, which makes it the active
  runtime for that process only.
- The game runs under `xvfb-run` with `--rendering-driver vulkan --rendering-method
  mobile`. `--headless` cannot be used: it selects the dummy renderer, which cannot
  create OpenXR swapchains. The method is named because `--rendering-driver` alone makes
  Godot choose Forward+ and ignore the project's Mobile setting.
- `LP_NUM_THREADS=1` keeps lavapipe on one rasteriser thread (see "What failed first").
- `monado-service` polls stdin for a quit key and refuses to start when stdin is
  `/dev/null` (`epoll_ctl(stdin) failed`). `tools/xr_smoke.sh` gives it an open pipe.
- The game is started with `-- --xr-smoke-frames=120`. `main.gd` then quits after 120
  frames and prints, for example:

  ```
  MELTDOWN_XR_SMOKE {"frames":120,"refresh_rate":20.0,"runtime":"Monado(XRT) by Collabora et al '25.0.0+dfsg-2build1'","session":true,"views":2}
  ```

- The script fails when there is no such line, when `session` is not true, when `views`
  is below 2, or when Godot exits with an error.

## What failed first

The first CI run (job 132623406794) started a session and then crashed: Godot printed
`OpenXR session active` and `refresh rate 20.0 Hz`, then `Program crashed with signal 11`
in a thread other than the main one, with the fault inside generated code.

The crash was reproduced in an `ubuntu:26.04` container, which has the same Monado and
Mesa packages as the runner:

| Mesa | Renderer | lavapipe threads | XR session | Result |
| --- | --- | --- | --- | --- |
| 26.0.8 | Forward+ | 4 | yes | crash, 6 of 6 runs |
| 26.0.8 | Forward+ | 3 | yes | crash in 1 of 2 runs |
| 26.0.8 | Forward+ | 0, 1 or 2 | yes | pass |
| 26.0.8 | Forward+ | 4 | no (flat) | pass |
| 26.0.8 | Mobile | 4 | yes | pass, 3 of 3 runs |
| 26.0.8 | Mobile | 1 | yes | pass, 8 of 8 runs |
| 25.2.8 (Ubuntu 24.04) | Forward+ | 4 | yes | pass, 2 of 2 runs |

So it is a fault in Mesa 26.0 lavapipe's threaded rasteriser that shows with stereo
rendering in Forward+, not a fault in the game or in Monado. The hosted runner has four
cores, the Builder's sandbox two, which is why the first local runs passed. Two changes
followed: the script now asks for the Mobile renderer, which is the one the Quest uses
and which the first run was not using by mistake, and it pins lavapipe to one thread.
The cause inside Mesa was not investigated further.

## Evidence

- Local runs in the Builder's sandbox (2 cores, no GPU) with the final script: session
  started, 2 views, 20 Hz, exit code 0, both on Ubuntu 24.04 (Monado 21.0.0 snapshot,
  Mesa 25.2.8) and in an `ubuntu:26.04` container (Monado 25.0.0, Mesa 26.0.8).
- Without Monado the same game command prints `"session":false,"views":0`, which the
  script turns into a failure. A crash leaves no result line, which also fails. So the
  job can fail, and did.
- CI run 43653672259 on pull request #34: the job passed in 88 seconds and reported
  `"session":true,"views":2,"refresh_rate":20.0` on Monado `25.0.0+dfsg-2build1`. The
  logs are in its `xr-smoke-logs` artifact. Run 43652355148 is the crash described above.

## Limits

1. It proves that the OpenXR start-up path runs, not that the picture is right. The null
   compositor throws every frame away; nothing is looked at or compared.
2. Since issue #571 the run starts two simulated `Simple Controller`s, the action map
   binds their profile, and the script fails unless both hands track. Only the pose
   actions are bound for that profile, so buttons, sticks and haptics are not exercised,
   and the Quest's own Touch bindings are checked by a unit test, not by the run.
   (Before #571 the simulated headset had no controllers and the hands never tracked.)
3. The only refresh rate is 20 Hz, so the 90 Hz branch in `main.gd` (PRF-1) is not taken.
4. Software rendering says nothing about performance (PRF requirements) and is desktop
   Vulkan, not the Quest's Android driver. Foveation and every Meta-specific extension
   are absent. The headset session at each gate stays necessary (DEV-6).
5. Godot 4.7 logs errors against Monado that do not stop the session, among them
   `XR_ERROR_SESSION_NOT_STOPPING` when the game quits without first asking the session
   to end. The script does not treat logged errors as failures.
   Since issue #575 the script counts the log lines containing
   `XR_ERROR_SESSION_NOT_STOPPING` (`tools/count_session_not_stopping.sh`) and prints
   `MELTDOWN_XR_SMOKE_SHUTDOWN {"session_not_stopping_errors":<n>}` after the result line.
   The count is reported, never a failure; it shows whether a fix for #558 removes the
   error.
6. The package versions follow `ubuntu-latest`. A new runner image can change Monado or
   Mesa and break the job without any change in this repository; the crash above is an
   example of what a Mesa update can bring.

## Consequences

- The job is a separate block in `ci.yml` with no `needs`, so it runs beside the other
  jobs and none of them waits for it.
- It is not `continue-on-error`, because a session does start: a change that breaks XR
  start-up should show as a red check. It must not be added to the required checks in
  branch protection. If it turns out to be flaky because of limit 6, mark it
  `continue-on-error` and open an issue; do not delete it silently.
- The quit switch lives in `game/xr/xr_smoke_probe.gd`. It is off unless
  `--xr-smoke-frames=<N>` with N above zero is on the command line.

## Possible follow-ups (not started)

(Simulated controllers, once listed here, were done in issues #559 and #571.)

- End the session cleanly before quitting to remove the `xrEndSession` error.

## Addendum 2026-11-18: simulated controllers (issue #559)

Tried in an `ubuntu:26.04` container with the runner's packages (Monado
`25.0.0+dfsg-2build1`, Mesa 26.0.8 lavapipe, Godot 4.7.2) and the unchanged game.

- Monado 25 reads `SIMULATED_ENABLE`, `SIMULATED_LEFT` and `SIMULATED_RIGHT`. With
  `SIMULATED_ENABLE=1` its log says `Using builder simulated` and lists `left: Simple
  Controller (Simulated)` and `right: Simple Controller (Simulated)` for the value
  `simple`, `WinMR Left/Right Controller (Simulated)` for `wmr`, and `ML2 Controller
  (Simulated)` for `ml2`. `hand_tracking.left` and `.right` stay `<none>`.
- With each of the three, the session starts as before but neither hand tracks:
  `"left_tracked":false,"right_tracked":false`. Godot logs no error about it.
- The cause is the action map. `game/openxr_action_map.tres` suggests bindings only for
  `khr/generic_controller`, `oculus/touch_controller` and `ext/hand_interaction_ext`.
  Monado 25 does not offer `khr/generic_controller`, and none of its simulated
  controllers offers the Touch profile, so no pose action is bound.
- As a check, a scratch copy with an extra `/interaction_profiles/khr/simple_controller`
  profile (only `default_pose` on `/user/hand/{left,right}/input/grip/pose`) reported
  `"left_tracked":true,"right_tracked":true` with `SIMULATED_LEFT=simple` and
  `SIMULATED_RIGHT=simple`. That change was not committed: the action map ships to the
  headset and was outside issue #559's files.

So `tools/xr_smoke.sh` now starts Monado with two simple controllers and prints the two
values, but does not fail on them. Limit 2 above stays until issue #571 adds the
simple-controller profile to the action map and makes the script check both hands.

Update (issue #571): `game/openxr_action_map.tres` now has a
`/interaction_profiles/khr/simple_controller` profile binding `default_pose` and
`aim_pose` to `/user/hand/{left,right}/input/aim/pose` and `grip_pose` to
`.../grip/pose`, the same pose paths the Touch profile uses. `default_pose` is the pose the
rig's `XRController3D` nodes follow. The hands are now tracked and checked:
`tools/xr_smoke.sh` fails, naming the hand, when `left_tracked` or `right_tracked` is
false. `game/tests/test_xr_action_map.gd` pins the Touch profile's bindings so the
addition cannot change what the Quest uses. Limit 2 above is rewritten accordingly.

## Addendum 2026-11-21: phase times and a 300 s budget (issue #727)

From 20 November the job failed at random with `xr_smoke: no result line (godot exit
code 124)` on `main` and on pull requests that changed nothing it runs: Godot was given a
fixed 120 s and recent green runs already took 66 to 120 s. Once, on PR #741, Monado's
socket did not appear within the 10 s the script waited.

`tools/xr_smoke.sh` now prints one line on every exit, failures included, from its own
clock (the moment a phase's marker first appears in the Godot log):

```
MELTDOWN_XR_SMOKE_TIMES {"monado_socket_s":…,"godot_to_ready_s":…,"godot_to_session_s":…,"session_to_first_frame_s":…,"first_frame_to_last_s":…,"godot_total_s":…,"budget_s":300,"frames":120}
```

`null` means that phase never ended. The probe also prints
`MELTDOWN_XR_SMOKE_FRAME {"frame":N,"msec":…}` (engine clock) on frame 1 and every 30th
frame; those lines are in the `xr-smoke-logs` artifact.

Three runs of the job on PR #746 (run 44836665075, attempts 1 to 3, same commit),
seconds:

| Attempt | Monado socket | Godot start to session | Session to frame 1 | Frame 1 to 120 | Godot total | Frames 1 to 30 | Then per 30 frames |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 6.6 | 3.8 | 0.0 | 64.3 | 68.3 | 41.9 | 7.1 to 7.9 |
| 2 | 6.0 | 7.1 | 0.0 | 118.2 | 125.9 | 72.8 | 14.7 to 15.7 |
| 3 | 1.0 | 4.1 | 0.0 | 86.5 | 91.0 | 54.9 | 9.7 to 11.4 |

For comparison, the Builder's sandbox (2 cores, Monado 21, Mesa 25.2) took 25 s in
total with a cold shader cache, 15 s of it for frames 1 to 30, and 19 s with a warm one.

What the times show:

- Start-up before the first frame is short (4 to 8 s). The time is in the frames.
- Frames 1 to 30 take 55 to 65 % of the run: the first frames compile the Mobile
  renderer's shaders and pipelines on lavapipe (llvmpipe), which nothing before them has
  done, because the import step runs headless without Vulkan.
- After that, each frame is software-rendered at 20 Hz pacing, 0.25 to 0.5 s each.
- The runner's speed varies by about two to one between attempts of the same commit, and
  both parts scale with it. Attempt 2 would have failed under the old 120 s.
- Monado's socket took up to 6.6 s, close to the old 10 s wait.

Decision:

- The Godot budget is `XR_SMOKE_TIMEOUT`, default 300 s: more than twice the slowest run
  measured, and well inside the job's 15-minute `timeout-minutes`, so `.github/` is
  unchanged. The frame count stays 120.
- The socket wait is `XR_SMOKE_SOCKET_WAIT`, default 30 s.
- Nothing was cut. The cheap fix for the first-frame compilation would be to carry
  Godot's shader cache (`user://shader_cache`, `user://vulkan`) between runs, which needs
  a cache step in `ci.yml` (protected). A warm-up run inside the script would cost about
  as much as it saves. If the job grows slow again, that cache step is the next thing to
  propose to the owner.
