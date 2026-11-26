extends RefCounted

## The launch fade's states and times (#1396, CMF-1, CMF-3, CMF-8, ARC-4): the
## glow rises, then the colour fades in to full, the launch is due once, then
## the colour fades out; times and colour come from the look file, and a
## refused file falls back to built-in values with a warning.

const SHIPPED: String = "res://xr/launch_fade.json"
const SCRATCH: String = "user://t1396_launch_fade.json"
const STEP: float = 1.0 / 72.0


func _fade() -> LaunchFade:
	return LaunchFade.new({"glow_seconds": 0.6, "fade_out_seconds": 0.5, "fade_in_seconds": 0.5,
		"color": Color(0.0, 0.0, 0.0)})


func test_the_shipped_file_is_accepted_with_the_issue_times() -> String:
	var values: Dictionary = LaunchFade.parse(FileAccess.get_file_as_string(SHIPPED))
	if values.has("error"):
		return "the shipped launch fade is rejected: %s" % values["error"]
	if absf(values["glow_seconds"] - 0.6) > 0.15 or absf(values["fade_out_seconds"] - 0.5) > 0.15 \
			or absf(values["fade_in_seconds"] - 0.5) > 0.15:
		return "the shipped times are %s, expected about 0.6, 0.5 and 0.5" % values
	return ""


func test_idle_shows_nothing() -> String:
	var fade: LaunchFade = _fade()
	if fade.alpha() != 0.0 or fade.glow() != 0.0 or fade.is_launching() or fade.advance(1.0):
		return "an idle fade shows something or launches"
	return ""


func test_a_launch_glows_then_fades_out_then_is_due_once_then_fades_in() -> String:
	var fade: LaunchFade = _fade()
	if not fade.start_launch() or fade.state != LaunchFade.State.GLOW:
		return "the launch did not start with the glow"
	if fade.start_launch():
		return "a second press restarted a launch under way"
	fade.advance(0.3)
	if absf(fade.glow() - 0.5) > 0.01 or fade.alpha() != 0.0:
		return "half way through the glow: glow %.2f, alpha %.2f" % [fade.glow(), fade.alpha()]
	fade.advance(0.3)
	if fade.state != LaunchFade.State.FADE_OUT or fade.glow() != 1.0:
		return "after 0.6 s the fade out did not begin with the glow full"
	fade.advance(0.25)
	if absf(fade.alpha() - 0.5) > 0.01 or not fade.is_launching():
		return "half way through the fade out the alpha is %.2f" % fade.alpha()
	if not fade.advance(0.25):
		return "the launch was not due when the fade out was full"
	if fade.alpha() != 1.0 or fade.state != LaunchFade.State.FADE_IN or fade.is_launching():
		return "on the due frame the view is not fully dark and fading in"
	fade.advance(0.25)
	if absf(fade.alpha() - 0.5) > 0.01:
		return "half way through the fade in the alpha is %.2f" % fade.alpha()
	if fade.advance(0.25) or fade.state != LaunchFade.State.IDLE or fade.alpha() != 0.0:
		return "the fade in did not end clear and idle"
	return ""


func test_at_frame_steps_the_alpha_never_reverses_and_is_due_once() -> String:
	var fade: LaunchFade = _fade()
	fade.start_launch()
	var dues: int = 0
	var last: float = 0.0
	var dark_seen: bool = false
	for i: int in 200:
		if fade.advance(STEP):
			dues += 1
			dark_seen = fade.alpha() == 1.0
			last = 1.0
			continue
		var now: float = fade.alpha()
		if dues == 0 and now < last:
			return "the fade out went down at frame %d" % i
		if dues == 1 and now > last:
			return "the fade in went up at frame %d" % i
		last = now
	if dues != 1 or not dark_seen or fade.state != LaunchFade.State.IDLE:
		return "%d launches due, dark %s, state %d" % [dues, dark_seen, fade.state]
	return ""


