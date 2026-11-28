class_name DevMenuValueDrawing
extends Node3D

## One menu row's value drawn instead of read (#1458): a switch for an on / off
## value, a row of small marks with the current one lit for a choice from a
## short list, a short bar for a number (its value is written beside it by the
## row). Its left edge is the node's origin; it is `DevMenuLook.DRAW_W_M` wide
## at most and centred on the row's line. Rebuilt only when what it shows
## changes. Presentation only: it reads the value helper and writes nothing
## (ARC-3, MP-2).

const NODE_NAME: String = "Value"

## What is drawn now, as `DevMenuValueDrawing.key_of` gives it; "" for nothing.
var shown_key: String = ""
var layers: int = 1


func _init(p_layers: int = 1) -> void:
	name = NODE_NAME
	layers = p_layers


## Draws `helper`'s value; null draws nothing.
func show_value(helper: DevMenuValue) -> void:
	var key: String = key_of(helper)
	if key == shown_key:
		return
	shown_key = key
	for child: Node in get_children():
		remove_child(child)
		child.free()
	if helper == null:
		return
	match helper.drawing():
		DevMenuValue.DRAW_SWITCH: _switch(helper.is_on())
		DevMenuValue.DRAW_BAR: _bar(helper.fill())
		_: _marks(helper.mark_count(), helper.mark_index())


## Names what `helper` would draw, so an unchanged value is not rebuilt.
static func key_of(helper: DevMenuValue) -> String:
	if helper == null:
		return ""
	match helper.drawing():
		DevMenuValue.DRAW_SWITCH: return "switch:%s" % helper.is_on()
		DevMenuValue.DRAW_BAR: return "bar:%.2f" % helper.fill()
		_: return "marks:%d:%d" % [helper.mark_count(), helper.mark_index()]


## The parts drawn, for tests and the acceptance step.
func part_count() -> int:
	return get_child_count()


## A track with its knob at the right and lit when on, at the left when off.
func _switch(on: bool) -> void:
	var w: float = DevMenuLook.SWITCH_W_M
	var h: float = DevMenuLook.DRAW_H_M
	_add(DevMenuLook.rect(Vector2(w, h), Vector3(w * 0.5, 0.0, 0.0),
		DevMenuLook.ON_TRACK_COLOR if on else DevMenuLook.DIM_COLOR, 0, layers), "Track")
	var knob: float = h * 0.8
	var x: float = w - h * 0.5 if on else h * 0.5
	_add(DevMenuLook.rect(Vector2(knob, knob), Vector3(x, 0.0, 0.0),
		DevMenuLook.LIT_COLOR if on else DevMenuLook.OFF_KNOB_COLOR, 1, layers), "Knob")


## `count` marks spread over the column, mark `lit` drawn lit and larger.
func _marks(count: int, lit: int) -> void:
	count = maxi(count, 1)
	var size: float = minf(DevMenuLook.MARK_M, DevMenuLook.DRAW_W_M / (count * 1.5))
	var step: float = minf(size * 2.0, (DevMenuLook.DRAW_W_M - size) / maxf(count - 1, 1))
	for i: int in count:
		var on: bool = i == lit
		var side: float = size * (1.4 if on else 1.0)
		_add(DevMenuLook.rect(Vector2(side, side), Vector3(size * 0.5 + i * step, 0.0, 0.0),
			DevMenuLook.LIT_COLOR if on else DevMenuLook.DIM_COLOR, 0, layers), "Mark%d" % i)


## A dim track the column wide with its lit share from the left.
func _bar(share: float) -> void:
	var w: float = DevMenuLook.DRAW_W_M
	var h: float = DevMenuLook.BAR_H_M
	_add(DevMenuLook.rect(Vector2(w, h), Vector3(w * 0.5, 0.0, 0.0), DevMenuLook.DIM_COLOR, 0, layers), "Track")
	if share > 0.0:
		_add(DevMenuLook.rect(Vector2(w * share, h), Vector3(w * share * 0.5, 0.0, 0.0),
			DevMenuLook.LIT_COLOR, 1, layers), "Fill")


func _add(mesh: MeshInstance3D, part_name: String) -> void:
	mesh.name = part_name
	add_child(mesh)
