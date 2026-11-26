extends RefCounted

## Dynamic resolution scaling's controller (#1417, GFX-7, PRF-2, PRF-3,
## ARC-3): it holds 1.0 under budget, steps down after a sustained overrun
## and not before, steps back up with headroom, never below the floor, at
## most once per interval, is always 1.0 when off, and holds on a frame with
## no rate or time.

const HZ: float = 90.0
const BUDGET_MS: float = 1000.0 / 90.0


func _table(changes: Dictionary = {}) -> RenderScaleTable:
	var data: Dictionary = {"enabled": true, "floor": 0.7, "ceiling": 1.0, "step": 0.1,
		"high_water": 0.9, "low_water": 0.7, "frames_down": 5, "frames_up": 45, "interval_frames": 30}
	data.merge(changes, true)
	var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify(data))
	assert(table.error == "", table.error)
	return table


## Runs `frames` frames whose GPU time is `share` of the budget; the scale after each.
static func _run(controller: RenderScaleController, frames: int, share: float) -> Array[float]:
	var scales: Array[float] = []
	for i: int in frames:
		scales.append(controller.advance(BUDGET_MS * share * 0.5, BUDGET_MS * share, HZ))
	return scales


func test_it_holds_at_full_under_budget() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table())
	var scales: Array[float] = _run(controller, 900, 0.8)
	scales.append_array(_run(controller, 900, 0.3))
	if scales.min() != 1.0:
		return "the scale dropped to %s under budget" % scales.min()
	return ""


func test_it_steps_down_only_after_a_sustained_overrun() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table())
	# Four long frames, then one in between, many times: never five in a row.
	for i: int in 50:
		_run(controller, 4, 1.2)
		_run(controller, 1, 0.8)
	if controller.scale != 1.0:
		return "broken runs of long frames lowered the scale to %s" % controller.scale
	var scales: Array[float] = _run(controller, 5, 1.2)
	if scales[3] != 1.0 or scales[4] != 0.9:
		return "five long frames in a row gave %s, expected one step to 0.9 on the fifth" % [scales]
	return ""


func test_it_steps_back_up_with_headroom() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table())
	_run(controller, 5, 1.2)
	if controller.scale != 0.9:
		return "did not step down first: %s" % controller.scale
	var scales: Array[float] = _run(controller, 45, 0.5)
	if scales[43] != 0.9 or scales[44] != 1.0:
		return "45 frames with headroom gave %s, expected 1.0 on the 45th" % [scales.slice(40)]
	scales = _run(controller, 600, 0.5)
	if scales.max() != 1.0:
		return "the scale rose above 1.0: %s" % scales.max()
	return ""


func test_it_respects_the_floor_and_the_interval() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table())
	var scales: Array[float] = _run(controller, 600, 2.0)
	if scales.min() != 0.7:
		return "the lowest scale was %s, the floor is 0.7" % scales.min()
	var last: float = 1.0
	var since: int = 0
	var changes: int = 0
	for scale: float in scales:
		since += 1
		if scale != last:
			changes += 1
			if changes > 1 and since < 30:
				return "two changes %d frames apart" % since
			since = 0
			last = scale
	if changes != 3:
		return "%d changes from 1.0 to the 0.7 floor, expected 3" % changes
	return ""


func test_the_ceiling_and_a_step_past_the_floor_are_clamped() -> String:
	var controller: RenderScaleController = RenderScaleController.new(
		_table({"ceiling": 0.95, "floor": 0.6, "step": 0.25, "interval_frames": 0}))
	if controller.scale != 0.95:
		return "a 0.95 ceiling starts at %s" % controller.scale
	var low: float = (_run(controller, 300, 1.5) as Array).min()
	var high: float = (_run(controller, 900, 0.2) as Array).max()
	if low != 0.6 or high != 0.95 or controller.scale != 0.95:
		return "went %s to %s, expected 0.6 to 0.95" % [low, high]
	return ""


func test_off_in_the_file_is_always_full() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table({"enabled": false}))
	var scales: Array[float] = _run(controller, 600, 3.0)
	if scales.min() != 1.0 or controller.scale != 1.0:
		return "an off table gave %s" % scales.min()
	var built_in: RenderScaleController = RenderScaleController.new()
	if (_run(built_in, 600, 3.0) as Array).min() != 1.0:
		return "the built-in table scaled"
	return ""


func test_a_frame_without_a_rate_or_time_changes_nothing() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table())
	for i: int in 100:
		controller.advance(30.0, 30.0, 0.0)
		controller.advance(0.0, 0.0, HZ)
		controller.advance(NAN, INF, HZ)
	if controller.scale != 1.0 or controller.long_frames != 0:
		return "frames with no rate or time moved the scale to %s" % controller.scale
	return ""


func test_a_cpu_bound_frame_counts_too() -> String:
	var controller: RenderScaleController = RenderScaleController.new(_table())
	for i: int in 5:
		controller.advance(BUDGET_MS * 1.2, BUDGET_MS * 0.2, HZ)
	if controller.scale != 0.9:
		return "five CPU-bound long frames left the scale at %s" % controller.scale
	return ""


func test_the_scaler_leaves_a_flat_viewport_alone() -> String:
	var viewport: SubViewport = SubViewport.new()
	viewport.scaling_3d_scale = 1.0
	RenderScaler.apply(viewport, 0.7)
	var kept: float = viewport.scaling_3d_scale
	var shown: float = RenderScaler.in_use
	viewport.free()
	if kept != 1.0 or shown != 1.0:
		return "a flat viewport was scaled to %s (shown %s)" % [kept, shown]
	if RenderScaler.refresh_hz() != RenderScaler.FALLBACK_HZ:
		return "with no headset the rate is %s" % RenderScaler.refresh_hz()
	return ""


func test_the_rig_carries_one_scaler() -> String:
	var rig: Node = (load("res://xr/xr_rig.tscn") as PackedScene).instantiate()
	rig.call("build")
	rig.call("build")
	var found: int = 0
	for child: Node in rig.get_children():
		if child is RenderScaler:
			found += 1
	rig.free()
	if found != 1:
		return "the rig has %d render scalers after building twice" % found
	return ""
