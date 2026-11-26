class_name DevMenuValueRenderScale
extends DevMenuValue

## The Render scale entry's value (#1417, GFX-7): the scale the headset is
## drawn at, as a percentage of the full eye resolution. Read-only: left and
## right change nothing, and confirming returns the shown value
## (`render_scale:85`) like every value row, which `DevMenuRenderScale` takes
## and ignores: the scale is the `RenderScaler`'s to choose.

const PREFIX: String = "render_scale:"

var scale: float = 1.0


func plain_text() -> String:
	return "%d%%" % roundi(scale * 100.0)


func confirmed() -> String:
	return "%s%d" % [PREFIX, roundi(scale * 100.0)]
