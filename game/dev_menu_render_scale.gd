class_name DevMenuRenderScale
extends DevMenuEntry

## The dev menu's Render scale row in the Display section (#1417, GFX-7,
## DEV-6): shows the scale dynamic resolution scaling draws the headset at,
## followed every frame while the menu is open, so a drop can be seen as it
## happens. Its confirmed value is taken and ignored: it sets nothing
## (ARC-3). In the flat build it reads 100%. One of `DevMenuWiring`'s entry
## helpers (`DevMenuEntry`).

## Returns the scale in use; tests swap it for a fixed value.
var read_scale: Callable = func() -> float: return RenderScaler.in_use


func _init() -> void:
	super([DevMenuSpec.KIND_RENDER_SCALE], [DevMenuValueRenderScale.PREFIX])


func show_on(model: DevMenuModel) -> void:
	follow(model)


func follow(model: DevMenuModel) -> void:
	var value: DevMenuValueRenderScale = model.value(DevMenuSpec.KIND_RENDER_SCALE) as DevMenuValueRenderScale
	if value != null:
		value.scale = float(read_scale.call())
