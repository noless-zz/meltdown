extends RefCounted

## The scaler's frame times without the wait for the display (#1509, GFX-7,
## PRF-1): the CPU time is the sum of its work parts and nothing else, a bad
## part counts as 0, the scripts' time is read once per mark, and the scaler
## processes after every other node so that time covers theirs.


func test_the_cpu_time_is_the_sum_of_its_parts() -> String:
	var total: float = RenderFrameTimes.cpu_ms_of(1.5, 0.3, 0.25, 1.4)
	if not is_equal_approx(total, 3.45):
		return "1.5 + 0.3 + 0.25 + 1.4 gave %s" % total
	return ""


func test_a_bad_part_counts_as_zero() -> String:
	for bad: float in [-4.0, NAN, INF, -INF]:
		var total: float = RenderFrameTimes.cpu_ms_of(1.0, bad, 0.5, 2.0)
		if not is_equal_approx(total, 3.5):
			return "a part of %s gave %s, expected 3.5" % [bad, total]
	return ""


func test_the_scripts_time_runs_from_the_mark_and_is_read_once() -> String:
	var times: RenderFrameTimes = RenderFrameTimes.new()
	if times.script_ms(5000) != 0.0:
		return "no mark yet, yet %s ms" % times.script_ms(5000)
	times.begin_process(10000)
	var first: float = times.script_ms(12500)
	if not is_equal_approx(first, 2.5):
		return "10000 to 12500 us gave %s ms" % first
	if times.script_ms(20000) != 0.0:
		return "the mark was read twice"
	times.begin_process(30000)
	if times.script_ms(29000) != 0.0:
		return "a clock before the mark gave time"
	return ""


func test_the_scripts_time_uses_the_clock_by_default() -> String:
	var times: RenderFrameTimes = RenderFrameTimes.new()
	times.begin_process()
	var ms: float = times.script_ms()
	if ms < 0.0 or ms > 1000.0:
		return "an immediate read gave %s ms" % ms
	return ""


func test_the_scaler_processes_last_and_owns_its_timer() -> String:
	var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify({"enabled": true, "floor": 0.7,
		"ceiling": 1.0, "step": 0.1, "high_water": 0.9, "low_water": 0.7, "frames_down": 5,
		"frames_up": 45, "interval_frames": 30}))
	var scaler: RenderScaler = RenderScaler.new(RenderScaleController.new(table))
	var problem: String = ""
	if scaler.process_priority != RenderScaler.PROCESS_LAST or RenderScaler.PROCESS_LAST < 1000:
		problem = "process priority %d" % scaler.process_priority
	elif scaler.frame_times == null:
		problem = "no frame timer"
	scaler.free()
	return problem


func test_the_scaler_no_longer_reads_the_process_time() -> String:
	# TIME_PROCESS spans RenderingServer.draw, so it holds the display wait (#1509).
	var source: String = FileAccess.get_file_as_string("res://xr/render_scaler.gd")
	if source.contains("Performance.TIME_PROCESS") or source.contains("Performance.get_monitor(Performance.TIME_PROCESS"):
		return "render_scaler.gd still reads TIME_PROCESS"
	var times: String = FileAccess.get_file_as_string("res://xr/render_frame_times.gd")
	if times.contains("get_monitor(Performance.TIME_PROCESS)"):
		return "render_frame_times.gd reads TIME_PROCESS"
	return ""
