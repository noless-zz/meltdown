class_name ShaftPanelCard
extends Node3D

## One offered shaft on the shaft panel (#1320, RUN-2, GFX-2, ARC-5): a plate,
## the shaft's look as a small object of primitives, its short label, and a
## gauge per thing it changes, all from `ShaftPanelShapes`. A shaft with no
## look shows its full label and risk line as text instead, as before.
##
## Everything draws unshaded over the fade quad without depth test, like the
## panel's words. Without depth test the order comes from `sorting_offset`:
## the plate first, then the look's parts in file order, then the gauges, then
## the words. Nothing moves or animates (CMF-3, CMF-8).

const PART_OFFSET: float = 0.1
const PART_OFFSET_STEP: float = 0.005
const GAUGE_OFFSET: float = 0.4
const WORD_OFFSET: float = 0.6
const VALUE_FONT_SCALE: float = 0.75
const GAUGE_LABEL_PAD_M: float = 0.02
const MARK_WIDTH_M: float = 0.004

var _shapes: ShaftPanelShapes
var _look: Dictionary
var _plate: MeshInstance3D
var _object: Node3D
var _look_key: String = "-"
var _label: Label3D
var _detail: Label3D
var _gauge_nodes: Array[Dictionary] = []


func _init(shapes: ShaftPanelShapes, look: Dictionary) -> void:
	_shapes = shapes
	_look = look
	var plate_at: Vector3 = Vector3(0.0, -_shapes.lengths["plate_drop_m"], -0.01)
	_plate = _box("Plate", Vector3(shapes.plate_size_m.x, shapes.plate_size_m.y, 0.002), plate_at,
		shapes.colors["plate_color"], 0.0)
	_object = Node3D.new()
	_object.name = "Look"
	_object.position = Vector3(0.0, -_shapes.lengths["object_drop_m"], 0.0)
	add_child(_object)
	_label = _word("Label", look["label_font_size"], HORIZONTAL_ALIGNMENT_CENTER)
	_detail = _word("Detail", look["detail_font_size"], HORIZONTAL_ALIGNMENT_CENTER)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.width = shapes.plate_size_m.x * 0.9 / float(look["pixel_size"])
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = _detail.width


## Shows entry `index` of `model`, lit when it is the highlighted one.
func show_entry(model: ShaftPanelModel, index: int, lit: bool) -> void:
	var key: String = model.looks[index]
	var color: Color = _look["highlight_color"] if lit else _look["text_color"]
	_set_color(_plate, _shapes.colors["plate_lit_color"] if lit else _shapes.colors["plate_color"])
	if key != _look_key:
		_build_look(key)
	var drop: float = _shapes.lengths["object_drop_m"]
	var text: String = (_look["mark_text"] if lit else "") + (_shapes.looks[key]["label"] if key != "" else model.labels[index])
	_put(_label, text, Vector3(0.0, -drop - (_shapes.lengths["label_drop_m"] if key != "" else 0.0), 0.0), color)
	_detail.visible = key == ""
	if key == "":
		_put(_detail, model.details[index], Vector3(0.0, -drop - _shapes.lengths["label_drop_m"], 0.0), color)
	var gauges: Array = model.gauges[index]
	for i: int in _gauge_nodes.size():
		var shown: bool = i < gauges.size()
		for node: Node3D in (_gauge_nodes[i].values() as Array):
			node.visible = shown
		if shown:
			_show_gauge(i, gauges[i], color)


## The look's label and each gauge's words, for tests: "label", then
## "<gauge label> <value>" per gauge.
func texts() -> PackedStringArray:
	var shown: PackedStringArray = PackedStringArray([_label.text])
	if _detail.visible:
		shown.append(_detail.text)
	for nodes: Dictionary in _gauge_nodes:
		if (nodes["label"] as Label3D).visible:
			shown.append("%s %s" % [(nodes["label"] as Label3D).text, (nodes["value"] as Label3D).text])
	return shown


## The fill length of each shown gauge, in metres, for tests.
func fill_lengths() -> Array[float]:
	var lengths: Array[float] = []
	for nodes: Dictionary in _gauge_nodes:
		var fill: MeshInstance3D = nodes["fill"]
		if fill.visible:
			lengths.append((fill.mesh as BoxMesh).size.x)
	return lengths


## The number of parts drawn for the look, 0 for a text row.
func part_count() -> int:
	return _object.get_child_count()


