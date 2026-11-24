extends RefCounted

## The shipped pickup looks (#1308, GFX-2, SLV-1, SLV-3, CRF-1, ARC-4, LGT-1,
## MP-2): every dropped part, component kind and trapped miner is drawn as a
## model from the shipped data, with a lit body and a glowing core, kinds tell
## apart by shape, nothing adds a light, drawing leaves the sim alone, and a
## look without a model is drawn as before.

const PICKUP: String = "res://data/components/pickup.json"
const TestMinerRescue := preload("res://tests/test_miner_rescue.gd")
## The orange of the reactor's core, which a miner was once taken for (#1208).
const REACTOR_HUE_RANGE: Array[float] = [0.02, 0.12]


static func _pieces(holder: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var model: Node3D = PickupModel.model_of(holder)
	if model != null:
		for child: Node in model.get_children():
			out.append(child as MeshInstance3D)
	return out


## "" when `holder` carries a model with a lit body and a piece in `glow`.
static func _lit_and_glowing(holder: Node3D, glow: Color) -> String:
	var pieces: Array[MeshInstance3D] = _pieces(holder)
	if pieces.is_empty():
		return "no model"
	var bodies: int = 0
	var glows: int = 0
	for piece: MeshInstance3D in pieces:
		var material: StandardMaterial3D = piece.material_override as StandardMaterial3D
		if material.emission_enabled and material.emission.is_equal_approx(glow):
			glows += 1
		elif not material.emission_enabled and material.metallic + (1.0 - material.roughness) > 0.0:
			bodies += 1
	if bodies == 0 or glows == 0:
		return "%d body and %d glowing pieces" % [bodies, glows]
	if not holder.find_children("*", "Light3D", true, false).is_empty():
		return "adds a light (GFX-4)"
	return ""


func test_every_shipped_part_is_drawn_as_its_model() -> String:
	var view: SalvageView = SalvageView.new()
	var items: Array[SalvageItem] = []
	for id: String in view.looked_ids():
		items.append(SalvageItem.new(id, Vector3(items.size() * 3.0, 0.0, 0.0)))
	var before: Array[int] = []
	for item: SalvageItem in items:
		before.append(item.state_hash())
	view.show_salvage(items, items, 1.0)
	var problem: String = view.look_error
	for index: int in items.size():
		var id: String = items[index].part_id
		if problem == "" and view.node(index).mesh != null:
			problem = "part %s still draws its single shape" % id
		if problem == "":
			problem = _lit_and_glowing(view.node(index), view.look_for(id)["emission_color"])
			problem = "" if problem == "" else "part %s: %s" % [id, problem]
	for index: int in items.size():
		if problem == "" and items[index].state_hash() != before[index]:
			problem = "drawing changed part %d" % index
	view.free()
	return problem


func test_a_part_without_a_model_keeps_todays_look() -> String:
	var view: SalvageView = SalvageView.new()
	var items: Array[SalvageItem] = [SalvageItem.new("pulse_cannon", Vector3.ZERO)]
	view.show_salvage(items, items, 1.0)
	var unknown: Array[SalvageItem] = [SalvageItem.new("no_such_part", Vector3.ZERO)]
	view.show_salvage(unknown, unknown, 1.0)
	var problem: String = ""
	if not (view.node(0).mesh is TorusMesh) or PickupModel.model_of(view.node(0)) != null:
		problem = "an unknown part reusing a modelled node is drawn as %s with model %s" % [
			view.node(0).mesh, PickupModel.model_of(view.node(0))]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SalvageView.DEFAULT_LOOK_FILE))
	data["parts"]["pulse_cannon"].erase("model")
	var parsed: Dictionary = SalvageView.parse_look(JSON.stringify(data))
	if problem == "" and (parsed.has("error") or not (parsed["parts"]["pulse_cannon"]["model"] as Dictionary).is_empty()):
		problem = "an entry without a model parsed as %s" % parsed
	view.free()
	return problem


func test_every_component_kind_has_its_own_shape() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.set_component_rules(ComponentPickup.parse_json(FileAccess.get_file_as_string(PICKUP)))
	var view: ComponentView = ComponentView.new()
	var kinds: Array[String] = view.looked_kinds()
	for kind: String in kinds:
		sim.components.append(ComponentItem.new(kind, 1, Vector3(sim.components.size() * 2.0, 0.0, 0.0)))
	view.show_heaps(sim)
	var problem: String = view.look_error
	var shapes: Dictionary[String, String] = {}
	for index: int in kinds.size():
		if problem != "":
			break
		problem = _lit_and_glowing(view.node(index), view.color_for(kinds[index]))
		var outline: PackedStringArray = PackedStringArray()
		for piece: MeshInstance3D in _pieces(view.node(index)):
			outline.append("%s %s" % [piece.mesh.get_class(), piece.transform])
		var key: String = " ".join(outline)
		if problem == "" and shapes.has(key):
			problem = "kinds %s and %s share a shape" % [shapes[key], kinds[index]]
		shapes[key] = kinds[index]
		problem = "" if problem == "" else "kind %s: %s" % [kinds[index], problem]
	view.free()
	return problem