func test_a_long_frame_through_the_glow_carries_into_the_fade_out() -> String:
	var fade: LaunchFade = _fade()
	fade.start_launch()
	if fade.advance(0.85):
		return "the launch was due before the fade out ended"
	if fade.state != LaunchFade.State.FADE_OUT or absf(fade.alpha() - 0.5) > 0.01:
		return "the glow's leftover time was not carried: %d, alpha %.2f" % [fade.state, fade.alpha()]
	var instant: LaunchFade = LaunchFade.new({"glow_seconds": 0.0, "fade_out_seconds": 0.5,
		"fade_in_seconds": 0.5, "color": Color.BLACK})
	instant.start_launch()
	if instant.advance(0.0) or instant.state != LaunchFade.State.FADE_OUT:
		return "a zero glow did not go straight to the fade out"
	return ""


func test_arriving_fades_in_from_dark() -> String:
	var fade: LaunchFade = _fade()
	fade.start_fade_in()
	if fade.alpha() != 1.0 or fade.is_launching() or fade.glow() != 0.0:
		return "arriving does not start dark without a glow"
	fade.advance(0.5)
	if fade.alpha() != 0.0 or fade.state != LaunchFade.State.IDLE:
		return "the arrival did not clear after its fade in"
	return ""


func test_the_file_sets_the_times_and_colour() -> String:
	var values: Dictionary = LaunchFade.parse(
		"{\"glow_seconds\": 1, \"fade_out_seconds\": 0.8, \"fade_in_seconds\": 0.4, \"color\": [0.1, 0, 0.2]}")
	if values.has("error"):
		return "a good file is rejected: %s" % values["error"]
	var fade: LaunchFade = LaunchFade.new(values)
	if fade.glow_seconds != 1.0 or fade.fade_out_seconds != 0.8 or fade.fade_in_seconds != 0.4 \
			or not fade.color.is_equal_approx(Color(0.1, 0.0, 0.2)):
		return "the file's values are not used: %s" % values
	return ""


func test_bad_files_name_the_field() -> String:
	var cases: Dictionary = {
		"[]": "top level",
		"{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.5, \"color\": [0, 0, 0]}": "fade_in_seconds",
		"{\"glow_seconds\": true, \"fade_out_seconds\": 0.5, \"fade_in_seconds\": 0.5, \"color\": [0, 0, 0]}": "glow_seconds",
		"{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.0, \"fade_in_seconds\": 0.5, \"color\": [0, 0, 0]}": "fade_out_seconds",
		"{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.5, \"fade_in_seconds\": 9, \"color\": [0, 0, 0]}": "fade_in_seconds",
		"{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.5, \"fade_in_seconds\": 0.5, \"color\": [1, 1, 1]}": "never a flash",
		"{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.5, \"fade_in_seconds\": 0.5, \"color\": [0, 0]}": "color",
		"{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.5, \"fade_in_seconds\": 0.5, \"color\": [0, 0, 0], \"flash\": 1}": "flash",
	}
	for text: String in cases:
		var values: Dictionary = LaunchFade.parse(text)
		if not values.has("error") or not str(values["error"]).contains(cases[text]):
			return "%s gave %s, expected an error naming %s" % [text, values, cases[text]]
	return ""


func test_a_refused_file_falls_back_to_the_built_in_values() -> String:
	var file: FileAccess = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("{\"glow_seconds\": 0.6, \"fade_out_seconds\": 0.5, \"fade_in_seconds\": 0.5, \"color\": [1, 1, 1]}")
	file.close()
	var fade: LaunchFade = LaunchFade.load_file(SCRATCH)  # Pushes the warning naming the colour.
	DirAccess.remove_absolute(SCRATCH)
	var missing: LaunchFade = LaunchFade.load_file("user://t1396_no_such_file.json")
	for each: LaunchFade in [fade, missing]:
		if each.glow_seconds != LaunchFade.FALLBACK["glow_seconds"] \
				or each.fade_out_seconds != LaunchFade.FALLBACK["fade_out_seconds"] \
				or each.fade_in_seconds != LaunchFade.FALLBACK["fade_in_seconds"] or each.color != Color.BLACK:
			return "a refused or missing file did not fall back to the built-in values"
	return ""
