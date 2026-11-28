extends RefCounted

## The aim ray inside a station (#1470, CRW-2, RUN-1, ARC-3, MP-2): at the
## Fitting Bay it ends with its dot on the slot the stations' own pick selects,
## at the Workbench on the tree node it selects, and it fades out at its length
## when the aim picks nothing there.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")
const FittingView: GDScript = preload("res://tests/test_hub_fitting_view.gd")
const Bench: GDScript = preload("res://tests/test_hub_craft_moment.gd")
const EPSILON: float = 0.0005


## An aim pose at `origin` looking along `along`, in the room's space (the room
## sits at the origin of the stand-in rig, so its parent's space is the same).
static func _aim(origin: Vector3, along: Vector3) -> Transform3D:
	var up: Vector3 = Vector3.UP if absf(along.normalized().dot(Vector3.UP)) < 0.99 else Vector3.BACK
	return Transform3D(Basis.looking_at(along, up), origin)


## Aims at `spot` (a drawn slot or node) from 0.6 m in front of its face and
## checks the picked id, the ray's end and its dot; "" when all agree.
static func _check_aim_at(stations: HubStations, spot: Node3D, id: String) -> String:
	var room: HubRoom = stations.get_parent() as HubRoom
	var at: Transform3D = HubScreenMeasure.in_space_of(spot, room)
	var facing: Vector3 = at.basis.z.normalized()
	var aim: Transform3D = _aim(at.origin + facing * 0.6, -facing)
	var hit: Variant = AimTargets.station_hit(stations, room, aim)
	var picked: String = stations.point(aim.origin, -aim.basis.z)
	if picked != id:
		return "aiming at %s, the stations picked '%s'" % [id, picked]
	if not hit is Vector3:
		return "aiming at %s, the ray lands on nothing" % id
	var ray: AimRay = AimRay.new()
	ray.show_from(aim, hit)
	var end: Vector3 = ray.end_point()
	var shown: bool = ray.shows_dot()
	ray.free()
	var along: Vector3 = -aim.basis.z.normalized()
	var off_ray: float = (end - aim.origin).cross(along).length()
	if not shown or off_ray > EPSILON or absf((at.origin - end).dot(along)) > EPSILON:
		return "aiming at %s the ray ends at %s (dot %s), not across from it at %s" % [id, end, shown, at.origin]
	return ""


func test_at_the_fitting_bay_the_ray_ends_on_the_slot_picked() -> String:
	var opened: Array = FittingView._on_the_bay()
	var stations: HubStations = opened[1]
	stations.advance(HubStations.SETTLE_SECONDS)
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var problem: String = "the bay draws no slots" if view == null or view.slot_nodes.is_empty() else ""
	for slot: String in (view.slot_nodes.keys() if view != null else []):
		if problem != "":
			break
		problem = _check_aim_at(stations, view.slot_nodes[slot], slot)
	Stations._free(stations)
	return problem


func test_at_the_workbench_the_ray_ends_on_the_node_picked() -> String:
	var opened: Array = Bench._at_the_bench()
	var stations: HubStations = opened[1]
	stations.advance(HubStations.SETTLE_SECONDS)
	var view: HubTreeView = stations.tree_view(HubCraftTree.STATION)
	var problem: String = "the bench draws no tree nodes" if view == null or view.nodes.is_empty() else ""
	var checked: int = 0
	for id: String in (view.nodes.keys() if view != null else []):
		if problem != "":
			break
		# Only nodes the hub text can select are picked by the aim; the rest are skipped.
		var room: HubRoom = stations.get_parent() as HubRoom
		var at: Transform3D = HubScreenMeasure.in_space_of(view.nodes[id], room)
		var facing: Vector3 = at.basis.z.normalized()
		var spot: Variant = view.point_on(at.origin + facing * 0.6, -facing, room)
		if spot is Vector2 and str(stations.hub.call("slot_at", spot)) == id:
			problem = _check_aim_at(stations, view.nodes[id], id)
			checked += 1
	if problem == "" and checked == 0:
		problem = "the aim picks none of the bench's %d nodes" % view.nodes.size()
	Stations._free(stations)
	return problem


func test_inside_a_station_a_miss_fades_out_at_its_length() -> String:
	var opened: Array = FittingView._on_the_bay()
	var stations: HubStations = opened[1]
	stations.advance(HubStations.SETTLE_SECONDS)
	var room: HubRoom = stations.get_parent() as HubRoom
	var view: HubFittingView = stations.view(HubFitBay.STATION)
	var at: Transform3D = HubScreenMeasure.in_space_of(view.slot_nodes.values()[0], room)
	var facing: Vector3 = at.basis.z.normalized()
	var problem: String = ""
	for aim: Transform3D in [_aim(at.origin + facing * 0.6, facing), _aim(at.origin + facing * 0.6, at.basis.y)]:
		var hit: Variant = AimTargets.station_hit(stations, room, aim)
		var ray: AimRay = AimRay.new()
		ray.show_from(aim, hit)
		var length: float = ray.end_point().distance_to(aim.origin)
		if hit != null or ray.shows_dot() or absf(length - ray.spec.length_m) > EPSILON:
			problem = "a miss in the bay lands on %s, dot %s, length %.3f" % [hit, ray.shows_dot(), length]
		ray.free()
		if problem != "":
			break
	Stations._free(stations)
	return problem
