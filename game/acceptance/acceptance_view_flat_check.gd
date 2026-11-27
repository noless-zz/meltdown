class_name AcceptanceViewFlatCheck
extends RefCounted

## The `view_not_flat` acceptance check (#737, part 1 of #734; DEV-6, PRF-1,
## GFX-1, CMF-8): on the headset, the eye image must never collapse to one
## flat colour. With foveated rendering at level 3, dynamic, the Quest 3's
## whole picture went to one colour every 20 to 30 s (#651, #664, #730) and
## nothing automated noticed; this step is what would have.
##
## While the step runs, the runner hands every frame's duration to `add`.
## Every `sample_interval_seconds` the eye image is read (the same image the
## step screenshots of #718 save) and judged on a `sample_size` square copy:
## a sample is **flat** when its luminance standard deviation is under
## `flat_luminance_stddev_below` and it holds fewer than `flat_colours_below`
## distinct colours, each channel quantised to `colour_levels` steps. Both
## must hold, so a dark but textured tunnel is not flat and neither is a
## smooth gradient. The numbers live in `view_flat.json` (ARC-4) so they can be
## tuned after the first device runs.
##
## Off the headset the check is skipped: the desktop draws no eye image, and
## Monado's null compositor gives none worth judging (decision record 0005).
## Reading the image only reads the viewport; nothing here touches the session.

const DATA_PATH: String = "res://acceptance/view_flat.json"
## The suite key a view_not_flat step must list, and no other step may.
const KEY_SECONDS: String = "view_seconds"
const STEP_KEYS: Array[String] = [KEY_SECONDS]
## Longer than this is a mistyped suite, not a check.
const MAX_SECONDS: float = 600.0
## The issue asks for a sample at least every 2 s: the collapse lasted a moment.
const MAX_INTERVAL_SECONDS: float = 2.0
const DATA_KEYS: Array[String] = ["sample_interval_seconds", "sample_size", "colour_levels",
	"flat_luminance_stddev_below", "flat_colours_below"]

## The data file's values; `error` says why they could not be read, or "".
var interval_seconds: float = MAX_INTERVAL_SECONDS
var sample_size: int = 64
var colour_levels: int = 16
var flat_stddev_below: float = 0.0
var flat_colours_below: int = 0
var error: String = ""
## How long the step samples.
var seconds: float = 0.0
## Returns the eye Image, or a String saying why there is none.
var grab: Callable = Callable()
## One entry per sample judged: `time`, `stddev`, `colours`, `flat`.
var samples: Array[Dictionary] = []
## Samples whose image could not be read, and the first reason.
var unread: int = 0
var unread_reason: String = ""

var _seen_seconds: float = 0.0
var _next_sample: float = 0.0


## Reads the thresholds from `path`; `error` is set when they are unusable.
static func from_file(path: String = DATA_PATH) -> AcceptanceViewFlatCheck:
	var check: AcceptanceViewFlatCheck = AcceptanceViewFlatCheck.new()
	check.error = check._load(path)
	check._next_sample = check.interval_seconds
	return check


## The sampler for `step`, or null when the step does not list the check or
## the image is not judged here.
static func for_step(step: AcceptanceStep, xr_available: bool, on_headset: bool,
		p_grab: Callable) -> AcceptanceViewFlatCheck:
	if not step.has_check(AcceptanceStep.CHECK_VIEW_NOT_FLAT) \
			or not AcceptanceFrameBudgetCheck.measures_here(xr_available, on_headset):
		return null
	var check: AcceptanceViewFlatCheck = from_file()
	check.seconds = step.view_seconds
	check.grab = p_grab
	return check


## Counts one frame and samples the image when one is due.
func add(frame_seconds: float) -> void:
	if done() or not frame_seconds > 0.0:
		return
	_seen_seconds += frame_seconds
	if _seen_seconds < _next_sample:
		return
	_next_sample += interval_seconds
	var got: Variant = grab.call() if grab.is_valid() else "nothing to read the image with"
	if got is Image and not (got as Image).is_empty():
		sample(got as Image, _seen_seconds)
	else:
		unread += 1
		if unread_reason == "":
			unread_reason = "empty image" if got is Image else str(got)


