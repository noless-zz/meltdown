extends RefCounted

## Each weapon's own bolt (#1309, GFX-2, ARC-4): the look builds from the
## shipped file, every documented key changes what is drawn, a missing key or
## weapon row keeps today's look, bad rows are rejected naming the field, and
## the view draws each slot's bolt with its weapon's mesh, trail and flash.

const PLAYER_WEAPONS: Array[String] = ["needle_gun", "pulse_cannon", "arc_lance", "slug_thrower"]
## A value for each weapon key unlike both the defaults and the shipped file's.
const OTHER: Dictionary = {
	"bolt_shape": "capsule", "bolt_length_m": 1.7, "bolt_radius_m": 0.21,
	"emission_color": [0.1, 0.2, 0.9], "trail_length_m": 5.5, "trail_color": [0.9, 0.1, 0.1],
	"muzzle_flash_radius_m": 0.33, "spark_color": [0.2, 0.9, 0.2],
}


func _shipped() -> Dictionary:
	return ProjectileLook.parse(FileAccess.get_file_as_string(ProjectileLook.DEFAULT_FILE))


func _ship(weapons: Array[String]) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.primary_ids.assign(weapons)
	return ship


func test_the_shipped_file_builds_and_every_player_and_robot_weapon_looks_different() -> String:
	var look: Dictionary = _shipped()
	if look.has("error"):
		return str(look["error"])
	var seen: Array[String] = []
	for weapon: String in PLAYER_WEAPONS + ([ProjectileWeaponLooks.ROBOT_ROW] as Array[String]):
		if not (look[ProjectileLook.WEAPONS_KEY] as Dictionary).has(weapon):
			return "the shipped file has no row for %s" % weapon
		var merged: Dictionary = ProjectileWeaponLooks.look_for(look, weapon)
		var key: String = "%s %s %s" % [merged["bolt_shape"], merged["emission_color"], merged["bolt_length_m"]]
		if seen.has(key):
			return "%s looks like another weapon: %s" % [weapon, key]
		seen.append(key)
	return ""


func test_every_weapon_key_changes_that_weapons_bolt_only() -> String:
	var text: Dictionary = {"weapons": {"test_gun": {}}}
	for key: String in ProjectileWeaponLooks.KEYS:
		text["weapons"]["test_gun"] = {key: OTHER[key]}
		var look: Dictionary = ProjectileLook.parse(JSON.stringify(text))
		if look.has("error"):
			return "%s: %s" % [key, look["error"]]
		var own: Dictionary = ProjectileWeaponLooks.look_for(look, "test_gun")
		var other: Dictionary = ProjectileWeaponLooks.look_for(look, "another_gun")
		if str(own[key]) == str(other[key]):
			return "%s did not change the weapon's look" % key
		if str(other[key]) != str(ProjectileLook.DEFAULTS[key]):
			return "%s leaked to a weapon without a row" % key
	return ""


func test_shape_length_radius_and_colour_change_the_head_mesh() -> String:
	var plain: PrimitiveMesh = BoltMeshes.build_head("cylinder", 0.6, 0.03, Color.ORANGE)
	for shape: String in BoltMeshes.SHAPES:
		var mesh: PrimitiveMesh = BoltMeshes.build_head(shape, 0.6, 0.03, Color.ORANGE)
		if shape != "cylinder" and mesh.get_class() == plain.get_class() \
				and (mesh as CylinderMesh).top_radius == (plain as CylinderMesh).top_radius:
			return "shape %s draws a plain rod" % shape
	var longer: CylinderMesh = BoltMeshes.build_head("cylinder", 1.2, 0.03, Color.ORANGE) as CylinderMesh
	var wider: CylinderMesh = BoltMeshes.build_head("cylinder", 0.6, 0.06, Color.ORANGE) as CylinderMesh
	var bluer: CylinderMesh = BoltMeshes.build_head("cylinder", 0.6, 0.03, Color.BLUE) as CylinderMesh
	if not is_equal_approx(longer.height, 1.2) or not is_equal_approx(wider.bottom_radius, 0.06):
		return "length or radius did not reach the mesh"
	if (bluer.material as StandardMaterial3D).emission != Color.BLUE:
		return "the colour did not reach the material"
	return ""


func test_top_level_keys_change_the_parsed_look() -> String:
	var defaults: Dictionary = ProjectileLook.parse("{}")
	var shipped: Dictionary = _shipped()
	var changed: int = 0
	for key: String in ProjectileLook.KEYS:
		if not ProjectileLook.FIRST_KEYS.has(key) and str(shipped[key]) != str(defaults[key]):
			changed += 1
	# The shipped file switches on trails, sparks, scorches and hit bursts.
	return "" if changed >= 7 else "only %d new keys differ from today's look" % changed


