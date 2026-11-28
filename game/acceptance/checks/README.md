# Acceptance check files

Every `*.gd` script in this folder adds acceptance checks without editing a shared
file (issue #1297, `AcceptanceCheckFiles`). Each lane adds its own file, so lanes
working on a milestone at the same time never edit the same lines.

A check script:

```gdscript
extends RefCounted

static func judges() -> Dictionary[String, Callable]:
	return {"my_check": _my_check}


static func _my_check(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return [AcceptanceReport.RESULT_PASS, "why"]
```

A check name may be used once across these files and `AcceptanceStep.KNOWN_CHECKS`.
A script that cannot be read fails every suite with the file named.

Suite steps for the M6 lanes go in the parts under `../suites/m6/`:
`ship` and `perf` (lane-a), `sound` and `effects` (lane-b), `look`, `base` and `menu` (lane-c).

## Step time limits (#1444)

Every step has a time limit, so one stuck step cannot hold the rest of the run. A step that
reaches it is reported `fail` with `timed out after N s at tick T`, and the next step starts.

- `time_limit_seconds` on a step: that step's limit in seconds, used as written.
- `default_time_limit_seconds` at the top of a suite file (beside `name`): the limit for its
  steps and its parts' steps that set none. Without it the default is 120 s.
- The default is counted on top of the time a step is told to wait (`settle_seconds`,
  `measure_seconds`, `view_seconds`, `pause_seconds`), so the 25-minute soak and the measured
  perf steps get their full time. A step whose checks wait for something else for a long time
  should set its own `time_limit_seconds`.

The clock is wall time from the step's first frame (`AcceptanceTimeLimit`).

## What a run leaves for the scripts (#1444)

- `<suite>-<commit>.json` in `user://acceptance/` as soon as each suite ends.
- `acceptance_exit.json` in the same folder when the run ends: `build`, `suites`, `passed`,
  `failed` and `skipped` (suite names), `exit_code` and `finished` (UTC). It is written just
  before the `Meltdown: acceptance: exit <code>` line.
- Each step line ends with `suite=<name> index=<n> count=<total>`, `index` counting from 1:
  `Meltdown: acceptance: step fly suite=m1 index=3 count=9`, then
  `Meltdown: acceptance: step fly pass suite=m1 index=3 count=9`. A timed-out step's line adds
  its message in brackets after the fields.
