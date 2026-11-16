extends RefCounted

## The projectiles drawn as bolts (CMB-1, MP-2, LGT-1): the view never writes
## to the projectiles, pools its bolts, places each one between ticks with the
## interpolation rule, draws a just-fired one where it is, points bolts along
## their flight and range-checks its look file.

const SCRIPT_PATH: String = "res://view/projectile_view.gd"
const OUTSIDE_DIRS: Array[String] = ["res://xr", "res://meta", "res://net"]
const EPSILON: float = 1e-5


func _valid_look() -> Dictionary:
	return {"bolt_length_m": 0.6, "bolt_radius_m": 0.03, "emission_color": [1.0, 0.5, 0.1]}


func _shots(count: int) -> Array[Projectile]:
	var shots: Array[Projectile] = []
	for index: int in count:
		shots.append(Projectile.new(Vector3(index, 0.0, 0.0), Vector3(0.0, 0.0, -60.0), 0, 30, 10.0))
	return shots


func _hash(projectiles: Array[Projectile]) -> int:
	var parts: Array[int] = []
	for projectile: Projectile in projectiles:
		parts.append(projectile.state_hash())
	return hash(parts)


func _bolt_ids(view: ProjectileView) -> Array[int]:
	var ids: Array[int] = []
	for child: Node in view.get_children():
		ids.append(child.get_instance_id())
	return ids


func test_shown_projectiles_are_not_written() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shots: Array[Projectile] = _shots(5)
	var before: int = _hash(shots)
	view.show_projectiles(shots, 0.0)
	for projectile: Projectile in shots:
		projectile.advance()
	var advanced: int = _hash(shots)
	view.show_projectiles(shots, 0.5)
	view.show_projectiles(shots, 1.0)
	var after: int = _hash(shots)
	view.free()
	if advanced == before:
		return "advancing the projectiles did not change the hash; the check is blind"
	if after != advanced:
		return "show_projectiles changed the projectiles"
	return ""


func test_bolts_are_pooled() -> String:
	var view: ProjectileView = ProjectileView.new()
	var result: String = ""
	view.show_projectiles(_shots(4), 0.5)
	var ids: Array[int] = _bolt_ids(view)
	view.show_projectiles(_shots(4), 0.5)
	if _bolt_ids(view) != ids:
		result = "bolt nodes changed while the count stayed at 4"
	view.show_projectiles(_shots(7), 0.5)
	if result == "" and (view.bolt_count() != 7 or view.get_child_count() != 7):
		result = "7 shots gave %d bolts and %d children" % [view.bolt_count(), view.get_child_count()]
	var grown: Array[int] = _bolt_ids(view)
	view.show_projectiles(_shots(2), 0.5)
	if result == "" and _bolt_ids(view) != grown:
		result = "bolts were freed or replaced when the count fell"
	if result == "":
		for index: int in 7:
			if view.bolt(index).visible != (index < 2):
				result = "bolt %d visible is %s with 2 shots" % [index, view.bolt(index).visible]
	view.show_projectiles([] as Array[Projectile], 0.5)
	if result == "" and (view.bolt_count() != 7 or view.bolt(0).visible):
		result = "an empty list did not hide every bolt in the pool"
	view.free()
	return result


func test_bolts_are_interpolated_between_ticks() -> String:
	var view: ProjectileView = ProjectileView.new()
	var shot: Projectile = Projectile.new(Vector3(1.0, 2.0, 3.0), Vector3(6.0, 0.0, -60.0), 0, 30, 1.0)
	var shots: Array[Projectile] = [shot]
	view.show_projectiles(shots, 0.0)
	shot.advance()
	var result: String = ""
	for alpha: float in [0.0, 0.25, 0.5, 1.0]:
		view.show_projectiles(shots, alpha)
		var expected: Vector3 = shot.position + shot.velocity * ShipState.TICK_DT * (alpha - 1.0)
		if not view.bolt(0).position.is_equal_approx(expected):
			result = "alpha %s drew %s, expected %s" % [alpha, view.bolt(0).position, expected]
			break
	view.show_projectiles(shots, 2.0)
	if result == "" and not view.bolt(0).position.is_equal_approx(shot.position):
		result = "alpha above 1 was not clamped: drew %s" % view.bolt(0).position
	view.free()
	return result


