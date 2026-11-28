class_name RenderFrameTimes
extends RefCounted

## One headset frame's CPU and GPU time for dynamic resolution scaling
## (#1509, GFX-7, PRF-1, PRF-2), without the time the frame spent waiting
## for the display.
##
## #1417 fed the controller the viewport's render CPU time plus the frame
## setup time plus `Performance.TIME_PROCESS`. In Godot 4.7 `TIME_PROCESS` is
## timed in `Main::iteration` from the start of the scripts' `_process` to the
## end of `RenderingServer.draw`. That span holds the render CPU time a second
## time and the wait for the headset's swapchain image, which the compositor
## releases once per refresh. On the Quest that wait fills the frame, so every
## frame read as longer than `high_water` of the budget and the scale stepped
## to its floor and stayed there (the device's "min 0.70, mean 0.70").
##
## Here the CPU time is only work, each part timed where nothing waits:
## - the scripts' `_process`, from the tree's `process_frame` signal (emitted
##   before any node processes) to the scaler, which processes last;
## - the physics step (`TIME_PHYSICS_PROCESS`);
## - the render server's frame setup (`get_frame_setup_time_cpu`);
## - the viewport's own render CPU time.
## `xrWaitFrame` runs before all of them and the swapchain wait outside the
## viewport's timestamps, so neither is counted. The GPU time is the
## viewport's GPU timestamps, as before. View only (ARC-3).

## Start of this frame's `_process`, in microseconds; -1 when not marked.
var _process_begin_usec: int = -1


## Marks the start of the scripts' `_process`. Connected to
## `SceneTree.process_frame` by the scaler.
func begin_process(now_usec: int = -1) -> void:
	_process_begin_usec = now_usec if now_usec >= 0 else Time.get_ticks_usec()


## Milliseconds of script work since `begin_process`; 0 when it was not
## marked this frame. Each mark is read once.
func script_ms(now_usec: int = -1) -> float:
	var now: int = now_usec if now_usec >= 0 else Time.get_ticks_usec()
	var begun: int = _process_begin_usec
	_process_begin_usec = -1
	if begun < 0 or now < begun:
		return 0.0
	return float(now - begun) / 1000.0


## The frame's CPU time from its parts in milliseconds. A part that is
## negative or not a number counts as 0, so one bad reading cannot make a
## frame look long.
static func cpu_ms_of(script: float, physics: float, setup: float, render: float) -> float:
	var total: float = 0.0
	for part: float in [script, physics, setup, render]:
		if is_finite(part) and part > 0.0:
			total += part
	return total


## The CPU time of the frame drawn on viewport `rid`.
func read_cpu_ms(rid: RID) -> float:
	return cpu_ms_of(script_ms(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_cpu(rid))


## The GPU time of the frame drawn on viewport `rid`.
static func read_gpu_ms(rid: RID) -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(rid)
