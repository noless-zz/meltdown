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
2. The simulated headset has no controllers, so `XRController3D` nodes never track and
   the action map is only loaded, not used. Monado has `SIMULATED_LEFT` and
   `SIMULATED_RIGHT` switches; they were not tried (out of scope for #26).
3. The only refresh rate is 20 Hz, so the 90 Hz branch in `main.gd` (PRF-1) is not taken.
4. Software rendering says nothing about performance (PRF requirements) and is desktop
   Vulkan, not the Quest's Android driver. Foveation and every Meta-specific extension
   are absent. The headset session at each gate stays necessary (DEV-6).
5. Godot 4.7 logs errors against Monado that do not stop the session, among them
   `XR_ERROR_SESSION_NOT_STOPPING` when the game quits without first asking the session
   to end. The script does not treat logged errors as failures.
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

- Simulated controllers through `SIMULATED_LEFT` and `SIMULATED_RIGHT`, to check that
  both hands track.
- End the session cleanly before quitting to remove the `xrEndSession` error.