func test_a_projectile_fired_this_tick_is_drawn_where_it_is() -> String:
	var view: ProjectileView = ProjectileView.new()
	var old: Projectile = Projectile.new(Vector3.ZERO, Vector3(0.0, 0.0, -60.0), 0, 30, 1.0)
	var shots: Array[Projectile] = [old]
	view.show_projectiles(shots, 0.0)
	old.advance()
	var fired: Projectile = Projectile.new(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -60.0), 0, 30, 1.0)
	shots.append(fired)
	var result: String = ""
	# Several frames can fall within one tick; none may draw it behind the muzzle.
	for alpha: float in [0.2, 0.6]:
		view.show_projectiles(shots, alpha)
		if not view.bolt(1).position.is_equal_approx(fired.position):
			result = "fired this tick, alpha %s drew %s, not %s" % [alpha, view.bolt(1).position, fired.position]
			break
	if result == "" and view.bolt(0).position.is_equal_approx(old.position):
		result = "the older projectile was not interpolated"
	old.advance()
	fired.advance()
	view.show_projectiles(shots, 0.5)
	var expected: Vector3 = fired.position + fired.velocity * ShipState.TICK_DT * -0.5
	if result == "" and not view.bolt(1).position.is_equal_approx(expected):
		result = "on its next tick it drew %s, expected %s" % [view.bolt(1).position, expected]
	view.free()
	return result


func test_bolts_point_along_their_velocity() -> String:
	var directions: Array[Vector3] = [
		Vector3.FORWARD, Vector3.UP, Vector3.DOWN, Vector3(1.0, 2.0, -3.0), Vector3(0.0, 0.01, 5.0),
	]
	for direction: Vector3 in directions:
		var basis: Basis = ProjectileView.bolt_basis(direction * 40.0)
		if not basis.y.is_equal_approx(direction.normalized()):
			return "bolt axis %s for velocity %s" % [basis.y, direction]
		if not is_equal_approx(basis.determinant(), 1.0) or not basis.is_conformal():
			return "basis for %s is not a pure rotation: %s" % [direction, basis]
	if ProjectileView.bolt_basis(Vector3.ZERO) != Basis.IDENTITY:
		return "a projectile at rest did not get the identity"
	var view: ProjectileView = ProjectileView.new()
	var shots: Array[Projectile] = [Projectile.new(Vector3.ZERO, Vector3(3.0, 0.0, 4.0), 0, 30, 1.0)]
	view.show_projectiles(shots, 1.0)
	var axis: Vector3 = view.bolt(0).basis.y
	view.free()
	if not axis.is_equal_approx(Vector3(0.6, 0.0, 0.8)):
		return "the shown bolt points along %s" % axis
	return ""


func test_look_file_loads_and_shapes_the_bolts() -> String:
	var view: ProjectileView = ProjectileView.new()
	var result: String = view.look_error
	var bolt_mesh: CylinderMesh = null
	if result == "":
		view.show_projectiles(_shots(1), 1.0)
		bolt_mesh = view.bolt(0).mesh as CylinderMesh
	if result == "" and bolt_mesh == null:
		result = "a bolt has no cylinder mesh"
	if result == "" and (not is_equal_approx(bolt_mesh.height, view.bolt_length_m)
			or not is_equal_approx(bolt_mesh.top_radius, view.bolt_radius_m)):
		result = "the mesh does not follow the look file"
	if result == "":
		var material: StandardMaterial3D = bolt_mesh.material as StandardMaterial3D
		if material == null or material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
				or not material.emission_enabled or material.emission != view.emission_color:
			result = "the bolt material is not unshaded and emissive in the look's colour"
	if result == "" and view.bolt(0).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		result = "bolts cast shadows"
	view.free()
	return result


