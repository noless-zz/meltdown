class_name AcceptanceRefreshCheck
extends RefCounted

## The `refresh_rate` acceptance check (#598, CMF-1, PRF-1, gate G1): on the
## headset the display must run at no less than the active comfort preset's
## rate. It reads the rate in use from the scene's `RefreshRate`, the same
## value the log line and the status panel show. Kept out of
## `AcceptanceRunner` so that file stays short.


## Whether the scene's rate in use is known, so the check can run.
static func settled(main: Node) -> bool:
	var rate: RefreshRate = main.get("refresh_rate") as RefreshRate
	return rate == null or rate.settled()


## [result, message] for the check, adding the rates to `measurements`.
## Without an OpenXR runtime it is skipped, or fails when `required`.
static func run(main: Node, xr_available: bool, required: bool, measurements: Dictionary) -> Array:
	if not xr_available:
		return [AcceptanceReport.RESULT_FAIL if required else AcceptanceReport.RESULT_SKIPPED,
			"no OpenXR runtime"]
	var rate: RefreshRate = main.get("refresh_rate") as RefreshRate
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	if rate == null or comfort == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no refresh rate or comfort preset"]
	return judge(rate, RefreshRate.target_hz(comfort.preset), measurements)


## [result, message] for a rate in use against the preset's `wanted_hz`.
static func judge(rate: RefreshRate, wanted_hz: float, measurements: Dictionary) -> Array:
	measurements["refresh_rate_wanted_hz"] = wanted_hz
	measurements["refresh_rate_in_use_hz"] = rate.in_use_hz
	measurements["refresh_rate_offered_hz"] = rate.offered.duplicate()
	if rate.in_use_hz == RefreshRate.UNKNOWN:
		return [AcceptanceReport.RESULT_FAIL, "the rate in use was not read back"]
	if rate.in_use_hz < wanted_hz - RefreshRate.SAME_RATE_HZ:
		return [AcceptanceReport.RESULT_FAIL, "%s Hz in use, below the preset's %s Hz; offered %s"
			% [rate.in_use_hz, wanted_hz, rate.offered]]
	return [AcceptanceReport.RESULT_PASS, "%s Hz in use" % rate.in_use_hz]
