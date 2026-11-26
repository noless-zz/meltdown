extends RefCounted

## The mark a taken component heap leaves (#1375, CRF-1, CMF-3, ARC-4, MP-2):
## fed `COMPONENT_COLLECTED` copies, it starts where the heap lay in the kind's
## colour, only ever dims, is gone within its fade, keeps clear of the eye, and
## its look is data held within comfort limits.

const PICKUP: String = "res://data/components/pickup.json"


func _collected(ship: int, kind: String, at: Vector3) -> SimEvent:
	var event: SimEvent = SimEvent.new(SimEvent.Kind.COMPONENT_COLLECTED, ship, 1.0, at)
	event.component = kind
	return event


func _view_with_heap(at: Vector3, kind: String = "cell_salts") -> ComponentView:
	var sim: Sim = Sim.new(1, 1)
	sim.set_component_rules(ComponentPickup.parse_json(FileAccess.get_file_as_string(PICKUP)))
	sim.components.append(ComponentItem.new(kind, 1, at))
	var view: ComponentView = ComponentView.new()
	view.show_heaps(sim)
	return view


func test_the_shipped_look_loads_within_the_comfort_limits() -> String:
	var marks: PickupMarks = PickupMarks.new()
	var look: Dictionary = marks.look()
	var heap_energy: float = float(ComponentView.parse_look(
		FileAccess.get_file_as_string(ComponentView.DEFAULT_LOOK_FILE))["energy"])
	var problem: String = ""
	if marks.look_error != "":
		problem = marks.look_error
	elif float(look["fade_seconds"]) > 1.0:
		problem = "it fades over %s s, more than 1 s" % look["fade_seconds"]
	elif maxf(look["start_size"], look["end_size"]) > 1.5:
		problem = "it grows to %s m" % look["end_size"]
	elif float(look["peak_energy"]) > heap_energy:
		problem = "it glows at %s, brighter than the heap's %s" % [look["peak_energy"], heap_energy]
	elif float(look["peak_alpha"]) >= 1.0:
		problem = "it starts opaque"
	marks.free()
	return problem


func test_a_look_past_a_comfort_limit_or_with_a_bad_key_is_refused() -> String:
	var good: Dictionary = PickupMarks.FALLBACK_LOOK.duplicate()
	if PickupMarks.parse_look(JSON.stringify(good)).has("error"):
		return "the fallback look is refused: %s" % PickupMarks.parse_look(JSON.stringify(good))
	var cases: Dictionary = {"fade_seconds": 1.5, "end_size": 3.0, "peak_energy": 8.0, "peak_alpha": 1.0, "max_marks": 2.5}
	for key: String in cases:
		var bad: Dictionary = good.duplicate()
		bad[key] = cases[key]
		if not String(PickupMarks.parse_look(JSON.stringify(bad)).get("error", "")).contains(key):
			return "%s %s was accepted" % [key, cases[key]]
	var extra: Dictionary = good.duplicate()
	extra["flash"] = true
	if not String(PickupMarks.parse_look(JSON.stringify(extra)).get("error", "")).contains("flash"):
		return "an unknown key was accepted"
	var missing: Dictionary = good.duplicate()
	missing.erase("eye_clearance_m")
	if not String(PickupMarks.parse_look(JSON.stringify(missing)).get("error", "")).contains("eye_clearance_m"):
		return "a missing key was accepted"
	return ""


func test_a_heap_the_local_ship_takes_leaves_a_mark_where_it_lay_in_its_colour() -> String:
	var at: Vector3 = Vector3(2, 1, -6)
	var view: ComponentView = _view_with_heap(at)
	var event: SimEvent = _collected(0, "cell_salts", at)
	var before: String = str(event)
	view.feed([event] as Array[SimEvent])
	view.show_heaps(Sim.new(1, 1), 0.0, Vector3(0, 0, 0))
	var marks: PickupMarks = view.marks
	var problem: String = ""
	if marks.shown_count() != 1 or marks.started_count != 1:
		problem = "%d marks drawn, %d started" % [marks.shown_count(), marks.started_count]
	elif not marks.node(0).position.is_equal_approx(at):
		problem = "the mark is at %s, the heap was at %s" % [marks.node(0).position, at]
	elif (marks.node(0).material_override as StandardMaterial3D).emission != view.color_for("cell_salts"):
		problem = "the mark is not in the kind's colour"
	elif marks.largest_offset_m > 0.001:
		problem = "recorded %.3f m from the heap" % marks.largest_offset_m
	elif str(event) != before:
		problem = "the event changed"
	view.free()
	return problem


