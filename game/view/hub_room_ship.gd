class_name HubRoomShip
extends RefCounted

## The pilot's ship on its cradle in the home base room (#1369, CRW-2, GFX-2,
## ARC-4): the optional `ship` object of `data/hub/room.json`,
##
##     "ship": {"position_m": [x, y, z], "facing_deg": 0..90, "scale": 0.5..3}
##
## drawn by `ShipModel` from the shipped `ShipLook`, so the base shows the same
## ship the pilot flies. `facing_deg` turns the nose away from pointing
## straight at the seat, about the vertical: 0 is nose-on, which hides the
## ship's shape; around 35 is the three-quarter view in which its silhouette
## reads. The ship is scenery: it reads no simulation state and its engine
## stays at idle (MP-2).

const NODE_NAME: String = "Ship"
const DEFAULT_FACING_DEG: float = 35.0
const DEFAULT_SCALE: float = 1.0


## The ship in `raw` as {"position": Vector3, "facing_deg", "scale"}; an empty
## dictionary for no ship; a String naming the bad field.
static func parse(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return "\"ship\" must be an object"
	var data: Dictionary = raw
	if data.is_empty():
		return {}
	for key: Variant in data:
		if not ["position_m", "facing_deg", "scale"].has(key):
			return "ship: unknown key \"%s\"" % str(key)
	if not HubRoomValues.is_vector(data.get("position_m"), 3, -30.0, 30.0):
		return "ship: \"position_m\" must be [x, y, z]"
	var position: Vector3 = HubRoomValues.vector3(data["position_m"])
	if Vector2(position.x, position.z).length() < 0.5:
		return "ship: \"position_m\" is on the seat"
	if not HubRoomValues.is_number(data.get("facing_deg", DEFAULT_FACING_DEG), 0.0, 90.0):
		return "ship: \"facing_deg\" must be 0..90"
	if not HubRoomValues.is_number(data.get("scale", DEFAULT_SCALE), 0.5, 3.0):
		return "ship: \"scale\" must be 0.5..3"
	return {"position": position, "facing_deg": float(data.get("facing_deg", DEFAULT_FACING_DEG)),
		"scale": float(data.get("scale", DEFAULT_SCALE))}


## Where the ship stands: at its position, nose (-Z) turned `facing_deg` away
## from the seat (the eye point, the room's origin), level, at its scale.
static func pose(data: Dictionary) -> Transform3D:
	var at: Vector3 = data["position"]
	var to_seat: Vector3 = Vector3(-at.x, 0.0, -at.z)
	var facing: Basis = Basis(Vector3.UP, deg_to_rad(float(data["facing_deg"]))) * Basis.looking_at(to_seat)
	return Transform3D(facing.scaled(Vector3.ONE * float(data["scale"])), at)


## The ship model for `data`, every piece drawn on `layers` only, its engine
## at idle. Named `NODE_NAME`.
static func build(data: Dictionary, layers: int) -> ShipModel:
	var model: ShipModel = ShipModel.create()
	model.name = NODE_NAME
	model.show_at(pose(data), 0.0)
	for piece: MeshInstance3D in model.pieces():
		piece.layers = layers
	return model


## The angle in degrees, about the vertical, between the nose of `model` and
## the line from it to the seat.
static func facing_angle_deg(model: Node3D) -> float:
	var nose: Vector3 = -model.transform.basis.z
	nose.y = 0.0
	var to_seat: Vector3 = -model.position
	to_seat.y = 0.0
	return rad_to_deg(nose.angle_to(to_seat))
