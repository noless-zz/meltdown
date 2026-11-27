extends RefCounted

## The pilot's hands at the home base (#1451, CRW-2, PLT-5, ARC-3): both
## controller shapes, left-handed too, are on the hands layer the room's camera
## draws, their flight labels are not; the room's camera draws the room and the
## hands but not the mine; hiding the room gives the camera back its mask; and a
## runtime model that arrives later is put on the layer as well.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"


func _rig() -> Node:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	rig.call("build")
	return rig


func test_both_controllers_are_on_the_hands_layer_in_either_hand_mode() -> String:
	var problem: String = ""
	for left_handed: bool in [false, true]:
		var rig: Node = _rig()
		var mapping: ThumbstickMapping = ThumbstickMapping.new()
		mapping.left_handed = left_handed
		rig.set("mapping", mapping)
		for hand: String in ["left", "right"]:
			var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
			if model == null or not HandLayer.is_tagged(model):
				problem = "the %s controller is not on the hands layer (left-handed %s)" % [hand, left_handed]
			elif (model.get_node("Handle") as VisualInstance3D).layers & 1 == 0:
				problem = "the %s controller left the mine's layer" % hand
		rig.free()
		if problem != "":
			break
	return problem


func test_the_flight_labels_stay_off_the_hands_layer() -> String:
	var rig: Node = _rig()
	var labels: ControlLabelSet = (rig.call("model_for", "right") as ControllerModel).label_set()
	var problem: String = ""
	var pending: Array[Node] = [labels]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is VisualInstance3D and ((node as VisualInstance3D).layers & HubRoom.HANDS_LAYER_BIT) != 0:
			problem = "label part %s is drawn at the base" % node.name
	rig.free()
	return problem


func test_a_runtime_model_arriving_later_joins_the_hands_layer() -> String:
	var model: ControllerModel = ControllerModel.new("right")
	model.build()
	var arrived: MeshInstance3D = MeshInstance3D.new()
	arrived.mesh = BoxMesh.new()
	model.runtime_models().add_child(arrived)
	model.on_runtime_model_added(arrived)
	model.tag_hands()  # The deferred call, made now: no frame runs here.
	var problem: String = "" if (arrived.layers & HubRoom.HANDS_LAYER_BIT) != 0 else "the runtime model is not drawn at the base"
	model.free()
	return problem


func test_the_room_camera_draws_the_room_and_the_hands_but_not_the_mine() -> String:
	var room: HubRoom = HubRoom.new()
	var camera: Camera3D = Camera3D.new()
	camera.cull_mask = 0xFFFFF
	var problem: String = ""
	if not room.show_for(camera):
		problem = "the room did not show"
	elif camera.cull_mask & 1 != 0:
		problem = "the room's camera still draws the mine's layer"
	elif camera.cull_mask & HubRoom.HANDS_LAYER_BIT == 0 or not room.shows_hands() or not room.hides_mine():
		problem = "the room's camera does not draw the hands (mask %d)" % camera.cull_mask
	room.hide_room()
	if problem == "" and camera.cull_mask != 0xFFFFF:
		problem = "hiding the room left mask %d" % camera.cull_mask
	if HubRoom.HANDS_LAYER_BIT == HubRoom.LAYER_BIT:
		problem = "the hands share the room's layer, so the room's lights would light them"
	room.free()
	camera.free()
	return problem
