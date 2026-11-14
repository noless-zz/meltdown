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
| Runtime | `Monado(XRT) by Collabora et al`, version 21.0.0 (Ubuntu 24.04 package `21.0.0+git2905.e26a272c1`) |
| Headset | Monado's built-in "Simulated HMD", chosen by itself when no hardware is attached |
| Views | 2 (primary stereo), 128 x 128 recommended render size per eye |
| Refresh rate | 20 Hz, the only rate the simulated display offers |
| Renderer | Godot Mobile renderer on Vulkan, software rendered by Mesa lavapipe 25.2 under Xvfb |
| Time for 120 frames | 12 to 30 seconds on 2 cores, plus about a minute of setup |

## How it is set up

- Packages: `monado-service`, `libopenxr1-monado`, `mesa-vulkan-drivers`, `xvfb`. Nothing
  is built from source and nothing is added to the repository (see `docs/licences.md`).
- `XRT_COMPOSITOR_NULL=1` selects Monado's null compositor, which is made for CI: it
  accepts frames and shows nothing, so the service needs no display.
- `XR_RUNTIME_JSON` points at the packaged Monado manifest, which makes it the active
  runtime for that process only.
- The game runs under `xvfb-run` with `--rendering-driver vulkan`. `--headless` cannot be
  used: it selects the dummy renderer, which cannot create OpenXR swapchains.
- `monado-service` polls stdin for a quit key and refuses to start when stdin is
  `/dev/null` (`epoll_ctl(stdin) failed`). `tools/xr_smoke.sh` gives it an open pipe.
- The game is started with `-- --xr-smoke-frames=120`. `main.gd` then quits after 120
  frames and prints, for example:

  ```
  MELTDOWN_XR_SMOKE {"frames":120,"refresh_rate":20.0,"runtime":"Monado(XRT) by Collabora et al 'GIT-NOTFOUND'","session":true,"views":2}
  ```

- The script fails when there is no such line, when `session` is not true, when `views`
  is below 2, or when Godot exits with an error.

## Evidence

- Local run in the Builder's sandbox (Ubuntu 24.04, 2 cores, no GPU), same packages and
  the same script: session started, 2 views, 20 Hz, exit code 0, in both runs made.
- Without Monado the same command prints `"session":false,"views":0`, which the script
  turns into a failure. So the job can fail.
- CI: see the `XR smoke test (Monado)` job and its `xr-smoke-logs` artifact on the pull
  request for #26. The run numbers are in the devlog entry of that pull request.

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
5. Monado in Ubuntu 24.04 is an old snapshot from the 21.0.0 line. Godot 4.7 logs three
   errors against it that do not stop the session: two rejected controller binding
   suggestions and `XR_ERROR_SESSION_NOT_STOPPING` when the game quits without first
   asking the session to end.
6. The package versions follow `ubuntu-latest`. A new runner image can change Monado or
   Mesa and break the job without any change in this repository.

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
