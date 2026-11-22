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
`ship` and `perf` (lane-a), `sound` and `effects` (lane-b), `look` and `base` (lane-c).
