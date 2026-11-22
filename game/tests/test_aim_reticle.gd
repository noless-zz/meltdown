extends RefCounted

## The aiming reticle (CMB-6, ARC-4, ARC-3, #923, #1211): its look file, its
## place along the simulated gun direction read from a fed ship state, and that
## it shows on every comfort preset. Its robot target: `test_aim_reticle_target.gd`.


func test_the_shipped_look_file_is_accepted_and_matches_the_fallback() -> String:
	var text: String = FileAccess.get_file_as_string(AimReticleLook.DEFAULT_FILE)
	var look: Dictionary = AimReticleLook.parse(text)
	if look.has("error"):
		return "shipped look rejected: %s" % look["error"]
	for key: String in AimReticleLook.FALLBACK:
		if look[key] != AimReticleLook.FALLBACK[key]:
			return "\"%s\" is %s in the file but %s in FALLBACK" % [key, look[key], AimReticleLook.FALLBACK[key]]
	return ""


func test_a_bad_look_file_is_rejected_naming_the_key() -> String:
	var good: Dictionary = {"distance_m": 25.0, "radius_m": 0.5, "thickness_m": 0.04,
		"cone_degrees": 4.0, "dim_alpha": 0.35, "color": [0.4, 1.0, 0.55, 0.85]}
	if AimReticleLook.parse(JSON.stringify(good)).has("error"):
		return "a good look file was rejected"
	var cases: Dictionary = {
		"cone_degrees": {"cone_degrees": 0.0},
		"dim_alpha": {"dim_alpha": 1.5},
		"distance_m": {"distance_m": 1.0},
		"radius_m": {"radius_m": true},
		"thickness_m": {"thickness_m": 0.6},
		"color": {"color": [1.0, 1.0, 1.0]},
		"spin": {"spin": 1.0},
	}
	for key: String in cases:
		var data: Dictionary = good.duplicate()
		data.merge(cases[key], true)
		var look: Dictionary = AimReticleLook.parse(JSON.stringify(data))
		if not look.has("error") or not str(look["error"]).contains(key):
			return "a bad \"%s\" gave %s" % [key, look]
	var missing: Dictionary = good.duplicate()
	missing.erase("color")
	if not AimReticleLook.parse(JSON.stringify(missing)).has("error"):
		return "a file without \"color\" was accepted"
	return ""


func test_it_sits_along_the_ship_gun_direction_at_the_look_distance() -> String:
	var state: ShipState = ShipState.new()
	state.position = Vector3(3.0, -2.0, 10.0)
	state.orientation = Basis(Vector3.UP, deg_to_rad(90.0))  # Nose turned left, to -x.
	state.gun_direction = Vector3(sin(deg_to_rad(10.0)), 0.0, -cos(deg_to_rad(10.0)))  # 10 degrees right.
	var pose: Transform3D = Transform3D(state.orientation, state.position)
	var reticle: AimReticle = AimReticle.new()
	reticle.show_aim(pose, state.gun_direction)
	var distance: float = float(reticle.look["distance_m"])
	var expected: Vector3 = state.position + (state.orientation * state.gun_direction) * distance
	var at: Vector3 = reticle.transform.origin
	var facing: Vector3 = -reticle.transform.basis.z
	var shown: bool = reticle.visible
	reticle.free()
	if not at.is_equal_approx(expected):
		return "reticle at %s, expected %s" % [at, expected]
	if facing.dot((expected - state.position).normalized()) < 0.9999:
		return "reticle faces %s, not along the guns" % facing
	if not shown:
		return "reticle hidden"
	return ""


func test_it_sits_on_the_nose_when_the_guns_rest() -> String:
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	var at: Transform3D = AimReticle.placed(pose, LookAim.NOSE, 20.0)
	if not at.origin.is_equal_approx(Vector3(1.0, 2.0, -17.0)):
		return "the nose reticle sits at %s" % at.origin
	var up: Transform3D = AimReticle.placed(pose, Vector3.UP, 20.0)
	if not up.basis.is_finite() or not up.origin.is_equal_approx(Vector3(1.0, 22.0, 3.0)):
		return "guns straight up gave %s" % up
	return ""


func test_a_new_reticle_waits_hidden_until_it_is_placed() -> String:
	var reticle: AimReticle = AimReticle.new()
	var hidden_at_start: bool = not reticle.visible
	reticle.show_aim(Transform3D.IDENTITY, LookAim.NOSE)
	var shown: bool = reticle.visible
	reticle.free()
	if not hidden_at_start:
		return "a new reticle is visible before anything places it"
	if not shown:
		return "the reticle stayed hidden after it was placed"
	return ""


func test_combat_wiring_shows_it_on_every_preset() -> String:
	for number: int in range(1, 5):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		if preset == null:
			return "preset %d did not load" % number
		var world: Node3D = Node3D.new()
		var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
		var combat: CombatWiring = CombatWiring.new()
		combat.attach(world)
		combat.update(session, null, null, 0.0, preset.look_aim)
		var shown: bool = combat.aim_reticle.visible
		var at: Vector3 = combat.aim_reticle.transform.origin
		var parented: bool = combat.aim_reticle.get_parent() == world
		var ship: ShipState = session.current_ship()
		var expected: Vector3 = ship.position + ship.orientation * ship.gun_direction \
			* combat.aim_reticle.shown_distance
		world.free()
		if not parented:
			return "the reticle is not under the world node"
		if not shown:
			return "reticle hidden on preset %d (look-aim %s)" % [number, preset.look_aim]
		if not at.is_equal_approx(expected):
			return "preset %d: reticle at %s, expected %s from the ship's gun direction" % [number, at, expected]
	return ""


func test_on_preset_4_without_the_module_it_sits_on_the_nose() -> String:
	var preset: ComfortPreset = ComfortPresetFiles.load_number(4)
	if preset == null or preset.look_aim:
		return "preset 4 should load with look-aim off"
	var world: Node3D = Node3D.new()
	var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
	var combat: CombatWiring = CombatWiring.new()
	combat.attach(world)
	combat.update(session, null, null, 0.0, preset.look_aim)
	var ship: ShipState = session.current_ship()
	var facing: Vector3 = -combat.aim_reticle.transform.basis.z.normalized()
	var nose: Vector3 = (ship.orientation * LookAim.NOSE).normalized()
	var shown: bool = combat.aim_reticle.visible
	world.free()
	if not ship.gun_direction.is_equal_approx(LookAim.NOSE):
		return "the guns start at %s, not on the nose" % ship.gun_direction
	if not shown or facing.dot(nose) < 0.9999:
		return "preset 4: reticle shown %s facing %s, nose %s" % [shown, facing, nose]
	return ""


func test_the_reticle_reads_state_only() -> String:
	var source: String = FileAccess.get_file_as_string("res://view/aim_reticle.gd")
	for forbidden: String in ["gun_direction =", "set_input", ".step(", "LocalSession"]:
		if source.find(forbidden) >= 0:
			return "aim_reticle.gd uses %s; it may only read state" % forbidden
	return ""
