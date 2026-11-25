extends RefCounted

## `ShipModel` (#1362, GFX-2, PRF-4, MP-2, GFX-4): every piece of the shipped
## look builds with its material, thrust brightens the engine, the pose is
## the one handed in, it stays within its draw-call budget, adds no light,
## and ships of one look share their lit materials.


func test_every_piece_builds_with_its_material() -> String:
	var look: ShipLook = ShipLook.load_file()
	var model: ShipModel = ShipModel.create(look)
	var specs: Array = look.look["pieces"]
	var problem: String = ""
	if model.pieces().size() != specs.size():
		problem = "%d pieces built for %d in the file" % [model.pieces().size(), specs.size()]
	for index: int in mini(specs.size(), model.pieces().size()):
		var piece: MeshInstance3D = model.pieces()[index]
		var spec: Dictionary = specs[index]
		var want: Material = model.engine_material() if spec["material"] == ShipLook.ENGINE else look.material(spec["material"])
		if problem == "" and piece.material_override != want:
			problem = "piece %d does not wear \"%s\"" % [index, spec["material"]]
		if problem == "" and piece.mesh != ShipModel.mesh_for(spec["shape"]):
			problem = "piece %d is not a shared %s" % [index, spec["shape"]]
		if problem == "" and not piece.position.is_equal_approx(spec["offset"]):
			problem = "piece %d sits at %s, the file says %s" % [index, piece.position, spec["offset"]]
	model.free()
	return problem


func test_the_nose_is_forward_and_the_engine_behind() -> String:
	var model: ShipModel = ShipModel.create()
	var front: float = 0.0
	var engine_z: float = 0.0
	for piece: MeshInstance3D in model.pieces():
		var box: AABB = piece.transform * piece.get_aabb()
		front = minf(front, box.position.z)
		if piece.material_override == model.engine_material():
			engine_z = box.get_center().z
	model.free()
	if engine_z <= 0.5:
		return "the engine glow is at z %.2f, not at the back" % engine_z
	if front > -1.0:
		return "the nose reaches only to z %.2f" % front
	return ""


func test_thrust_brightens_the_engine_and_is_clamped() -> String:
	var model: ShipModel = ShipModel.create()
	var engine: Dictionary = ShipLook.load_file().look["engine"]
	model.set_thrust(0.0)
	var idle: float = model.engine_energy()
	model.set_thrust(0.5)
	var half: float = model.engine_energy()
	model.set_thrust(3.0)
	var full: float = model.engine_energy()
	var clamped: float = model.thrust()
	model.free()
	if not is_equal_approx(idle, engine["idle_energy"]) or not is_equal_approx(full, engine["full_energy"]):
		return "idle %.2f and full %.2f, the file says %.2f and %.2f" % [idle, full, engine["idle_energy"], engine["full_energy"]]
	if not (half > idle and half < full):
		return "half thrust gives %.2f" % half
	if not is_equal_approx(clamped, 1.0):
		return "thrust 3 is kept as %.2f" % clamped
	return ""


func test_show_at_takes_the_pose_and_thrust_only() -> String:
	var model: ShipModel = ShipModel.create()
	var pose: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.0, -2.0, 5.0))
	model.show_at(pose, 0.25)
	var problem: String = ""
	if not model.transform.is_equal_approx(pose):
		problem = "the model sits at %s" % model.transform
	elif not is_equal_approx(model.thrust(), 0.25):
		problem = "thrust %.2f" % model.thrust()
	model.free()
	return problem


func test_one_ship_stays_within_its_draw_budget_and_adds_no_light() -> String:
	var model: ShipModel = ShipModel.create()
	var cost: Dictionary = model.cost()
	var lights: int = model.find_children("*", "Light3D", true, false).size()
	model.free()
	if int(cost["draw_calls"]) > ShipLook.MAX_PIECES:
		return "%d draw calls" % cost["draw_calls"]
	if int(cost["materials"]) > int(cost["pieces"]) or int(cost["triangles"]) <= 0:
		return "cost %s" % cost
	if lights != 0:
		return "%d lights" % lights
	return ""


func test_two_ships_share_lit_materials_but_not_their_engines() -> String:
	var look: ShipLook = ShipLook.load_file()
	var a: ShipModel = ShipModel.create(look)
	var b: ShipModel = ShipModel.create(look)
	a.set_thrust(1.0)
	b.set_thrust(0.0)
	var problem: String = ""
	if a.pieces()[0].material_override != b.pieces()[0].material_override:
		problem = "two ships of one look draw the hull with two materials"
	elif is_equal_approx(a.engine_energy(), b.engine_energy()):
		problem = "one ship's thrust changed the other's engine"
	a.free()
	b.free()
	return problem


func test_a_refused_look_builds_the_plain_hull() -> String:
	var look: ShipLook = ShipLook.new()
	look.use({"materials": {}})
	var model: ShipModel = ShipModel.create(look)
	var count: int = model.pieces().size()
	model.free()
	if look.error == "":
		return "the bad look was accepted"
	return "" if count == ShipLook.PLAIN["pieces"].size() else "%d pieces built" % count


func test_rebuilding_replaces_the_pieces() -> String:
	var model: ShipModel = ShipModel.create()
	var plain: ShipLook = ShipLook.new()
	plain.use(ShipLook.PLAIN)
	model.build(plain)
	var count: int = model.get_child_count()
	model.free()
	return "" if count == ShipLook.PLAIN["pieces"].size() else "%d children after a rebuild" % count