func test_another_ships_pickup_and_other_events_leave_no_mark() -> String:
	var view: ComponentView = _view_with_heap(Vector3.ZERO)
	var events: Array[SimEvent] = [_collected(1, "cell_salts", Vector3.ZERO),
		SimEvent.new(SimEvent.Kind.SALVAGE_COLLECTED, 0, 1.0, Vector3.ZERO),
		SimEvent.new(SimEvent.Kind.MINER_RESCUED, 0, 0.0, Vector3.ZERO)]
	view.feed(events)
	view.show_heaps(Sim.new(1, 1), 0.0)
	var started: int = view.marks.started_count
	view.free()
	return "" if started == 0 else "%d marks started" % started


func test_a_mark_only_dims_and_is_gone_within_its_fade() -> String:
	var marks: PickupMarks = PickupMarks.new()
	var fade: float = marks.look()["fade_seconds"]
	marks.start(Vector3.ZERO, Color(0.4, 0.8, 0.8))
	var last_alpha: float = INF
	var last_energy: float = INF
	var last_size: float = 0.0
	var frames: int = 0
	marks.advance(0.0)
	while marks.shown_count() > 0 and frames < 600:
		var material: StandardMaterial3D = marks.node(0).material_override as StandardMaterial3D
		if material.albedo_color.a > last_alpha or material.emission_energy_multiplier > last_energy:
			marks.free()
			return "frame %d brightened" % frames
		if marks.node(0).scale.x < last_size:
			marks.free()
			return "frame %d shrank" % frames
		last_alpha = material.albedo_color.a
		last_energy = material.emission_energy_multiplier
		last_size = marks.node(0).scale.x
		marks.advance(1.0 / 72.0)
		frames += 1
	var problem: String = ""
	if frames == 0:
		problem = "the mark was never drawn"
	elif float(frames) / 72.0 > fade + 1.0 / 72.0:
		problem = "drawn for %d frames, longer than %.2f s" % [frames, fade]
	elif marks.longest_drawn_seconds >= fade or marks.drawn_count != 1:
		problem = "longest %.3f s, drawn %d" % [marks.longest_drawn_seconds, marks.drawn_count]
	marks.free()
	return problem


func test_the_mark_is_hidden_while_the_eye_is_inside_or_beside_it() -> String:
	var marks: PickupMarks = PickupMarks.new()
	marks.start(Vector3(0, 0, -5), Color.WHITE)
	marks.advance(0.0, Vector3(0, 0, -5))
	var inside: bool = marks.shown_count() == 0
	marks.advance(0.0, Vector3(0, 0, -5.4))
	var beside: bool = marks.shown_count() == 0
	marks.advance(0.0, Vector3(0, 0, -1))
	var away: bool = marks.shown_count() == 1
	var culled: bool = (marks.node(0).material_override as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK
	marks.free()
	if not (inside and beside and away and culled):
		return "hidden inside %s, beside %s; drawn away %s; back faces culled %s" % [inside, beside, away, culled]
	return ""


func test_marks_are_pooled_up_to_the_look_s_count() -> String:
	var marks: PickupMarks = PickupMarks.new()
	var most: int = marks.look()["max_marks"]
	for index: int in most + 3:
		marks.start(Vector3(index, 0, 0), Color.WHITE)
		marks.advance(0.01)
	var count: int = marks.node_count()
	marks.advance(1.0)
	marks.start(Vector3.ZERO, Color.WHITE)
	var reused: int = marks.node_count()
	marks.free()
	if count != most or reused != most:
		return "%d nodes for %d marks, then %d" % [count, most + 3, reused]
	return ""
