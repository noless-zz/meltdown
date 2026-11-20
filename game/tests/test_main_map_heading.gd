extends RefCounted

## In play the map's ship marker turns with the ship every frame (#679, MAP-1):
## after a turn its basis is the ship's interpolated orientation from the
## session, so the map alone shows which way the pilot faces.

const FRAME: float = 1.0 / 90.0
const EPSILON: float = 0.01


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("use_level", LevelSwitch.path_for("g2"))
	main.call("_ready")
	return main


func _close(a: Basis, b: Basis) -> bool:
	return (a.x - b.x).length() < EPSILON and (a.y - b.y).length() < EPSILON \
		and (a.z - b.z).length() < EPSILON


func test_the_marker_turns_with_the_ship_in_play() -> String:
	var main: Node = _main()
	main.call("advance_frame", 0.0)
	var source: LatestInputSource = main.get("input_source")
	# Yaw and roll together, so both heading and the top side change.
	source.set_input(ShipInput.new(Vector3i.ZERO, Vector3i(0, 1500, 1500)))
	for i: int in 45:
		main.call("advance_frame", FRAME)
	var session: LocalSession = main.get("session")
	var want: Basis = session.previous_ship().orientation.slerp(
		session.current_ship().orientation, session.interpolation_fraction)
	var wiring: MapWiring = main.get("map")
	var got: Basis = (wiring.hologram.get_node(MapHologram.MARKER_NAME) as Node3D).basis
	main.free()
	if _close(want, Basis.IDENTITY):
		return "the test turn did not turn the ship"
	if not _close(got, want):
		return "marker basis %s, ship %s" % [got, want]
	return ""
