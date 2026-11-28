extends RefCounted

## The device's 27 Nov frames fed to the render scale controller (#1509,
## GFX-7, PRF-1, PRF-2, CMF-8).
##
## The device run (build `4978f50b2fd1`, `m1/frame_budget_120`) reported a
## mean frame of 8.43 ms at 120 Hz with 49 draw calls and 47 k triangles,
## and the scale at 0.70 on every frame. It did not report the CPU and GPU
## split; the parts below are assumed, sized for a scene that light, and
## named so the next device report (which now carries them) can replace
## them. What is not assumed is the old sum: `TIME_PROCESS` spans the draw
## and the swapchain wait, so on a vsynced headset it is close to the whole
## frame, whatever the work.

const HZ: float = 120.0
const BUDGET_MS: float = 1000.0 / 120.0
const DEVICE_FRAME_MS: float = 8.43
## Assumed work parts, in milliseconds.
const SCRIPT_MS: float = 1.5
const PHYSICS_MS: float = 0.3
const SETUP_MS: float = 0.3
const RENDER_CPU_MS: float = 1.4
const GPU_MS: float = 4.0
## What `TIME_PROCESS` read: the frame less `xrWaitFrame`, which runs before it.
const PROCESS_MS: float = DEVICE_FRAME_MS - 0.5


## The shipped file's values with scaling on, so this test does not depend
## on whether the shipped file has it on (#1503 turns it off for now).
func _controller() -> RenderScaleController:
	var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify({"enabled": true, "floor": 0.7,
		"ceiling": 1.0, "step": 0.1, "high_water": 0.9, "low_water": 0.7, "frames_down": 5,
		"frames_up": 45, "interval_frames": 30}))
	assert(table.error == "", table.error)
	return RenderScaleController.new(table)


## #1417's sum: render CPU + frame setup + TIME_PROCESS.
static func _old_cpu_ms() -> float:
	return RENDER_CPU_MS + SETUP_MS + PROCESS_MS


static func _new_cpu_ms() -> float:
	return RenderFrameTimes.cpu_ms_of(SCRIPT_MS, PHYSICS_MS, SETUP_MS, RENDER_CPU_MS)


func test_the_old_sum_reads_every_device_frame_as_long() -> String:
	var controller: RenderScaleController = _controller()
	var lowest_after: int = -1
	for i: int in 600:
		controller.advance(_old_cpu_ms(), GPU_MS, HZ)
		if controller.scale == 0.7 and lowest_after < 0:
			lowest_after = i + 1
	if _old_cpu_ms() <= BUDGET_MS * 0.9:
		return "the old sum %.2f ms is not over high_water" % _old_cpu_ms()
	if controller.scale != 0.7 or lowest_after < 0 or lowest_after > 100:
		return "the old sum left the scale at %s (floor after %d frames); the device saw 0.70" % [
			controller.scale, lowest_after]
	return ""


func test_the_fixed_times_are_under_high_water() -> String:
	var limit: float = BUDGET_MS * 0.9
	if _new_cpu_ms() >= limit or GPU_MS >= limit:
		return "CPU %.2f or GPU %.2f ms not under %.2f" % [_new_cpu_ms(), GPU_MS, limit]
	return ""


func test_from_the_floor_the_fixed_times_climb_back_to_full() -> String:
	var controller: RenderScaleController = _controller()
	for i: int in 600:
		controller.advance(_old_cpu_ms(), GPU_MS, HZ)
	if controller.scale != 0.7:
		return "did not start at the floor: %s" % controller.scale
	# Three steps up, each after frames_up frames with headroom.
	var back_after: int = -1
	for i: int in 3 * 45 + 10:
		controller.advance(_new_cpu_ms(), GPU_MS, HZ)
		if controller.scale == 1.0:
			back_after = i + 1
			break
	if back_after != 3 * 45:
		return "back to 1.0 after %d frames, expected %d" % [back_after, 3 * 45]
	for i: int in 1200:
		controller.advance(_new_cpu_ms(), GPU_MS, HZ)
	if controller.scale != 1.0:
		return "left 1.0 again: %s" % controller.scale
	return ""


func test_between_the_waters_the_scale_holds_where_it_is() -> String:
	# The hysteresis band: frames between low_water and high_water neither
	# lower nor raise the scale, so it does not pump (CMF-8).
	var controller: RenderScaleController = _controller()
	for i: int in 600:
		controller.advance(_old_cpu_ms(), GPU_MS, HZ)
	for i: int in 900:
		controller.advance(BUDGET_MS * 0.8, BUDGET_MS * 0.8, HZ)
	if controller.scale != 0.7:
		return "frames at 0.8 of the budget moved the scale to %s" % controller.scale
	return ""
