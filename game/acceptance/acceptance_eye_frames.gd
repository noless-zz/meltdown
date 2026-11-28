class_name AcceptanceEyeFrames
extends RefCounted

## The drawn frames an `eyes_same_frame` step samples (#1513, CMF-8, DEV-6):
## every frame for `seconds`, each read with `read` and judged with
## `AcceptanceEyePair.problem`. The first frame's fields of view are the
## runtime's for the step; a later frame whose eye differs from them (a squashed
## or swapped projection) fails, as does any frame whose eyes do not mirror or
## were not posed from the same frame.
##
## Without a stereo runtime, or where no frame is drawn, nothing is sampled and
## `skipped` says why, so the step reports skipped, not passed (decision record 0005).

## Returns `AcceptanceEyePair.read_interface`'s answer for this frame; tests pass a fake.
var read: Callable = Callable()
var seconds: float = 10.0
var limits: Dictionary = {}
## Why nothing was sampled, or "".
var skipped: String = ""
## True once the seconds have passed, or once it was skipped.
var done: bool = false
var frames_sampled: int = 0
var frames_wrong: int = 0
## What was wrong with the first wrong frame, and how far into the step it came.
var first_problem: String = ""
var first_problem_seconds: float = 0.0
## The runtime's field of view per eye, from the first sampled frame.
var reference: Array[Vector4] = []
## The eyes' distance apart on the first sampled frame.
var ipd_m: float = 0.0

var _start_usec: int = -1
var _frames: AcceptanceFrameHook = null


## Asks `frames` for drawn frames until the seconds have passed.
func start(frames: AcceptanceFrameHook) -> void:
	_frames = frames
	frames.next_drawn_frame(on_frame)


## One frame, drawn or not, at `usec` on the hook's clock.
func on_frame(drawn: bool, usec: int) -> void:
	if not drawn:
		_skip("nothing is drawn here (headless display or dummy renderer)")
		return
	var got: Variant = read.call()
	if typeof(got) != TYPE_DICTIONARY:
		_skip(str(got))
		return
	if _start_usec < 0:
		_start_usec = usec
	var at: float = float(usec - _start_usec) / 1000000.0
	var sample: Dictionary = got
	var fovs: Array[Vector4] = []
	fovs.assign(sample["fovs"])
	var eyes: Array[Transform3D] = []
	eyes.assign(sample["eyes"])
	if reference.is_empty():
		reference = fovs.duplicate()
		ipd_m = eyes[AcceptanceEyePair.LEFT].origin.distance_to(eyes[AcceptanceEyePair.RIGHT].origin)
	frames_sampled += 1
	var found: String = AcceptanceEyePair.problem(fovs, reference, eyes, limits)
	if found != "":
		frames_wrong += 1
		if first_problem == "":
			first_problem = found
			first_problem_seconds = at
	if at >= seconds:
		done = true
	elif _frames != null:
		_frames.next_drawn_frame(on_frame)


## [result, message] for the frames sampled, adding them to `measurements`.
## A skipped step fails when `required`.
func judge(required: bool, measurements: Dictionary) -> Array:
	measurements["frames_sampled"] = frames_sampled
	measurements["frames_wrong"] = frames_wrong
	measurements["seconds"] = seconds
	if skipped != "":
		measurements["skipped"] = skipped
		return [AcceptanceReport.RESULT_FAIL if required else AcceptanceReport.RESULT_SKIPPED,
			"no stereo frames to judge: %s" % skipped]
	if not done:
		return [AcceptanceReport.RESULT_FAIL, "sampled %d frames, not %.0f s of them" % [frames_sampled, seconds]]
	measurements["left_fov_deg"] = AcceptanceEyePair.describe_fov(reference[AcceptanceEyePair.LEFT])
	measurements["right_fov_deg"] = AcceptanceEyePair.describe_fov(reference[AcceptanceEyePair.RIGHT])
	measurements["ipd_m"] = snappedf(ipd_m, 0.0001)
	var fov: String = "left eye %s, right eye %s degrees (left, right, bottom, top), eyes %.1f mm apart" % [
		measurements["left_fov_deg"], measurements["right_fov_deg"], ipd_m * 1000.0]
	if frames_wrong > 0:
		measurements["first_problem"] = first_problem
		return [AcceptanceReport.RESULT_FAIL, "%d of %d frames wrong; first at %.2f s: %s; %s" % [
			frames_wrong, frames_sampled, first_problem_seconds, first_problem, fov]]
	return [AcceptanceReport.RESULT_PASS, "%d frames over %.1f s, both eyes right on every one: %s" % [
		frames_sampled, seconds, fov]]



func _skip(reason: String) -> void:
	skipped = reason
	done = true
