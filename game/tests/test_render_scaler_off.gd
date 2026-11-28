extends RefCounted

## The render scaler with the shipped table (#1503, GFX-7, PRF-1, CMF-8): on
## the Quest a lowered `scaling_3d_scale` magnified the whole picture, so the
## shipped file has scaling off. Then a headset viewport is held at exactly
## 1.0, even one an earlier frame left lowered, and no render times are
## measured. A flat viewport is still left alone.


func _xr_viewport(scale: float) -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.use_xr = true
	viewport.scaling_3d_scale = scale
	return viewport


func test_the_shipped_scaler_is_off() -> String:
	var scaler: RenderScaler = RenderScaler.new()
	var enabled: bool = scaler.controller.table.enabled
	var error: String = scaler.controller.table.error
	scaler.free()
	if enabled or error != "":
		return "the shipped scaler: enabled %s, error \"%s\"" % [enabled, error]
	return ""


func test_off_holds_a_headset_viewport_at_full_scale() -> String:
	var scaler: RenderScaler = RenderScaler.new()
	var viewport: SubViewport = _xr_viewport(0.7)
	RenderScaler.in_use = 0.7
	var after: Array[float] = []
	for i: int in 120:
		scaler.tick(viewport)
		after.append(viewport.scaling_3d_scale)
	var shown: float = RenderScaler.in_use
	var measuring: bool = scaler._measuring.is_valid()
	viewport.free()
	scaler.free()
	RenderScaler.in_use = 1.0
	if after.min() != 1.0 or after.max() != 1.0:
		return "a lowered headset viewport went %s..%s, not 1.0" % [after.min(), after.max()]
	if shown != 1.0:
		return "the dev menu would show %s" % shown
	if measuring:
		return "render times are measured while scaling is off"
	return ""


func test_off_leaves_a_flat_viewport_alone() -> String:
	var scaler: RenderScaler = RenderScaler.new()
	var viewport: SubViewport = SubViewport.new()
	viewport.scaling_3d_scale = 0.8
	scaler.tick(viewport)
	var kept: float = viewport.scaling_3d_scale
	viewport.free()
	scaler.free()
	if not is_equal_approx(kept, 0.8):
		return "a flat viewport was changed to %s" % kept
	return ""
