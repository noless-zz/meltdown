class_name AcceptanceXrSessionCheck
extends RefCounted

## The `xr_session` acceptance check (#165, DEV-6): the OpenXR session began
## within the runner's wait. Kept out of `AcceptanceRunner` so that file stays
## short (#643).


## [result, message] for the check, adding the frames waited to `measurements`.
## Without an OpenXR runtime it is skipped, or fails when `required`.
static func run(xr_available: bool, xr_begun: bool, waited_frames: int, wait_limit: int, required: bool,
		measurements: Dictionary) -> Array:
	if not xr_available:
		return [AcceptanceReport.RESULT_FAIL if required else AcceptanceReport.RESULT_SKIPPED,
			"no OpenXR runtime"]
	measurements["xr_wait_frames"] = waited_frames
	if not xr_begun:
		return [AcceptanceReport.RESULT_FAIL, "the session did not begin within %d frames" % wait_limit]
	return [AcceptanceReport.RESULT_PASS, "session began"]