## Whether the step has sampled for its whole length, or cannot sample at all.
func done() -> bool:
	return error != "" or _seen_seconds >= seconds


## Judges one image taken `time` seconds into the step and keeps the result.
func sample(image: Image, time: float) -> Dictionary:
	var measured: Dictionary = measure(image, sample_size, colour_levels)
	measured["time"] = snappedf(time, 0.01)
	measured["flat"] = float(measured["stddev"]) < flat_stddev_below \
		and int(measured["colours"]) < flat_colours_below
	samples.append(measured)
	return measured


## `stddev` (luminance, 0 to 1) and `colours` (distinct after quantising each
## channel to `levels` steps) of `image` scaled to `size` square. Works on a copy.
static func measure(image: Image, size: int, levels: int) -> Dictionary:
	var copy: Image = image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGB8)
	if copy.get_width() != size or copy.get_height() != size:
		copy.resize(size, size, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	var total_squares: float = 0.0
	var seen: Dictionary = {}
	for y: int in size:
		for x: int in size:
			var colour: Color = copy.get_pixel(x, y)
			var luminance: float = 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
			total += luminance
			total_squares += luminance * luminance
			seen[_quantised(colour.r, levels) * levels * levels + _quantised(colour.g, levels) * levels
				+ _quantised(colour.b, levels)] = true
	var count: float = float(size * size)
	var mean: float = total / count
	var variance: float = maxf(total_squares / count - mean * mean, 0.0)
	return {"stddev": snappedf(sqrt(variance), 0.0001), "colours": seen.size()}


static func _quantised(channel: float, levels: int) -> int:
	return clampi(int(channel * levels), 0, levels - 1)


## Reads the view_not_flat key of one suite step. Returns the problem, or "".
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wanted: bool = step.has_check(AcceptanceStep.CHECK_VIEW_NOT_FLAT)
	if not data.has(KEY_SECONDS):
		return "%s.%s: needed by the view_not_flat check" % [field, KEY_SECONDS] if wanted else ""
	if not wanted:
		return "%s.%s: only used by the view_not_flat check, which the step does not list" % [
			field, KEY_SECONDS]
	var value: Variant = data[KEY_SECONDS]
	# A bool must not pass as 0 or 1.
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)) \
			or float(value) < MAX_INTERVAL_SECONDS or float(value) > MAX_SECONDS:
		return "%s.%s: must be a number from %s to %s" % [field, KEY_SECONDS, MAX_INTERVAL_SECONDS,
			MAX_SECONDS]
	step.view_seconds = float(value)
	return ""


## [result, message] for the check, adding the numbers to `measurements`.
static func run(xr_available: bool, on_headset: bool, step: AcceptanceStep,
		measured: AcceptanceViewFlatCheck, measurements: Dictionary) -> Array:
	if not AcceptanceFrameBudgetCheck.measures_here(xr_available, on_headset) or measured == null:
		return [AcceptanceReport.RESULT_FAIL if step.required else AcceptanceReport.RESULT_SKIPPED,
			AcceptanceFrameBudgetCheck.not_measured_reason(xr_available)]
	var verdict: Array = measured.judge(measurements)
	# Also into the device log: a later hang lost the report and this message with it (#1439).
	print("%s: %s %s: %s" % [AcceptanceRunner.LOG_PREFIX, AcceptanceStep.CHECK_VIEW_NOT_FLAT, verdict[0], verdict[1]])
	return verdict


