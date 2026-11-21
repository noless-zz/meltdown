extends RefCounted

## Component heaps drawn in the level (CRF-1, #1034, MP-2, ARC-4): one glowing
## node per heap in the sim's list, coloured by kind from data, with a fallback
## for an unknown kind, and nothing while drops are off.

const PICKUP: String = "res://data/components/pickup.json"


func _sim() -> Sim:
	var sim: Sim = Sim.new(1, 1)
	sim.set_component_rules(ComponentPickup.parse_json(FileAccess.get_file_as_string(PICKUP)))
	return sim


func _emission(view: ComponentView, index: int) -> Color:
	return (view.node(index).material_override as StandardMaterial3D).emission


func _hashes(sim: Sim) -> Array[int]:
	var out: Array[int] = []
	for heap: ComponentItem in sim.components:
		out.append(heap.state_hash())
	return out


func test_two_heaps_of_two_kinds_draw_in_their_colours() -> String:
	var sim: Sim = _sim()
	if sim.component_rules == null:
		return "the shipped pickup rules did not load"
	sim.components.append(ComponentItem.new("cell_salts", 2, Vector3(1, 0, -5)))
	sim.components.append(ComponentItem.new("core_glass", 1, Vector3(-2, 1, -9)))
	var before: Array[int] = _hashes(sim)
	var view: ComponentView = ComponentView.new()
	view.show_heaps(sim)
	var problem: String = ""
	if view.shown_count() != 2:
		problem = "%d heaps drawn" % view.shown_count()
	elif _emission(view, 0) != view.color_for("cell_salts") or _emission(view, 1) != view.color_for("core_glass"):
		problem = "colours %s, %s" % [_emission(view, 0), _emission(view, 1)]
	elif view.color_for("cell_salts") == view.color_for("core_glass"):
		problem = "two kinds share a colour"
	elif not view.node(1).position.is_equal_approx(Vector3(-2, 1, -9)):
		problem = "second heap drawn at %s" % view.node(1).position
	elif _hashes(sim) != before:
		problem = "drawing changed the heaps"
	view.free()
	return problem


func test_a_collected_heap_leaves_with_the_sims_list() -> String:
	var sim: Sim = _sim()
	sim.components.append(ComponentItem.new("cell_salts", 2, Vector3(0, 0, -5)))
	sim.components.append(ComponentItem.new("scrap_alloy", 1, Vector3(0, 0, -9)))
	var view: ComponentView = ComponentView.new()
	view.show_heaps(sim)
	sim.components.remove_at(0)
	view.show_heaps(sim)
	var problem: String = ""
	if view.shown_count() != 1 or _emission(view, 0) != view.color_for("scrap_alloy"):
		problem = "after collecting one: %d drawn" % view.shown_count()
	view.free()
	return problem


func test_a_sim_without_rules_draws_nothing() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.components.append(ComponentItem.new("cell_salts", 1, Vector3.ZERO))
	var view: ComponentView = ComponentView.new()
	view.show_heaps(sim)
	var count: int = view.node_count()
	view.free()
	return "" if count == 0 else "%d nodes with drops off" % count


func test_an_unknown_kind_uses_the_fallback_colour() -> String:
	var sim: Sim = _sim()
	sim.components.append(ComponentItem.new("not_a_kind", 1, Vector3.ZERO))
	var view: ComponentView = ComponentView.new()
	view.show_heaps(sim)
	var fallback: Color = ComponentView.parse_look(FileAccess.get_file_as_string(ComponentView.DEFAULT_LOOK_FILE))["fallback"]
	var drawn: Color = _emission(view, 0)
	view.free()
	return "" if drawn == fallback else "unknown kind drawn %s, fallback %s" % [drawn, fallback]


func test_the_shipped_look_covers_every_kind() -> String:
	var view: ComponentView = ComponentView.new()
	var problem: String = view.look_error
	var listed: Array[String] = view.looked_kinds()
	view.free()
	if problem != "":
		return problem
	for file: String in DirAccess.get_files_at(ComponentList.COMPONENTS_DIR):
		if file.ends_with(".json") and file != ComponentList.RULES_FILE and not listed.has(file.get_basename()):
			return "no colour for kind %s" % file.get_basename()
	return ""


func test_a_bad_key_is_named() -> String:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ComponentView.DEFAULT_LOOK_FILE))
	var bad: Dictionary = {
		"shape": ["hexagon", 3], "size": [0.0, "1", true], "energy": [-1, 11],
		"fallback": [[1, 1], [2, 0, 0], "white"], "kinds": [[], {"cell_salts": [1, 1]}],
	}
	for key: String in bad:
		for value: Variant in bad[key]:
			var data: Dictionary = good.duplicate(true)
			data[key] = value
			var parsed: Dictionary = ComponentView.parse_look(JSON.stringify(data))
			if not parsed.has("error") or not String(parsed["error"]).contains(key):
				return "%s = %s: %s" % [key, JSON.stringify(value), parsed]
	var extra: Dictionary = good.duplicate(true)
	extra["glow"] = 1
	if not String(ComponentView.parse_look(JSON.stringify(extra)).get("error", "")).contains("glow"):
		return "an unknown key was accepted"
	var missing: Dictionary = good.duplicate(true)
	missing.erase("kinds")
	return "" if String(ComponentView.parse_look(JSON.stringify(missing)).get("error", "")).contains("kinds") else "a missing key was accepted"
