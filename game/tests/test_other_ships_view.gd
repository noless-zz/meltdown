extends RefCounted

## The view of the ships flown beside the local one (#1354, PRF-8, GFX-2,
## MP-2): one `ShipModel` of the ship look per ship, blended between ticks,
## hidden when the ship is gone, with no light of its own, and holding only the
## copies it is handed.


static func _ship(position: Vector3, facing: Vector3 = Vector3(0, 0, -1)) -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.position = position
	ship.orientation = Basis.looking_at(facing, Vector3.UP)
	return ship


func test_each_ship_gets_a_model_at_its_pose() -> String:
	var view: OtherShipsView = OtherShipsView.new()
	var ships: Array[ShipState] = [_ship(Vector3(1, 2, 3)), _ship(Vector3(-4, 0, 6), Vector3(1, 0, 0)),
		_ship(Vector3(0, 5, 0))]
	view.show_ships(ships, ships, 0.0)
	var problem: String = ""
	var models: Array[ShipModel] = view.models()
	if models.size() != 3 or view.shown() != 3 or view.name != OtherShipsView.NODE_NAME:
		problem = "%d models, %d shown" % [models.size(), view.shown()]
	for index: int in models.size():
		if problem == "" and (not models[index].transform.origin.is_equal_approx(ships[index].position)
				or not models[index].transform.basis.is_equal_approx(ships[index].orientation)):
			problem = "model %d is at %s, its ship at %s" % [index, models[index].transform.origin, ships[index].position]
	view.show_ships(ships, ships, 0.0)
	if problem == "" and view.get_child_count() != 3:
		problem = "showing again added models: %d children" % view.get_child_count()
	view.free()
	return problem


func test_a_ship_is_blended_between_ticks() -> String:
	var view: OtherShipsView = OtherShipsView.new()
	var before: Array[ShipState] = [_ship(Vector3(0, 0, 0), Vector3(0, 0, -1))]
	var after: Array[ShipState] = [_ship(Vector3(2, 0, 0), Vector3(1, 0, 0))]
	view.show_ships(before, after, 0.5)
	var drawn: Transform3D = view.models()[0].transform
	var problem: String = ""
	if not drawn.origin.is_equal_approx(Vector3(1, 0, 0)):
		problem = "half way is drawn at %s" % drawn.origin
	var ahead: Vector3 = -drawn.basis.z
	if problem == "" and not ahead.is_equal_approx(Vector3(1, 0, -1).normalized()):
		problem = "half way faces %s" % ahead
	view.free()
	return problem


func test_a_destroyed_or_escaped_ship_and_a_missing_one_are_hidden() -> String:
	var view: OtherShipsView = OtherShipsView.new()
	var ships: Array[ShipState] = [_ship(Vector3.ZERO), _ship(Vector3.ONE), _ship(Vector3(2, 2, 2))]
	view.show_ships(ships, ships, 0.0)
	ships[0].hull = 0.0
	ships[1].escaped = true
	view.show_ships(ships, ships, 0.0)
	var problem: String = ""
	if view.shown() != 1 or not view.models()[2].visible:
		problem = "%d shown after one was destroyed and one escaped" % view.shown()
	var fewer: Array[ShipState] = [_ship(Vector3.ZERO)]
	view.show_ships(fewer, fewer, 0.0)
	if problem == "" and (view.shown() != 1 or view.models()[1].visible or view.models()[2].visible):
		problem = "models beyond the ships handed are still shown"
	view.free()
	return problem


func test_the_engine_follows_speed_and_afterburner() -> String:
	var ship: ShipState = _ship(Vector3.ZERO)
	if OtherShipsView.thrust_of(ship) != 0.0:
		return "a ship at rest glows at %s" % OtherShipsView.thrust_of(ship)
	ship.velocity = Vector3(0, 0, -ship.max_speed * 0.5)
	if not is_equal_approx(OtherShipsView.thrust_of(ship), 0.5):
		return "half speed glows at %s" % OtherShipsView.thrust_of(ship)
	ship.afterburner_active = true
	if OtherShipsView.thrust_of(ship) != 1.0:
		return "the afterburner glows at %s" % OtherShipsView.thrust_of(ship)
	return ""


func test_the_view_adds_no_light_and_reads_only_copies() -> String:
	var source: String = FileAccess.get_file_as_string("res://view/other_ships_view.gd")
	for forbidden: String in ["Light3D", "LocalSession", "Sim", ".sim"]:
		if source.contains(forbidden + " ") or source.contains(forbidden + ".") or source.contains(forbidden + ")"):
			return "the view names %s" % forbidden
	var view: OtherShipsView = OtherShipsView.new()
	var ships: Array[ShipState] = [_ship(Vector3.ZERO)]
	view.show_ships(ships, ships, 0.0)
	var lights: Array[Node] = view.find_children("*", "Light3D", true, false)
	view.free()
	return "" if lights.is_empty() else "%d lights under the view" % lights.size()