func test_bad_look_values_are_rejected_with_the_field_named() -> String:
	for key: String in ProjectileView.KEYS:
		var high: Dictionary = _valid_look()
		high[key] = [2.0, 0.5, 0.5] if key == "emission_color" else float(ProjectileView.RANGES[key][1]) + 1.0
		var low: Dictionary = _valid_look()
		low[key] = [0.5, -0.1, 0.5] if key == "emission_color" else float(ProjectileView.RANGES[key][0]) - 0.001
		var missing: Dictionary = _valid_look()
		missing.erase(key)
		var wrong_type: Dictionary = _valid_look()
		wrong_type[key] = true
		for bad: Dictionary in [high, low, missing, wrong_type]:
			var error: Variant = ProjectileView.parse_look(JSON.stringify(bad)).get("error", "")
			if error == "" or not key in str(error):
				return "%s gave error \"%s\"" % [JSON.stringify(bad), error]
	var short_color: Dictionary = _valid_look()
	short_color["emission_color"] = [1.0, 0.5]
	var unknown: Dictionary = _valid_look()
	unknown["glow"] = 1.0
	for bad: Dictionary in [short_color, unknown]:
		if not ProjectileView.parse_look(JSON.stringify(bad)).has("error"):
			return "%s was accepted" % JSON.stringify(bad)
	if ProjectileView.parse_look(JSON.stringify(_valid_look())).has("error"):
		return "valid data was rejected"
	return ""


func test_a_rejected_or_missing_look_falls_back_to_defaults() -> String:
	var view: ProjectileView = ProjectileView.new()
	var result: String = ""
	view.bolt_length_m = 3.0
	var error: String = view.load_look("res://view/no_such_look.json")
	if error == "" or view.look_error != error:
		result = "a missing file gave no error"
	elif view.bolt_length_m != ProjectileView.DEFAULT_BOLT_LENGTH_M \
			or view.bolt_radius_m != ProjectileView.DEFAULT_BOLT_RADIUS_M \
			or view.emission_color != ProjectileView.DEFAULT_EMISSION_COLOR:
		result = "a missing file did not restore the default look"
	if result == "" and view.load_look() != "":
		result = "the shipped look file was rejected: %s" % view.look_error
	view.free()
	return result


## The defaults in code and the shipped file are the same look, so a missing
## file on a device does not change what the player sees.
func test_defaults_match_the_shipped_file() -> String:
	var values: Dictionary = ProjectileView.parse_look(
		FileAccess.get_file_as_string(ProjectileView.DEFAULT_LOOK_FILE))
	if values.has("error"):
		return str(values["error"])
	if not is_equal_approx(values["bolt_length_m"], ProjectileView.DEFAULT_BOLT_LENGTH_M) \
			or not is_equal_approx(values["bolt_radius_m"], ProjectileView.DEFAULT_BOLT_RADIUS_M) \
			or not (values["emission_color"] as Color).is_equal_approx(ProjectileView.DEFAULT_EMISSION_COLOR):
		return "shipped look %s differs from the defaults" % values
	return ""


## `view/` may read `core/` and nothing in `xr/`, `meta/` or `net/`.
func test_reads_no_layer_above_core() -> String:
	var source: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	var found_any: bool = false
	for root: String in OUTSIDE_DIRS:
		for file: String in DirAccess.get_files_at(root):
			if not file.ends_with(".gd"):
				continue
			var found: RegExMatch = RegEx.create_from_string("class_name\\s+(\\w+)") \
				.search(FileAccess.get_file_as_string(root.path_join(file)))
			if found == null:
				continue
			found_any = true
			if RegEx.create_from_string("\\b%s\\b" % found.get_string(1)).search(source) != null:
				return "%s references %s from %s" % [SCRIPT_PATH, found.get_string(1), root]
	if not found_any:
		return "no classes were read from %s" % [OUTSIDE_DIRS]
	return ""