## [result, message] for the samples taken.
func judge(measurements: Dictionary) -> Array:
	if error != "":
		return [AcceptanceReport.RESULT_FAIL, error]
	var flat_times: Array[float] = []
	var first_flat: Dictionary = {}
	var lowest: Dictionary = {}
	for entry: Dictionary in samples:
		if lowest.is_empty() or float(entry["stddev"]) < float(lowest["stddev"]):
			lowest = entry
		if entry["flat"]:
			flat_times.append(float(entry["time"]))
			if first_flat.is_empty():
				first_flat = entry
	measurements["samples"] = samples.size()
	measurements["flat_samples"] = flat_times.size()
	measurements["flat_sample_seconds"] = flat_times
	measurements["unread_samples"] = unread
	if not lowest.is_empty():
		measurements["lowest_luminance_stddev"] = lowest["stddev"]
		measurements["lowest_at_seconds"] = lowest["time"]
	if samples.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no eye image could be read: %s" % (
			unread_reason if unread_reason != "" else "no sample was due")]
	var spread: Dictionary = spread_of(samples)
	for key: String in spread:
		measurements[key] = spread[key]
	var limits: String = "flat is luminance stddev under %s with fewer than %d colours" % [
		flat_stddev_below, flat_colours_below]
	var measured: String = "luminance stddev %s to %s (median %s), %d to %d colours" % [
		spread["lowest_luminance_stddev"], spread["highest_luminance_stddev"], spread["median_luminance_stddev"],
		int(spread["fewest_colours"]), int(spread["most_colours"])]
	var unread_note: String = "; %d unread: %s" % [unread, unread_reason] if unread > 0 else ""
	if not first_flat.is_empty():
		var first: String = "flat at %.2f s: luminance stddev %s, %d colours" % [float(first_flat["time"]),
			first_flat["stddev"], int(first_flat["colours"])]
		return [AcceptanceReport.RESULT_FAIL, "%s; %d of %d samples flat; %s (%s)%s" % [first,
			flat_times.size(), samples.size(), measured, limits, unread_note]]
	var summary: String = "%d samples, none flat; lowest luminance stddev %s at %.2f s; %s (%s)%s" % [
		samples.size(), lowest["stddev"], float(lowest["time"]), measured, limits, unread_note]
	return [AcceptanceReport.RESULT_PASS, summary]


## The range of the samples' luminance stddev and colour counts, so a step
## message shows how far the view was from the limits, pass or fail (#1439).
static func spread_of(taken: Array[Dictionary]) -> Dictionary:
	var stddevs: Array[float] = []
	var colours: Array[int] = []
	for entry: Dictionary in taken:
		stddevs.append(float(entry["stddev"]))
		colours.append(int(entry["colours"]))
	stddevs.sort()
	colours.sort()
	return {"lowest_luminance_stddev": stddevs[0], "highest_luminance_stddev": stddevs[-1],
		"median_luminance_stddev": stddevs[stddevs.size() / 2], "fewest_colours": colours[0],
		"most_colours": colours[-1]}


## Reads and checks the data file. Returns the problem, or "".
func _load(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return "%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())]
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "%s: not a JSON object" % path
	var data: Dictionary = parsed
	for key: String in data.keys():
		if not DATA_KEYS.has(key):
			return "%s.%s: unknown key" % [path, key]
	for key: String in DATA_KEYS:
		if not data.has(key):
			return "%s.%s: missing" % [path, key]
		# A bool must not pass as 0 or 1.
		if (typeof(data[key]) != TYPE_FLOAT and typeof(data[key]) != TYPE_INT) or not is_finite(float(data[key])):
			return "%s.%s: must be a number" % [path, key]
	interval_seconds = float(data["sample_interval_seconds"])
	flat_stddev_below = float(data["flat_luminance_stddev_below"])
	if not interval_seconds > 0.0 or interval_seconds > MAX_INTERVAL_SECONDS:
		return "%s.sample_interval_seconds: must be above 0 and at most %s" % [path, MAX_INTERVAL_SECONDS]
	if not flat_stddev_below > 0.0 or flat_stddev_below > 0.5:
		return "%s.flat_luminance_stddev_below: must be above 0 and at most 0.5" % path
	for key: String in ["sample_size", "colour_levels", "flat_colours_below"]:
		if float(data[key]) != floorf(float(data[key])) or float(data[key]) < 2.0 or float(data[key]) > 256.0:
			return "%s.%s: must be a whole number from 2 to 256" % [path, key]
	sample_size = int(data["sample_size"])
	colour_levels = int(data["colour_levels"])
	flat_colours_below = int(data["flat_colours_below"])
	return ""