func test_a_missing_key_or_row_keeps_todays_look() -> String:
	var look: Dictionary = ProjectileLook.parse("{}")
	if look.has("error"):
		return "an empty file was rejected: %s" % look["error"]
	for key: String in ProjectileLook.KEYS:
		if str(look[key]) != str(ProjectileLook.DEFAULTS[key]):
			return "missing %s gave %s" % [key, look[key]]
	if look["trail_length_m"] != 0.0 or look["spark_count"] != 0 or look["scorch_fade_s"] != 0.0:
		return "today's look gained effects"
	var shipped: Dictionary = _shipped()
	var unknown: Dictionary = ProjectileWeaponLooks.look_for(shipped, "no_such_gun")
	for key: String in ProjectileWeaponLooks.KEYS:
		if str(unknown[key]) != str(shipped[key]):
			return "a weapon with no row did not keep the file's %s" % key
	return ""


func test_bad_weapon_rows_are_rejected_naming_the_field() -> String:
	var bad_rows: Array = [
		[{"weapons": []}, "weapons"],
		[{"weapons": {"gun": 3}}, "gun"],
		[{"weapons": {"gun": {"glow": 1.0}}}, "glow"],
		[{"weapons": {"gun": {"bolt_shape": "cube"}}}, "bolt_shape"],
		[{"weapons": {"gun": {"bolt_length_m": 50.0}}}, "bolt_length_m"],
		[{"weapons": {"gun": {"trail_color": [1.0, 0.5]}}}, "trail_color"],
		[{"bolt_shape": 2}, "bolt_shape"],
	]
	for row: Array in bad_rows:
		var error: String = str(ProjectileLook.parse(JSON.stringify(row[0])).get("error", ""))
		if error.is_empty() or not (row[1] as String) in error:
			return "%s gave \"%s\"" % [JSON.stringify(row[0]), error]
	return ""


func test_a_bolt_is_told_by_its_slot_or_its_robot() -> String:
	var rows: Dictionary = {"needle_gun": {}, "robot_arc": {}}
	var ships: Array[ShipState] = [_ship(["pulse_cannon", "needle_gun"])]
	var def: RobotDef = RobotDef.new()
	def.weapon = "robot_arc"
	var robot: RobotState = RobotState.new(def)
	var robots: Array[RobotState] = [robot, null]
	var second: Projectile = Projectile.new(Vector3.ZERO, Vector3.FORWARD, 0, 10, 1.0)
	second.slot = 1
	var cases: Array = [
		[second, "needle_gun"],
		[Projectile.new(Vector3.ZERO, Vector3.FORWARD, 0, 10, 1.0), "pulse_cannon"],
		[Projectile.new(Vector3.ZERO, Vector3.FORWARD, Projectile.robot_owner(0), 10, 1.0), "robot_arc"],
		[Projectile.new(Vector3.ZERO, Vector3.FORWARD, Projectile.robot_owner(1), 10, 1.0), "robot"],
		[Projectile.new(Vector3.ZERO, Vector3.FORWARD, 3, 10, 1.0), ""],
	]
	for case: Array in cases:
		var got: String = ProjectileWeaponLooks.weapon_of(case[0], ships, robots, rows)
		if got != case[1]:
			return "expected %s, got %s" % [case[1], got]
	return ""


func test_the_view_draws_each_slot_with_its_weapon() -> String:
	var view: ProjectileView = ProjectileView.new()
	var result: String = view.look_error
	view.set_scene([_ship(["needle_gun", "slug_thrower"])] as Array[ShipState], [], null)
	var right: Projectile = Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -180.0), 0, 40, 3.0)
	var left: Projectile = Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -60.0), 0, 40, 30.0)
	left.slot = 1
	var poses: Array[Transform3D] = [Transform3D.IDENTITY]
	view.show_projectiles([right, left] as Array[Projectile], 1.0, poses)
	var needle: Dictionary = view.meshes.look("needle_gun")
	var slug: Dictionary = view.meshes.look("slug_thrower")
	if result == "" and view.bolt(0).mesh != view.meshes.head("needle_gun"):
		result = "slot 1's bolt is not drawn as its needle gun"
	if result == "" and view.bolt(1).mesh != view.meshes.head("slug_thrower"):
		result = "slot 2's bolt is not drawn as its slug thrower"
	if result == "" and (view.trail(0).visible or view.trail(1).visible):
		result = "a bolt at its muzzle already trails back into the cockpit"
	var flashes: Array[MeshInstance3D] = view.muzzle_flashes.shown()
	if result == "" and (flashes.size() != 2 or not is_equal_approx(flashes[0].scale.x,
			needle["muzzle_flash_radius_m"]) or not is_equal_approx(flashes[1].scale.x, slug["muzzle_flash_radius_m"])):
		result = "each slot's muzzle did not flash at its weapon's size"
	for tick: int in 20:
		right.advance()
		left.advance()
	view.show_projectiles([right, left] as Array[Projectile], 1.0, poses)
	if result == "" and not (view.trail(0).visible and view.trail(1).visible):
		result = "flying bolts have no trail"
	if result == "" and (not is_equal_approx(view.trail(0).scale.y, needle["trail_length_m"])
			or view.trail(0).mesh != view.meshes.trail("needle_gun")):
		result = "the needle trail is %s long, not %s" % [view.trail(0).scale.y, needle["trail_length_m"]]
	view.free()
	return result
