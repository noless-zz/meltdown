class_name RenderScaler
extends Node

## Applies dynamic resolution scaling to the headset's picture (#1417, GFX-7,
## PRF-2, PRF-3). Hangs under the rig (`XRRig.build`). Each frame it hands
## the last frame's CPU and GPU time and the headset's refresh rate to a
## `RenderScaleController` and sets the answer as the viewport's 3D scale
## (`Viewport.scaling_3d_scale`), which Godot applies to the XR eye buffers
## every frame. `OpenXRInterface.render_target_size_multiplier` is not used:
## it sizes the swapchain when the session starts and does not follow later
## changes.
##
## Only while the viewport renders to the headset (`use_xr`). In the flat
## build it does nothing and the scale stays 1.0. With the table off it holds
## the headset viewport at exactly 1.0 and does not measure render times
## (#1503: on the Quest a lowered scale magnified the picture, so an earlier
## scale must never survive). View only: it never reads or writes simulation
## state (ARC-3, MP-2).

const NODE_NAME: String = "RenderScaler"
## Used when the runtime does not report its rate yet (PRF-1's default).
const FALLBACK_HZ: float = 90.0

## The scale the headset is drawn at now, for the dev menu's Render scale row
## and the acceptance frame budget; 1.0 when no scaler runs.
static var in_use: float = 1.0

var controller: RenderScaleController
var _measuring: RID = RID()


func _init(p_controller: RenderScaleController = null) -> void:
	name = NODE_NAME
	controller = p_controller if p_controller != null else RenderScaleController.load_file()


func _process(_delta: float) -> void:
	tick(get_viewport())


## One frame on `viewport`. Public for the tests.
func tick(viewport: Viewport) -> void:
	if viewport == null or not viewport.use_xr:
		return
	if not controller.table.enabled:
		apply(viewport, 1.0)
		return
	var rid: RID = viewport.get_viewport_rid()
	if _measuring != rid:
		# The times read back start with the next frame; this one has none.
		RenderingServer.viewport_set_measure_render_time(rid, true)
		_measuring = rid
		return
	var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(rid) \
		+ RenderingServer.get_frame_setup_time_cpu() + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	apply(viewport, controller.advance(cpu_ms, gpu_ms, refresh_hz()))


## Sets `scale` on `viewport` when it renders to the headset; a flat viewport
## is left alone. Public for the tests.
static func apply(viewport: Viewport, scale: float) -> void:
	if viewport == null or not viewport.use_xr:
		return
	in_use = scale
	if not is_equal_approx(viewport.scaling_3d_scale, scale):
		viewport.scaling_3d_scale = scale


## The rate the headset runs at, or `FALLBACK_HZ` before it reports one.
static func refresh_hz() -> float:
	var openxr: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	var rate: float = openxr.get_display_refresh_rate() if openxr != null and openxr.is_initialized() else 0.0
	return rate if rate > 0.0 else FALLBACK_HZ


func _exit_tree() -> void:
	in_use = 1.0
