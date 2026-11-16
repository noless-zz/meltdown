extends RefCounted

## The bolt lights (LGT-1, PRF-1, CMB-1): only the bolts nearest the viewer are
## lit, the choice is deterministic, the lights are pooled within their budget,
## a budget of 0 turns them off, and they cast no shadows.

const LOOK_PATH: String = "user://test_projectile_lights_look.json"

## Ten bolts on the X axis, listed out of order so a bolt's index is not its
## distance rank: index i sits at x = ORDER[i].
const ORDER: Array[int] = [7, 2, 9, 0, 5, 3, 8, 1, 6, 4]


func _shots_at(xs: Array[int]) -> Array[Projectile]:
	var shots: Array[Projectile] = []
	for x: int in xs:
		shots.append(Projectile.new(Vector3(x, 0.0, 0.0), Vector3(0.0, 0.0, -60.0), 0, 30, 10.0))
	return shots


## Bolt indices whose x is in `xs`, in index order.
func _indices_at(xs: Array[int]) -> Array[int]:
	var indices: Array[int] = []
	for index: int in ORDER.size():
		if xs.has(ORDER[index]):
			indices.append(index)
	return indices


func _sorted(values: Array[int]) -> Array[int]:
	var copy: Array[int] = values.duplicate()
	copy.sort()
	return copy


func _light_nodes(view: ProjectileView) -> int:
	var count: int = 0
	for child: Node in view.get_children():
		if child is Light3D:
			count += 1
	return count


func _visible_lights(view: ProjectileView) -> int:
	var count: int = 0
	for index: int in view.light_count():
		if view.light(index).visible:
			count += 1
	return count


func _load_budget(view: ProjectileView, budget: int) -> String:
	var look: Dictionary = {
		"bolt_length_m": 0.6, "bolt_radius_m": 0.03, "emission_color": [0.2, 0.6, 1.0],
		"max_lights": budget, "light_range": 9.0, "light_energy": 2.5,
	}
	var file: FileAccess = FileAccess.open(LOOK_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(look))
	file.close()
	return view.load_look(LOOK_PATH)


func test_the_four_nearest_of_ten_are_lit() -> String:
	var view: ProjectileView = ProjectileView.new()
	view.max_lights = 4
	view.set_viewer(Vector3(3.2, 1.0, 0.0))
	view.show_projectiles(_shots_at(ORDER), 1.0)
	var lit: Array[int] = view.lit_bolts()
	var expected: Array[int] = _indices_at([3, 4, 2, 5])
	var result: String = ""
	if _sorted(lit) != expected:
		result = "lit bolts %s, expected %s" % [lit, expected]
	elif lit[0] != ORDER.find(3):
		result = "the nearest bolt is not listed first: %s" % [lit]
	if result == "" and _visible_lights(view) != 4:
		result = "%d lights are visible" % _visible_lights(view)
	if result == "":
		for slot: int in 4:
			if not view.light(slot).position.is_equal_approx(view.bolt(lit[slot]).position):
				result = "light %d is not on bolt %d" % [slot, lit[slot]]
	view.free()
	return result


func test_moving_the_viewer_moves_the_lights() -> String:
	var view: ProjectileView = ProjectileView.new()
	view.max_lights = 4
	var shots: Array[Projectile] = _shots_at(ORDER)
	view.set_viewer(Vector3(-5.0, 0.0, 0.0))
	view.show_projectiles(shots, 1.0)
	var near_start: Array[int] = _sorted(view.lit_bolts())
	view.set_viewer(Vector3(20.0, 0.0, 0.0))
	view.show_projectiles(shots, 1.0)
	var near_end: Array[int] = _sorted(view.lit_bolts())
	view.free()
	if near_start != _indices_at([0, 1, 2, 3]):
		return "viewer at x=-5 lit %s" % [near_start]
	if near_end != _indices_at([6, 7, 8, 9]):
		return "viewer at x=20 lit %s" % [near_end]
	return ""


## Equal distances keep the order of the projectile list.
func test_ties_follow_the_projectile_order() -> String:
	var view: ProjectileView = ProjectileView.new()
	view.max_lights = 2
	var shots: Array[Projectile] = _shots_at([-1, 1, -1, 1, 0, 0, 0])
	view.set_viewer(Vector3(0.0, 3.0, 0.0))
	view.show_projectiles(shots, 1.0)
	var first: Array[int] = view.lit_bolts()
	view.show_projectiles(shots, 1.0)
	var second: Array[int] = view.lit_bolts()
	view.free()
	var expected: Array[int] = [4, 5]
	if first != expected:
		return "three bolts tie nearest; lit %s, expected [4, 5]" % [first]
	if second != first:
		return "the same input lit %s, then %s" % [first, second]
	return ""


