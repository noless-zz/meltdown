extends RefCounted

## A restart onto the test tunnel after a level draws the tunnel again and
## takes the level's drawing away (#795, DEV-6, CMF-8, MP-2): the dev menu's
## "Test tunnel" after a seed or level no longer flies the tunnel's walls inside
## the level's drawing.

const FRAME: float = 1.0 / 90.0
const G2_FILE: String = "res://data/levels/g2_level.json"
const SEED_SOURCE: String = "seed:31"


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


## Restarts `main` onto `source` the way the dev menu does once the view is black.
func _restart(main: Node, source: String) -> void:
	(main.get("level_start") as LevelStart).source = source
	main.call("restart_level")


func _fly(main: Node, frames: int) -> void:
	var input: ShipInput = ShipInput.from_floats(Vector3(0.2, 0.1, -1.0), Vector3(0.0, 0.3, 0.0))
	(main.get("input_source") as LatestInputSource).set_input(input)
	for i: int in frames:
		main.call("advance_frame", FRAME)


func _count(main: Node, node_name: String) -> int:
	var found: int = 0
	for child: Node in main.get_children():
		if child.name == node_name:
			found += 1
	return found


func _hash(main: Node) -> int:
	return (main.get("session") as LocalSession).sim.state_hash()


## "" when `main` shows only the drawing for `source`; otherwise what is wrong.
func _drawn_only(main: Node, source: String) -> String:
	var tunnels: int = _count(main, LevelSwitch.TUNNEL_NODE)
	var views: int = _count(main, LevelView.NODE_NAME)
	if source == "":
		if tunnels != 1 or views != 0:
			return "after a tunnel restart: %d tunnels, %d level views" % [tunnels, views]
		var tunnel: Node3D = main.get_node(LevelSwitch.TUNNEL_NODE) as Node3D
		if tunnel.position != LevelStart.TUNNEL_OFFSET:
			return "the tunnel is drawn at %s, not where its walls are" % tunnel.position
		return ""
	if tunnels != 0 or views != 1:
		return "after a restart on %s: %d tunnels, %d level views" % [source, tunnels, views]
	return ""


func test_a_tunnel_restart_after_a_level_draws_the_tunnel_and_drops_the_level() -> String:
	var main: Node = _main()
	_restart(main, SEED_SOURCE)
	var problem: String = _drawn_only(main, SEED_SOURCE)
	if problem == "":
		_fly(main, 20)
		_restart(main, "")
		problem = _drawn_only(main, "")
	main.free()
	return problem


func test_a_level_after_the_tunnel_restart_still_replaces_the_tunnel() -> String:
	var main: Node = _main()
	_restart(main, G2_FILE)
	_restart(main, "")
	_restart(main, G2_FILE)
	var problem: String = _drawn_only(main, G2_FILE)
	main.free()
	return problem


func test_tunnel_level_tunnel_level_leaves_one_drawing_each_time() -> String:
	var main: Node = _main()
	var problem: String = ""
	for source: String in [G2_FILE, "", SEED_SOURCE, "", G2_FILE, SEED_SOURCE, ""]:
		_restart(main, source)
		problem = _drawn_only(main, source)
		if problem != "":
			break
		_fly(main, 5)
	main.free()
	return problem


func test_a_tunnel_restart_flies_like_a_fresh_tunnel_start() -> String:
	var fresh: Node = _main()
	var main: Node = _main()
	_restart(main, SEED_SOURCE)
	_fly(main, 30)
	_restart(main, "")
	var problem: String = ""
	if _hash(main) != _hash(fresh):
		problem = "the state hash after the restart differs from a fresh tunnel start"
	else:
		_fly(fresh, 60)
		_fly(main, 60)
		if _hash(main) != _hash(fresh):
			problem = "60 frames after the restart the state differs from a fresh tunnel start"
	fresh.free()
	main.free()
	return problem


func test_a_tunnel_restart_on_the_tunnel_keeps_the_same_tunnel_node() -> String:
	var main: Node = _main()
	var before: Node = main.get_node(LevelSwitch.TUNNEL_NODE)
	_restart(main, "")
	var after: Node = main.get_node_or_null(LevelSwitch.TUNNEL_NODE)
	main.free()
	return "" if after == before else "a tunnel restart on the tunnel rebuilt the tunnel node"


func test_show_tunnel_puts_the_tunnel_back_at_the_offset() -> String:
	var world: Node3D = Node3D.new()
	var view: LevelView = LevelView.new()
	world.add_child(view)
	var tunnel: Node3D = LevelSwitch.show_tunnel(world, Vector3(0.0, -1.0, 0.0))
	var problem: String = ""
	if world.get_node_or_null(LevelView.NODE_NAME) != null:
		problem = "the level view stayed"
	elif tunnel == null or tunnel.name != LevelSwitch.TUNNEL_NODE or tunnel.get_parent() != world:
		problem = "no tunnel node was added"
	elif not (tunnel is TestTunnel):
		problem = "the tunnel node is not the test tunnel scene"
	elif tunnel.position != Vector3(0.0, -1.0, 0.0):
		problem = "the tunnel sits at %s" % tunnel.position
	world.free()
	return problem
