class_name HubCraftMoment
extends Node3D

## The crafting moment on the Workbench's tree (#1402, CRF-3, CRW-2, CMF-3,
## CMF-8, ARC-3, ARC-4): when a node turns from buildable to built, the spent
## components' icons fly from the cost rows into it, a plate fills the node,
## and then the item's icon grows a little past its size and settles. Nodes
## the craft unlocks come up from locked to buildable under a soft glow that
## fades in, holds and fades out; their frame and icon grow with it.
##
## Presentation only. `HubTreeView` starts it when one drawing differs from the
## last; it reads nothing but those drawings and the screen look, writes no
## simulation state (MP-2) and reads no comfort setting (ARC-3). Everything is
## drawn on the station's face, so nothing moves outside the screen and the
## view never moves (CMF-8). Times, sizes and colours are the look file's
## (`HubScreenLook`, ARC-4).

const NODE_NAME: String = "CraftMoment"
## Behind the node's frame and icon; the glow behind its edges too.
const PLATE_Z_M: float = 0.0015
const GLOW_Z_M: float = 0.0008
const FLY_Z_M: float = 0.0035
## A flying component ends at this share of its size, as if taken in.
const FLY_END_SCALE: float = 0.5
## Share of the item's time spent growing; the rest settles to rest.
const ITEM_GROW_SHARE: float = 0.6
## Under this an icon or frame is hidden rather than scaled to nothing.
const TINY: float = 0.001

## The node crafted, or "" when nothing is playing.
var crafted: String = ""
## Nodes the craft unlocked.
var unlocked: Array[String] = []
## Seconds since the craft.
var elapsed: float = 0.0

var _look: Dictionary
var _node_size: float = 0.0
## Each flying component: {"icon": HubIcon, "from": Vector3}.
var _flying: Array[Dictionary] = []
var _plate: MeshInstance3D
var _glows: Dictionary[String, MeshInstance3D] = {}
var _locked_scale: float = 1.0


func _init(look: Dictionary, locked_scale: float) -> void:
	name = NODE_NAME
	_look = look
	_locked_scale = locked_scale


## Starts the moment for node `id`, built just now, with `opened` the nodes it
## unlocked and `spent` the component icons to fly in, each {"icon": HubIcon
## made for it, "at": where its row showed it}. Ends one already playing.
func start(id: String, opened: Array[String], spent: Array[Dictionary], node_size: float, layers: int) -> void:
	finish()
	crafted = id
	unlocked = opened.duplicate()
	elapsed = 0.0
	_node_size = node_size
	for each: Dictionary in spent:
		var icon: HubIcon = each["icon"]
		icon.position = each["at"]
		add_child(icon)
		_flying.append({"icon": icon, "from": each["at"]})
	_plate = _flat_mesh("Fill", _square_mesh(node_size * HubTreeView.SQUARE), _value("frame_color"), layers)
	for opened_id: String in unlocked:
		var across: float = node_size * float(_value("unlock_glow_scale"))
		_glows[opened_id] = _flat_mesh("Glow_%s" % opened_id, _disc_mesh(across), _value("unlock_glow_color"), layers)


func running() -> bool:
	return crafted != ""


## The whole moment, in seconds: the item settled and the glows gone.
func duration() -> float:
	var item_end: float = _value("craft_fly_seconds") + _value("craft_item_seconds")
	var glow_end: float = _value("craft_fill_seconds") + _value("unlock_glow_seconds") * 2.0 \
		+ _value("unlock_glow_hold_seconds")
	return maxf(item_end, glow_end if not unlocked.is_empty() else 0.0)


## 0..1: how far the node has filled from buildable to built.
func fill() -> float:
	return _eased(elapsed / _value("craft_fill_seconds"))


## The crafted node's icon size against its rest size: 0 until the components
## arrive, then up to the peak and back to 1.
func item_scale() -> float:
	var time: float = elapsed - _value("craft_fly_seconds")
	if not running() or time >= _value("craft_item_seconds"):
		return 1.0
	if time <= 0.0:
		return 0.0
	var share: float = time / _value("craft_item_seconds")
	var peak: float = _value("craft_item_peak")
	if share < ITEM_GROW_SHARE:
		return lerpf(0.0, peak, _eased(share / ITEM_GROW_SHARE))
	return lerpf(peak, 1.0, _eased((share - ITEM_GROW_SHARE) / (1.0 - ITEM_GROW_SHARE)))


## 0..1: how far an unlocked node has come up from locked; it starts once the
## crafted node has filled.
func unlocking() -> float:
	return _eased((elapsed - _value("craft_fill_seconds")) / _value("unlock_glow_seconds"))


