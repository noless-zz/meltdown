extends RefCounted

## `view_not_flat` puts what it measured in its step message, pass or fail
## (#1439, DEV-6, PRF-1): on the headset the step failed with foveation off and
## its message was lost, so nobody could tell a flat picture from a dim one.

const ImageHelpers := preload("res://tests/test_acceptance_view_flat_check.gd")


## A pass names the stddev range and median, the colour range and both limits.
func test_a_pass_names_the_measured_spread_and_the_limits() -> String:
	var check: AcceptanceViewFlatCheck = AcceptanceViewFlatCheck.from_file()
	check.sample(ImageHelpers._tunnel_image(), 2.0)
	check.sample(ImageHelpers._dark_textured_image(), 4.0)
	var measured: Dictionary = {}
	var verdict: Array = check.judge(measured)
	var message: String = str(verdict[1])
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "gave %s" % [verdict]
	return _names_everything(check, message, measured)


## A fail names the first flat sample and, beside it, the same spread and limits.
func test_a_fail_names_the_measured_spread_and_the_limits() -> String:
	var check: AcceptanceViewFlatCheck = AcceptanceViewFlatCheck.from_file()
	check.sample(ImageHelpers._tunnel_image(), 2.0)
	check.sample(ImageHelpers._flat_image(Color(0.4, 0.3, 0.2), 0.0), 4.0)
	var measured: Dictionary = {}
	var verdict: Array = check.judge(measured)
	var message: String = str(verdict[1])
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not message.contains("flat at 4.00 s"):
		return "gave %s" % [verdict]
	if float(measured["lowest_luminance_stddev"]) != 0.0 or int(measured["fewest_colours"]) != 1:
		return "measured %s" % measured
	return _names_everything(check, message, measured)


static func _names_everything(check: AcceptanceViewFlatCheck, message: String, measured: Dictionary) -> String:
	var wanted: Array[String] = [
		"luminance stddev %s to %s" % [measured["lowest_luminance_stddev"], measured["highest_luminance_stddev"]],
		"(median %s)" % measured["median_luminance_stddev"],
		"%d to %d colours" % [int(measured["fewest_colours"]), int(measured["most_colours"])],
		"stddev under %s" % check.flat_stddev_below,
		"fewer than %d colours" % check.flat_colours_below,
	]
	for part: String in wanted:
		if not message.contains(part):
			return "'%s' does not say '%s'" % [message, part]
	return ""