func _build_look(key: String) -> void:
	for child: Node in _object.get_children():
		_object.remove_child(child)
		child.free()
	_look_key = key
	if key == "":
		return
	var parts: Array = _shapes.looks[key]["parts"]
	for i: int in parts.size():
		var part: Dictionary = parts[i]
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = "Part%d" % i
		instance.mesh = HubRoomParts.mesh(part["shape"], part["size"])
		instance.transform = part["at"]
		instance.material_override = flat_material(part["color"])
		instance.sorting_offset = PART_OFFSET + PART_OFFSET_STEP * i
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_object.add_child(instance)
	while _gauge_nodes.size() < _shapes.gauges.size():
		_gauge_nodes.append(_new_gauge(_gauge_nodes.size()))


func _new_gauge(index: int) -> Dictionary:
	var length: float = _shapes.lengths["gauge_length_m"]
	var height: float = _shapes.lengths["gauge_height_m"]
	var nodes: Dictionary = {
		"back": _box("GaugeBack%d" % index, Vector3(length, height, 0.002), Vector3.ZERO,
			_shapes.colors["gauge_back_color"], GAUGE_OFFSET),
		"fill": _box("GaugeFill%d" % index, Vector3(length, height, 0.002), Vector3.ZERO, Color.WHITE,
			GAUGE_OFFSET + 0.05),
		"mark": _box("GaugeMark%d" % index, Vector3(MARK_WIDTH_M, height * 1.5, 0.002), Vector3.ZERO,
			_shapes.colors["mark_color"], GAUGE_OFFSET + 0.1),
		"label": _word("GaugeLabel%d" % index, _look["detail_font_size"], HORIZONTAL_ALIGNMENT_RIGHT),
		"value": _word("GaugeValue%d" % index, float(_look["detail_font_size"]) * VALUE_FONT_SCALE,
			HORIZONTAL_ALIGNMENT_CENTER),
	}
	(nodes["value"] as Label3D).outline_size = 8
	(nodes["value"] as Label3D).outline_modulate = Color.BLACK
	return nodes


func _show_gauge(index: int, gauge: Dictionary, word_color: Color) -> void:
	var nodes: Dictionary = _gauge_nodes[index]
	var length: float = _shapes.lengths["gauge_length_m"]
	var left: float = _shapes.lengths["gauge_x_m"] - length * 0.5
	var y: float = -_shapes.lengths["object_drop_m"] - _shapes.lengths["gauge_drop_m"] \
		- _shapes.lengths["gauge_step_m"] * index
	(nodes["back"] as Node3D).position = Vector3(_shapes.lengths["gauge_x_m"], y, 0.0)
	var fill: MeshInstance3D = nodes["fill"]
	var fill_length: float = maxf(length * float(gauge["fill"]), 0.001)
	(fill.mesh as BoxMesh).size.x = fill_length
	fill.position = Vector3(left + fill_length * 0.5, y, 0.0)
	_set_color(fill, gauge["color"])
	(nodes["mark"] as Node3D).position = Vector3(left + length * float(gauge["mark"]), y, 0.0)
	_put(nodes["label"], gauge["label"], Vector3(left - GAUGE_LABEL_PAD_M, y, 0.0), word_color)
	_put(nodes["value"], gauge["value_text"], Vector3(_shapes.lengths["gauge_x_m"], y, 0.0), Color.WHITE)


## An unshaded colour drawn over the fade quad, as the panel's words are.
static func flat_material(color: Color) -> StandardMaterial3D:
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.albedo_color = color
	made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	made.no_depth_test = true
	made.render_priority = DestroyedScreen.RENDER_PRIORITY
	return made


static func _set_color(instance: MeshInstance3D, color: Color) -> void:
	(instance.material_override as StandardMaterial3D).albedo_color = color


static func _put(label: Label3D, text: String, at: Vector3, color: Color) -> void:
	if label.text != text:  # Label3D rebuilds its glyphs on every text assignment.
		label.text = text
	label.position = at
	label.modulate = color
	label.visible = true


func _box(box_name: String, size: Vector3, at: Vector3, color: Color, offset: float) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = box_name
	instance.mesh = box
	instance.position = at
	instance.material_override = flat_material(color)
	instance.sorting_offset = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _word(word_name: String, font_size: float, align: HorizontalAlignment) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = word_name
	label.pixel_size = _look["pixel_size"]
	label.font_size = roundi(font_size)
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = align
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = DestroyedScreen.RENDER_PRIORITY
	label.sorting_offset = WORD_OFFSET
	add_child(label)
	return label