## The glow's opacity on the unlocked nodes now.
func glow_alpha() -> float:
	var out_from: float = _value("craft_fill_seconds") + _value("unlock_glow_seconds") \
		+ _value("unlock_glow_hold_seconds")
	var fading: float = _eased((elapsed - out_from) / _value("unlock_glow_seconds"))
	return float(_value("unlock_glow_alpha")) * unlocking() * (1.0 - fading)


func flying_count() -> int:
	return _flying.size()


## Moves the moment `seconds` on and applies it to `nodes` (the tree view's
## drawn nodes by id); ends it when its time is up.
func advance(seconds: float, nodes: Dictionary[String, Node3D]) -> void:
	if not running():
		return
	elapsed += seconds
	if elapsed >= duration():
		finish()
		_rest(nodes)
		return
	apply(nodes)


## Puts the moment's current look on `nodes`; called after every redraw too,
## since a redraw makes the nodes afresh at rest.
func apply(nodes: Dictionary[String, Node3D]) -> void:
	if not running():
		return
	var spot: Node3D = nodes.get(crafted, null)
	var arrived: float = _eased(elapsed / _value("craft_fly_seconds"))
	for each: Dictionary in _flying:
		var icon: HubIcon = each["icon"]
		icon.visible = spot != null and arrived < 1.0
		if spot != null:
			var to: Vector3 = Vector3(spot.position.x, spot.position.y, FLY_Z_M)
			icon.position = (each["from"] as Vector3).lerp(to, arrived)
			icon.scale = Vector3.ONE * lerpf(1.0, FLY_END_SCALE, arrived)
	if spot != null:
		_set_scale(spot.get_node_or_null("Icon") as Node3D, item_scale())
		_set_scale(spot.get_node_or_null("Frame") as Node3D, fill())
	_place(_plate, spot, PLATE_Z_M, fill(), float(_value("craft_fill_alpha")) * (1.0 - _item_share()))
	for id: String in _glows:
		var opened: Node3D = nodes.get(id, null)
		_place(_glows[id], opened, GLOW_Z_M, 1.0, glow_alpha())
		if opened != null:
			_set_scale(opened.get_node_or_null("Frame") as Node3D, unlocking())
			_set_scale(opened.get_node_or_null("Icon") as Node3D, lerpf(_locked_scale, 1.0, unlocking()))


## Ends the moment where it would end: its own pieces gone.
func finish() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_flying.clear()
	_glows.clear()
	_plate = null
	crafted = ""
	unlocked.clear()
	elapsed = 0.0


func _rest(nodes: Dictionary[String, Node3D]) -> void:
	for spot: Node3D in nodes.values():
		for part: String in ["Icon", "Frame"]:
			_set_scale(spot.get_node_or_null(part) as Node3D, 1.0)


func _item_share() -> float:
	return clampf((elapsed - _value("craft_fly_seconds")) / _value("craft_item_seconds"), 0.0, 1.0)


func _place(mesh: MeshInstance3D, spot: Node3D, z: float, size: float, alpha: float) -> void:
	mesh.visible = spot != null and size > TINY and alpha > TINY
	if not mesh.visible:
		return
	mesh.position = Vector3(spot.position.x, spot.position.y, z)
	mesh.scale = Vector3.ONE * size
	var material: StandardMaterial3D = mesh.material_override
	material.albedo_color.a = alpha


static func _set_scale(part: Node3D, size: float) -> void:
	if part == null:
		return
	part.visible = size > TINY
	if part.visible:
		part.scale = Vector3.ONE * size


static func _eased(share: float) -> float:
	return smoothstep(0.0, 1.0, clampf(share, 0.0, 1.0))


func _value(key: String) -> Variant:
	return _look.get(key, HubScreenLook.FALLBACK[key])


static func _square_mesh(side: float) -> Mesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(side, side)
	return quad


static func _disc_mesh(across: float) -> Mesh:
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = across * 0.5
	disc.bottom_radius = across * 0.5
	disc.height = HubIcon.THICK_M
	disc.radial_segments = HubIcon.SEGMENTS
	disc.rings = 1
	return disc


## A see-through unshaded sheet of its own, so its opacity can change alone.
func _flat_mesh(part_name: String, mesh: Mesh, color: Color, layers: int) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = layers
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	if mesh is CylinderMesh:
		instance.rotation.x = PI * 0.5  # A cylinder stands on Y; laid on Z it faces the pilot.
	add_child(instance)
	return instance
