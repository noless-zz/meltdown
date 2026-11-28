extends RefCounted

## The `view_not_magnified` measure (#1513, CMF-8, PRF-1, GFX-7): a target
## drawn where the field of view says passes, and the fault of 27 Nov (#1503),
## the eye drawn at render scale 0.7 and stretched over the whole view, fails
## as magnified. The pictures are painted here, as the eye would show them.

const SIZE: Vector2i = Vector2i(400, 400)
const DISTANCE: float = 2.0
const HALF_SIZE: float = 0.25
const TOLERANCE: float = 0.06


static func _projection() -> Projection:
	return Projection.create_perspective(90.0, 1.0, 0.05, 100.0)


static func _expected() -> Rect2:
	return AcceptanceMagnify.expected_rect(_projection(), Vector3(0.0, 0.0, -DISTANCE), HALF_SIZE, SIZE)


## The tunnel as drawn: dark, with the target where `rect` says.
static func _picture(rect: Rect2) -> Image:
	var image: Image = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08))
	image.fill_rect(Rect2i(Vector2i(rect.position.round()), Vector2i(rect.size.round())), AcceptanceMagnify.TARGET_COLOUR)
	return image


## What the Quest showed on 27 Nov: only the middle `scale` of the eye's view, stretched over all of it.
static func _stretched(image: Image, scale: float) -> Image:
	var kept: Vector2i = Vector2i(roundi(SIZE.x * scale), roundi(SIZE.y * scale))
	var middle: Image = image.get_region(Rect2i((SIZE - kept) / 2, kept))
	middle.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_BILINEAR)
	return middle


func test_the_expected_rect_follows_the_field_of_view() -> String:
	# 90 degrees across 400 px: tan = 0.25 / 2 = 0.125 of the half width, 25 px each side.
	var rect: Rect2 = _expected()
	if not rect.position.is_equal_approx(Vector2(175.0, 175.0)) or not rect.size.is_equal_approx(Vector2(50.0, 50.0)):
		return "gave %s" % rect
	return ""


func test_a_target_where_the_view_says_passes() -> String:
	var measured: Vector2 = AcceptanceMagnify.measure(_picture(_expected()), _expected())
	var verdict: Array = AcceptanceMagnify.judge(_expected(), measured, TOLERANCE, {})
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else "gave %s" % [verdict]


func test_render_scale_0_7_stretched_fails_as_magnified() -> String:
	var picture: Image = _stretched(_picture(_expected()), 0.7)
	var measurements: Dictionary = {}
	var verdict: Array = AcceptanceMagnify.judge(_expected(), AcceptanceMagnify.measure(picture, _expected()),
		TOLERANCE, measurements)
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).begins_with("the picture is magnified"):
		return "gave %s" % [verdict]
	var ratio: float = float((measurements["size_ratio"] as Array)[0])
	return "" if absf(ratio - 1.0 / 0.7) < 0.05 else "ratio %s, want about 1.43" % ratio


func test_a_slightly_stretched_view_within_tolerance_passes() -> String:
	var picture: Image = _stretched(_picture(_expected()), 0.98)
	var verdict: Array = AcceptanceMagnify.judge(_expected(), AcceptanceMagnify.measure(picture, _expected()),
		TOLERANCE, {})
	return "" if verdict[0] == AcceptanceReport.RESULT_PASS else "gave %s" % [verdict]


func test_a_shrunk_view_fails_as_shrunk() -> String:
	var small: Rect2 = Rect2(_expected().get_center() - _expected().size * 0.4, _expected().size * 0.8)
	var verdict: Array = AcceptanceMagnify.judge(_expected(), AcceptanceMagnify.measure(_picture(small), _expected()),
		TOLERANCE, {})
	return "" if verdict[0] == AcceptanceReport.RESULT_FAIL and str(verdict[1]).contains("shrunk") else "gave %s" % [verdict]


func test_a_missing_target_fails() -> String:
	var picture: Image = _picture(Rect2())
	var verdict: Array = AcceptanceMagnify.judge(_expected(), AcceptanceMagnify.measure(picture, _expected()),
		TOLERANCE, {})
	return "" if verdict[0] == AcceptanceReport.RESULT_FAIL and str(verdict[1]).contains("not in the picture") \
		else "gave %s" % [verdict]


func test_a_target_behind_the_eye_has_no_rect() -> String:
	var rect: Rect2 = AcceptanceMagnify.expected_rect(_projection(), Vector3(0.0, 0.0, DISTANCE), HALF_SIZE, SIZE)
	return "" if rect.size == Vector2.ZERO else "gave %s" % rect
