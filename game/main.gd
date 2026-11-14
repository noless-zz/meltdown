extends Node3D

## Entry scene. Starts an XR session when an OpenXR runtime is present and
## falls back to a flat window otherwise, so the same build runs on the
## headset, the desktop and headless CI (PLT-2, PLT-4).

const TARGET_REFRESH_RATE: float = 90.0


func _ready() -> void:
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		# The headset compositor paces frames; desktop vsync would fight it.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		var openxr: OpenXRInterface = xr as OpenXRInterface
		if openxr != null:
			openxr.session_begun.connect(_on_session_begun.bind(openxr))
		print("Meltdown: OpenXR session active")
	else:
		print("Meltdown: running flat (no OpenXR session)")


func _on_session_begun(openxr: OpenXRInterface) -> void:
	# PRF-1: 90 Hz by default when the headset offers it.
	var rates: Array = openxr.get_available_display_refresh_rates()
	if rates.has(TARGET_REFRESH_RATE):
		openxr.display_refresh_rate = TARGET_REFRESH_RATE
	print("Meltdown: refresh rate ", openxr.display_refresh_rate, " Hz, available ", rates)
