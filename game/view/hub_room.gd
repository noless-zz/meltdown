class_name HubRoom
extends Node3D

## The home base as a modelled room around the seated pilot (#1298, CRW-2,
## decision record 0012): walls, floor, ceiling, props, the pilot's ship on its
## cradle (#1369, `HubRoomShip`), the hangar details merged by material
## (#1397, `HubRoomDetails`), up to 8 lights (`HubRoomLights`) and a
## station for each task the hub pages do, all built from `HubRoomSpec`
## (`data/hub/room.json`, ARC-4, ARC-5). The node's origin is the seated eye
## point, so the hub wiring places it where it places the hub panel and the
## pilot sits at one spot; nothing in the room moves (CMF-1, CMF-3, CMF-8).
##
## Every part is drawn on `LAYER_BIT` only. While the room shows, the head
## camera draws that layer alone and the room's own environment, so the mine
## (and the fade quad that darkens it) is not drawn; hiding the room gives the
## camera back its mask and environment. The room reads no simulation state
## and writes none (ARC-3, MP-2); the hub's pages stay what they were.

const NODE_NAME: String = "HubRoom"
## Render layer 20, unused by anything else in the game.
const LAYER_BIT: int = 1 << 19
## The room's share of PRF-4's 150 draw calls: the rest is for the station
## screens' words and icons, the hands and the controllers (#1369). Lowered
## from 80 to 60 with the hangar details (#1397).
const MAX_DRAW_CALLS: int = 60

var spec: HubRoomSpec = null

var _environment: Environment = null
var _camera: Camera3D = null
var _saved_mask: int = 0
var _saved_environment: Environment = null


## Builds the room from `p_spec`; a rejected spec builds nothing and the room
## never shows, so the hub falls back to the panel in the dark.
func _init(p_spec: HubRoomSpec = HubRoomSpec.load_shipped()) -> void:
	name = NODE_NAME
	spec = p_spec
	visible = false
	if spec.error != "":
		print("[meltdown view] the hub room is not built: %s" % spec.error)
		return
	var looks: Dictionary = {}
	for material_name: String in spec.materials:
		looks[material_name] = HubRoomParts.material(spec.materials[material_name])
	for wall: MeshInstance3D in HubRoomParts.shell(spec, looks, LAYER_BIT):
		add_child(wall)
	for prop: Dictionary in spec.props:
		var rotation_rad: Vector3 = (prop["rotation"] as Vector3) * (PI / 180.0)
		var at: Transform3D = Transform3D(Basis.from_euler(rotation_rad), prop["position"])
		add_child(HubRoomParts.part("Prop_%s" % prop["id"], prop["shape"], prop["size"], at,
			looks[prop["material"]], LAYER_BIT))
	for detail: MeshInstance3D in HubRoomDetails.build(spec, LAYER_BIT):
		add_child(detail)
	if not spec.ship.is_empty():
		add_child(HubRoomShip.build(spec.ship, LAYER_BIT))
	for i: int in spec.lights.size():
		add_child(HubRoomLights.build(i, spec.lights[i], LAYER_BIT))
	for station: Dictionary in spec.stations:
		add_child(HubRoomParts.station(spec, station, looks, LAYER_BIT))
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = spec.background_color
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = spec.ambient_color
	_environment.ambient_light_energy = spec.ambient_energy


func is_built() -> bool:
	return spec != null and spec.error == ""


## Shows the room and makes `camera` (may be null) draw only it. False, with
## nothing changed, when the room was not built.
func show_for(camera: Camera3D) -> bool:
	if not is_built():
		return false
	visible = true
	if camera != null and _camera == null:
		_camera = camera
		_saved_mask = camera.cull_mask
		_saved_environment = camera.environment
		camera.cull_mask = LAYER_BIT
		camera.environment = _environment
	return true


## Hides the room and gives the camera back what it drew before.
func hide_room() -> void:
	visible = false
	if _camera != null and is_instance_valid(_camera):
		_camera.cull_mask = _saved_mask
		_camera.environment = _saved_environment
	_camera = null
	_saved_environment = null


## True while the room shows and holds a camera to it.
func hides_mine() -> bool:
	return visible and _camera != null and _camera.cull_mask == LAYER_BIT


## Each station's screen centre in the room's space (from the eye point), by id.
func station_points() -> Dictionary[String, Vector3]:
	var points: Dictionary[String, Vector3] = {}
	for child: Node in get_children():
		if child is Node3D and child.name.begins_with("Station_"):
			points[child.name.trim_prefix("Station_")] = (child as Node3D).position
	return points


func light_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is Light3D:
			count += 1
	return count


## The pilot's ship on the cradle, or null when the room file gives none.
func ship() -> ShipModel:
	return get_node_or_null(HubRoomShip.NODE_NAME) as ShipModel


## What the room costs to draw: one draw call per mesh and per label (each
## has one surface and one material), the distinct materials, and the lights.
func cost() -> Dictionary:
	var draw_calls: int = 0
	var materials: Array[Material] = []
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is MeshInstance3D or node is Label3D:
			draw_calls += 1
		if node is MeshInstance3D and not materials.has((node as MeshInstance3D).material_override):
			materials.append((node as MeshInstance3D).material_override)
	return {"draw_calls": draw_calls, "materials": materials.size(), "lights": light_count()}