func test_lights_stay_within_the_budget_and_are_pooled() -> String:
	var view: ProjectileView = ProjectileView.new()
	view.max_lights = 4
	var result: String = ""
	view.show_projectiles(_shots_at(ORDER), 1.0)
	var ids: Array[int] = []
	for index: int in view.light_count():
		ids.append(view.light(index).get_instance_id())
	if view.light_count() != 4 or _light_nodes(view) != 4:
		result = "10 bolts with a budget of 4 made %d lights" % _light_nodes(view)
	view.set_viewer(Vector3(9.0, 0.0, 0.0))
	view.show_projectiles(_shots_at(ORDER), 1.0)
	var again: Array[int] = []
	for index: int in view.light_count():
		again.append(view.light(index).get_instance_id())
	if result == "" and again != ids:
		result = "light nodes were replaced while 4 bolts stayed lit"
	view.show_projectiles(_shots_at([1, 2]), 1.0)
	if result == "" and (_light_nodes(view) != 4 or _visible_lights(view) != 2):
		result = "2 bolts left %d light nodes, %d visible" % [_light_nodes(view), _visible_lights(view)]
	view.show_projectiles([] as Array[Projectile], 1.0)
	if result == "" and (_visible_lights(view) != 0 or not view.lit_bolts().is_empty()):
		result = "no bolts still left a light on"
	if result == "" and _load_budget(view, 2) != "":
		result = "a budget of 2 was rejected: %s" % view.look_error
	if result == "" and _light_nodes(view) != 2:
		result = "a budget of 2 left %d light nodes" % _light_nodes(view)
	view.show_projectiles(_shots_at(ORDER), 1.0)
	if result == "" and (_light_nodes(view) != 2 or view.lit_bolts().size() != 2):
		result = "a budget of 2 lit %d bolts with %d nodes" % [view.lit_bolts().size(), _light_nodes(view)]
	view.free()
	return result


func test_a_budget_of_zero_turns_the_lights_off() -> String:
	var view: ProjectileView = ProjectileView.new()
	view.show_projectiles(_shots_at(ORDER), 1.0)
	var result: String = ""
	if view.light_count() == 0:
		result = "the shipped look lit no bolts; the check is blind"
	if result == "" and _load_budget(view, 0) != "":
		result = "a budget of 0 was rejected: %s" % view.look_error
	view.show_projectiles(_shots_at(ORDER), 1.0)
	if result == "" and (_light_nodes(view) != 0 or not view.lit_bolts().is_empty()):
		result = "a budget of 0 kept %d light nodes" % _light_nodes(view)
	view.free()
	return result


func test_lights_use_the_look_and_cast_no_shadows() -> String:
	var view: ProjectileView = ProjectileView.new()
	view.show_projectiles(_shots_at([0, 1]), 1.0)
	var result: String = _load_budget(view, 3)
	view.show_projectiles(_shots_at([0, 1, 2, 3]), 1.0)
	if result == "" and view.light_count() != 3:
		result = "a budget of 3 made %d lights" % view.light_count()
	for index: int in view.light_count():
		var lamp: OmniLight3D = view.light(index)
		if result != "":
			break
		if lamp.shadow_enabled:
			result = "light %d casts shadows" % index
		elif not is_equal_approx(lamp.omni_range, 9.0) or not is_equal_approx(lamp.light_energy, 2.5):
			result = "light %d has range %s and energy %s" % [index, lamp.omni_range, lamp.light_energy]
		elif not lamp.light_color.is_equal_approx(view.emission_color):
			result = "light %d is %s, not the bolt colour" % [index, lamp.light_color]
	view.free()
	DirAccess.remove_absolute(LOOK_PATH)
	return result


func test_light_budget_must_be_a_whole_number() -> String:
	var look: Dictionary = {
		"bolt_length_m": 0.6, "bolt_radius_m": 0.03, "emission_color": [1.0, 0.5, 0.1],
		"max_lights": 2.5, "light_range": 6.0, "light_energy": 1.5,
	}
	var error: Variant = ProjectileView.parse_look(JSON.stringify(look)).get("error", "")
	if error == "" or not "max_lights" in str(error):
		return "a budget of 2.5 gave error \"%s\"" % error
	look["max_lights"] = 2.0
	var values: Dictionary = ProjectileView.parse_look(JSON.stringify(look))
	if values.has("error") or typeof(values["max_lights"]) != TYPE_INT:
		return "a budget of 2 was not read as a whole number: %s" % values
	return ""
