class_name AcceptanceMagnify
extends RefCounted

## Whether the picture is drawn at the size the field of view says, for the m1
## `view_not_magnified` step (#1513, CMF-8, PRF-1, GFX-7, DEV-6). On 27 Nov
## the Quest drew its eyes at a render scale of 0.7 and stretched the result
## over the whole view (#1503): everything looked 1/0.7 = 1.43 times too big.
## No flat screenshot showed it, so the check measures it. A target of known
## size at a known distance straight ahead must cover, in the drawn picture,
## the pixels the eye's projection puts it on, within `tolerance` of its width
## and height.
##
## Pure: `expected_rect` projects, `measure` finds the target's colour in an
## image, `judge` compares. Tests paint their own pictures.

## The target's colour: a magenta nothing in the mine has, so it cannot be mistaken.
const TARGET_COLOUR: Color = Color(1.0, 0.0, 1.0)
## A pixel is the target's when red and blue are both over this and green under `MAX_GREEN`.
const MIN_RED_BLUE: float = 0.5
const MAX_GREEN: float = 0.35
## How far outside the expected rect the search goes, as a share of its size, so
## a target up to this much too big is still measured whole.
const SEARCH_MARGIN: float = 1.0


## Where a square target, `half_size` metres from its centre to each side and
## facing the eye at `centre` (in the eye's space, -z ahead), lands in a picture
## of `size` pixels drawn with `projection`: its rect in pixels, y down.
## An empty rect when a corner is behind the eye.
static func expected_rect(projection: Projection, centre: Vector3, half_size: float, size: Vector2i) -> Rect2:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for side: float in [-1.0, 1.0]:
		for up: float in [-1.0, 1.0]:
			var point: Vector3 = centre + Vector3(side * half_size, up * half_size, 0.0)
			var clip: Vector4 = projection * Vector4(point.x, point.y, point.z, 1.0)
			if clip.w <= 0.0:
				return Rect2()
			var pixel: Vector2 = Vector2((clip.x / clip.w + 1.0) * 0.5 * size.x, (1.0 - clip.y / clip.w) * 0.5 * size.y)
			low = low.min(pixel)
			high = high.max(pixel)
	return Rect2(low, high - low)


## The target's width and height in pixels in `image`, measured along the row
## and the column through the middle of `expected`, from the first to the last
## target pixel within `SEARCH_MARGIN` around it. Zero where none is found.
static func measure(image: Image, expected: Rect2) -> Vector2:
	var picture: Image = image
	if picture.is_compressed():
		picture = image.duplicate() as Image
		picture.decompress()
	var middle: Vector2i = Vector2i(expected.get_center().round())
	var reach: Vector2 = expected.size * SEARCH_MARGIN
	var width: int = _span(picture, middle, Vector2i(1, 0), int(expected.position.x - reach.x),
		int(expected.end.x + reach.x))
	var height: int = _span(picture, middle, Vector2i(0, 1), int(expected.position.y - reach.y),
		int(expected.end.y + reach.y))
	return Vector2(width, height)


## True when `colour` is the target's.
static func is_target(colour: Color) -> bool:
	return colour.r > MIN_RED_BLUE and colour.b > MIN_RED_BLUE and colour.g < MAX_GREEN


## [result, message] for a target measured at `measured` pixels where `expected`
## says it should be, adding both to `measurements`. Fails when the width or the
## height is off by more than `tolerance` (a share), naming how much bigger or smaller.
static func judge(expected: Rect2, measured: Vector2, tolerance: float, measurements: Dictionary) -> Array:
	measurements["expected_px"] = [snappedf(expected.size.x, 0.1), snappedf(expected.size.y, 0.1)]
	measurements["measured_px"] = [measured.x, measured.y]
	if expected.size.x < 1.0 or expected.size.y < 1.0:
		return [AcceptanceReport.RESULT_FAIL, "the target is not in front of the eye"]
	if measured.x <= 0.0 or measured.y <= 0.0:
		return [AcceptanceReport.RESULT_FAIL, "the target is not in the picture (expected %.0f x %.0f px)" % [
			expected.size.x, expected.size.y]]
	var ratio: Vector2 = measured / expected.size
	measurements["size_ratio"] = [snappedf(ratio.x, 0.001), snappedf(ratio.y, 0.001)]
	var detail: String = "target %.0f x %.0f px, field of view says %.0f x %.0f px (x%.3f wide, x%.3f tall)" % [
		measured.x, measured.y, expected.size.x, expected.size.y, ratio.x, ratio.y]
	if absf(ratio.x - 1.0) > tolerance or absf(ratio.y - 1.0) > tolerance:
		var worst: float = ratio.x if absf(ratio.x - 1.0) >= absf(ratio.y - 1.0) else ratio.y
		var how: String = "magnified" if worst > 1.0 else "shrunk"
		return [AcceptanceReport.RESULT_FAIL, "the picture is %s: %s; at most %d%% off allowed" % [
			how, detail, roundi(tolerance * 100.0)]]
	return [AcceptanceReport.RESULT_PASS, "%s; within %d%%" % [detail, roundi(tolerance * 100.0)]]


## The count of pixels from the first to the last target pixel on the line
## through `middle` along `step`, between `from` and `to` on that axis.
static func _span(image: Image, middle: Vector2i, step: Vector2i, from: int, to: int) -> int:
	var axis: int = 0 if step.x != 0 else 1
	var limit: int = image.get_width() if axis == 0 else image.get_height()
	var across: int = middle.y if axis == 0 else middle.x
	var across_limit: int = image.get_height() if axis == 0 else image.get_width()
	if across < 0 or across >= across_limit:
		return 0
	var first: int = -1
	var last: int = -1
	for index: int in range(maxi(from, 0), mini(to + 1, limit)):
		var pixel: Vector2i = Vector2i(index, across) if axis == 0 else Vector2i(across, index)
		if is_target(image.get_pixelv(pixel)):
			if first < 0:
				first = index
			last = index
	return 0 if first < 0 else last - first + 1
