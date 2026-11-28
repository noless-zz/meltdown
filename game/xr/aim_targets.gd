class_name AimTargets
extends RefCounted

## Where the aim ray lands, found with the very pick the selection uses
## (#1451, CRW-2, RUN-1): `HubStations.pick` over the room's stations while the
## pilot chooses one, and `ShaftChoiceWiring.point_in` over the shaft panel's
## entries. The ray's end is the point on the aim ray nearest the entry that
## pick chose, so the hand, the ray and the highlight agree.
##
## It only reads the nodes the hub and the shaft choice hang under the rig;
## it writes nothing and reads no comfort setting (ARC-3, MP-2). Pointing
## selects only at the base and the shaft choice, so in flight it reports
## nothing to show.

## The shaft panel's pick radius comes from the same file the shaft choice reads.
var shaft_shapes: ShaftPanelShapes = ShaftPanelShapes.load_file()


## For the aim pose `aim` (in `rig`'s space): {"shown": true while pointing
## selects, "hit": the landing point in `rig`'s space, or null for none}.
func find(rig: Node, aim: Transform3D) -> Dictionary:
	var none: Dictionary = {"shown": false, "hit": null}
	if rig == null:
		return none
	var stations: HubStations = rig.get_node_or_null(HubStations.NODE_NAME) as HubStations
	var room: HubRoom = rig.get_node_or_null(HubRoom.NODE_NAME) as HubRoom
	if stations != null and room != null and stations.visible and room.visible:
		return {"shown": true, "hit": station_hit(stations, room, aim)}
	var panel: ShaftPanel = rig.get_node_or_null(ShaftPanel.NODE_NAME) as ShaftPanel
	if panel != null and panel.visible:
		return {"shown": true, "hit": shaft_hit(panel, aim, shaft_radius())}
	return none


## The point on `aim`'s ray (in the room's parent's space) at the station the
## stations' own pick chooses, in that space; null when it points at none.
## Inside a station it is the slot or tree node the station's drawing picks
## (`slot_hit`, #1470).
static func station_hit(stations: HubStations, room: HubRoom, aim: Transform3D) -> Variant:
	var to_room: Transform3D = room.transform.affine_inverse()
	var origin: Vector3 = to_room * aim.origin
	var direction: Vector3 = to_room.basis * -aim.basis.z
	if stations.in_use != "":
		var landed: Variant = slot_hit(stations, room, origin, direction)
		return room.transform * (landed as Vector3) if landed is Vector3 else null
	var all: Dictionary[String, Vector3] = room.station_points()
	var points: Dictionary[String, Vector3] = {}
	for id: String in stations.ids:
		points[id] = all[id]
	var id: String = HubStations.pick(origin, direction, points, HubStations.POINT_RADIUS_M)
	if id == "":
		return null
	return room.transform * on_ray(origin, direction, points[id])


## Inside the station in use: the point on the ray from `origin` along
## `direction` (in the room's space) nearest the slot or tree node that the
## station's own pick chooses, as `HubStations.point` picks it (the drawing's
## `point_on`, then the hub text's `slot_at`), in the room's space; null when
## it picks none or the station draws nothing to point at.
static func slot_hit(stations: HubStations, room: HubRoom, origin: Vector3, direction: Vector3) -> Variant:
	var fitting: HubFittingView = stations.view(stations.in_use)
	var tree: HubTreeView = stations.tree_view(stations.in_use)
	var drawn: Node3D = fitting if fitting != null else tree
	if drawn == null or not drawn.call("can_point") or stations.hub == null or not stations.hub.has_method("slot_at"):
		return null
	var at: Variant = drawn.call("point_on", origin, direction, room)
	if not at is Vector2:
		return null
	var slot: String = stations.hub.call("slot_at", at)
	var spots: Dictionary[String, Node3D] = fitting.slot_nodes if fitting != null else tree.nodes
	if slot == "" or not spots.has(slot):
		return null
	return on_ray(origin, direction, HubScreenMeasure.in_space_of(spots[slot], room).origin)


## The point on `aim`'s ray at the entry `ShaftChoiceWiring.point_in` picks on
## `panel`, in the panel's parent's space; null when it picks none.
static func shaft_hit(panel: ShaftPanel, aim: Transform3D, radius: float) -> Variant:
	var kind: String = ShaftChoiceWiring.point_in(panel, aim, radius)
	if kind == "":
		return null
	var to_panel: Transform3D = panel.transform.affine_inverse()
	var landed: Vector3 = on_ray(to_panel * aim.origin, to_panel.basis * -aim.basis.z, panel.entry_points()[kind])
	return panel.transform * landed


## The point on the ray from `origin` along `direction` nearest `point`.
static func on_ray(origin: Vector3, direction: Vector3, point: Vector3) -> Vector3:
	var along: Vector3 = direction.normalized()
	return origin + along * maxf((point - origin).dot(along), 0.0)


## The shaft choice's pick radius, as `ShaftChoiceWiring._point` reads it.
func shaft_radius() -> float:
	return shaft_shapes.lengths.get("point_radius_m", 0.0) if shaft_shapes.error == "" else 0.0