func test_a_kind_without_a_model_keeps_todays_look() -> String:
	var sim: Sim = Sim.new(1, 1)
	sim.set_component_rules(ComponentPickup.parse_json(FileAccess.get_file_as_string(PICKUP)))
	sim.components.append(ComponentItem.new("not_a_kind", 1, Vector3.ZERO))
	var view: ComponentView = ComponentView.new()
	view.show_heaps(sim)
	var problem: String = ""
	if not (view.node(0).mesh is PrismMesh) or PickupModel.model_of(view.node(0)) != null:
		problem = "an unknown kind is drawn as %s" % view.node(0).mesh
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ComponentView.DEFAULT_LOOK_FILE))
	data.erase("models")
	view.free()
	var parsed: Dictionary = ComponentView.parse_look(JSON.stringify(data))
	if problem == "" and (parsed.has("error") or not (parsed["models"] as Dictionary).is_empty()):
		problem = "a look without models parsed as %s" % parsed
	data["models"] = {"cell_salts": {"body": {}}}
	parsed = ComponentView.parse_look(JSON.stringify(data))
	if problem == "" and not String(parsed.get("error", "")).contains("models.cell_salts"):
		problem = "a bad model was not named: %s" % parsed
	return problem


func test_a_trapped_miner_sits_in_a_pod_with_a_lit_window() -> String:
	var sim: Sim = TestMinerRescue.sim_with([Vector3i(0, 0, -1000)] as Array[Vector3i])
	var view: MinerView = MinerView.new()
	view.show_miners(sim.rescue, sim.ships[0])
	var look: Dictionary = MinerView.parse_look(FileAccess.get_file_as_string(MinerView.DEFAULT_LOOK_FILE))
	var problem: String = view.look_error
	if problem == "":
		problem = _lit_and_glowing(view.marker(0), look[MinerPod.KEY]["glow_color"])
	if problem == "" and view.marker(0).get_node_or_null("Beacon") == null:
		problem = "the rescue beacon is gone"
	var window: Color = look[MinerPod.KEY]["glow_color"]
	if problem == "" and window.s > 0.5 and window.h >= REACTOR_HUE_RANGE[0] and window.h <= REACTOR_HUE_RANGE[1]:
		problem = "the window glows orange, like the reactor (#1208)"
	view.free()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MinerView.DEFAULT_LOOK_FILE))
	data.erase("pod")
	var bare: MinerView = MinerView.new()
	var path: String = "user://test_miner_look_no_pod.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	if problem == "" and bare.load_look(path) != "":
		problem = "a look without a pod was rejected: %s" % bare.look_error
	bare.show_miners(sim.rescue, sim.ships[0])
	if problem == "" and PickupModel.model_of(bare.marker(0)) != null:
		problem = "a look without a pod still drew one"
	bare.free()
	DirAccess.remove_absolute(path)
	data["pod"] = {"glow_color": [1, 1, 1], "glow_energy": 99, "model": {}}
	if problem == "" and not String(MinerView.parse_look(JSON.stringify(data)).get("error", "")).contains("pod.glow_energy"):
		problem = "a bad pod was not named"
	return problem


## Draw calls and triangles one copy of each look adds, printed for the pull
## request (#1308 asks for them); fails only if a look costs nothing.
func test_each_look_states_its_cost() -> String:
	var models: PickupModel = PickupModel.new()
	var salvage: Dictionary = SalvageView.parse_look(FileAccess.get_file_as_string(SalvageView.DEFAULT_LOOK_FILE))
	var components: Dictionary = ComponentView.parse_look(FileAccess.get_file_as_string(ComponentView.DEFAULT_LOOK_FILE))
	var miner: Dictionary = MinerView.parse_look(FileAccess.get_file_as_string(MinerView.DEFAULT_LOOK_FILE))
	var looks: Dictionary = {"pod": miner[MinerPod.KEY]["model"]}
	for id: String in salvage["parts"]:
		looks["part " + id] = salvage["parts"][id]["model"]
	for id: String in components["models"]:
		looks["kind " + id] = components["models"][id]
	for name: String in looks:
		var cost: Dictionary = models.cost(looks[name])
		print("pickup cost %s: %d draw calls, %d triangles" % [name, cost["draw_calls"], cost["triangles"]])
		if int(cost["triangles"]) <= 0:
			return "%s costs no triangles" % name
	return ""
