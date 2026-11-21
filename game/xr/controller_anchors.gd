class_name ControllerAnchors
extends RefCounted

## Where each label's leader line ends on the runtime's own controller model
## (issue #652, PLT-5, CMF-1). The leader lines used to end on the generic
## shape's buttons, which do not sit where the real Quest 3 controller's do.
##
## A runtime model that names its parts (a glTF node per button, stick and
## trigger) is measured directly; a component it does not name comes from a
## per-profile offset table in `res://xr/controller_anchors.json` (ARC-4), and
## a profile the table does not know uses `runtime_default_profile`, the
## Quest 3's own controller. The generic shape keeps its own points. Points
## are hand-local on the right hand, like `ControllerModel.CONTROL_POINTS`;
## `ControlLabelSet` mirrors them for the left hand. Physical controls never
## swap, so the left-handed and paired layouts only change which text sits on
## which control, never where a line ends. View only (ARC-3).
##
## `gripped_rest` (#789, optional) says where the gripped scheme's stick and
## throttle models rest beside each hand before it grips them: an offset from
## the controller's origin, right hand, each axis within `GRIPPED_REST_RANGE_M`
## so a typo cannot put a model out of reach. The left hand mirrors it.

const DEFAULT_FILE: String = "res://xr/controller_anchors.json"
## Every component a profile's table must give, and the node names searched for.
const COMPONENTS: Array[String] = ["stick_click", "button_upper", "button_lower", "menu", "trigger", "grip"]
## Label points that share another component's point: a stick's two axes end
## where its click does.
const SHARED_POINTS: Dictionary = {"stick_x": "stick_click", "stick_y": "stick_click"}
const TOP_KEYS: Array[String] = ["runtime_default_profile", "node_names", "profiles"]
const GRIPPED_REST_KEY: String = "gripped_rest"
## The controls `gripped_rest` places, as `GrippedControlsModel.KINDS` names them.
const GRIPPED_REST_CONTROLS: Array[String] = ["stick", "throttle"]
const GRIPPED_REST_RANGE_M: float = 0.25
## A little ahead of and below the hand, where a grip closes round it.
const GRIPPED_REST_DEFAULT: Dictionary = {
	"stick": Vector3(0.0, -0.04, -0.06),
	"throttle": Vector3(0.0, -0.04, -0.06),
}
## Where the points came from, as `ControllerModel.anchor_source` reports it.
const SOURCE_GENERIC: String = "generic"
const SOURCE_TABLE: String = "table"
const SOURCE_NODES: String = "nodes"

## Set when the data was rejected; empty otherwise.
var error: String = ""
## The profile assumed for a runtime model when the runtime names none.
var runtime_default_profile: String = ""
## Component -> node names to look for, in order of preference.
var node_names: Dictionary = {}
## Profile -> (component -> Vector3), right hand.
var profiles: Dictionary = {}
## Control -> its rest offset from the right hand's origin (#789).
var gripped_rest: Dictionary = GRIPPED_REST_DEFAULT.duplicate()
## Hand -> the anchor line last printed.
var _logged: Dictionary = {}


## Parses an anchor data file's text. Every profile must give every component
## in `COMPONENTS` as three numbers; on failure `error` names what is wrong.
static func parse_json(text: String) -> ControllerAnchors:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	return parse_data(json.data)


static func parse_data(data: Dictionary) -> ControllerAnchors:
	for key: Variant in data:
		if not TOP_KEYS.has(str(key)) and str(key) != GRIPPED_REST_KEY:
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in TOP_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var anchors: ControllerAnchors = ControllerAnchors.new()
	anchors.runtime_default_profile = str(data["runtime_default_profile"])
	if typeof(data["node_names"]) != TYPE_DICTIONARY or typeof(data["profiles"]) != TYPE_DICTIONARY:
		return _rejected("\"node_names\" and \"profiles\" must be objects")
	var names: Dictionary = data["node_names"]
	for component: String in COMPONENTS:
		if not names.has(component) or typeof(names[component]) != TYPE_ARRAY:
			return _rejected("node_names is missing component \"%s\"" % component)
		var list: Array[String] = []
		for entry: Variant in names[component]:
			list.append(str(entry).to_lower())
		anchors.node_names[component] = list
	var tables: Dictionary = data["profiles"]
	for profile: Variant in tables:
		if typeof(tables[profile]) != TYPE_DICTIONARY:
			return _rejected("profile \"%s\" must be an object" % str(profile))
		var table: Dictionary = tables[profile]
		var points: Dictionary = {}
		for component: String in COMPONENTS:
			if not table.has(component):
				return _rejected("profile \"%s\" is missing component \"%s\"" % [str(profile), component])
			var value: Variant = table[component]
			if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3 or not _all_numbers(value):
				return _rejected("profile \"%s\" component \"%s\" must be three numbers" % [str(profile), component])
			points[component] = Vector3(float(value[0]), float(value[1]), float(value[2]))
		for component: Variant in table:
			if not COMPONENTS.has(str(component)):
				return _rejected("profile \"%s\" has unknown component \"%s\"" % [str(profile), str(component)])
		anchors.profiles[str(profile)] = points
	if not anchors.profiles.has(anchors.runtime_default_profile):
		return _rejected("runtime_default_profile \"%s\" has no table" % anchors.runtime_default_profile)
	if data.has(GRIPPED_REST_KEY):
		var problem: String = anchors._read_gripped_rest(data[GRIPPED_REST_KEY])
		if problem != "":
			return _rejected(problem)
	return anchors


## Where control `kind` rests beside `hand` ("left" or "right"), in the hand's
## own space: the right hand's offset, mirrored for the left.
func rest_offset(kind: String, hand: String) -> Vector3:
	var offset: Vector3 = gripped_rest.get(kind, Vector3.ZERO)
	return Vector3(-offset.x, offset.y, offset.z) if hand == "left" else offset


static func load_file(path: String = DEFAULT_FILE) -> ControllerAnchors:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var anchors: ControllerAnchors = parse_json(FileAccess.get_file_as_string(path))
	if anchors.error != "":
		anchors.error = "%s: %s" % [path, anchors.error]
	return anchors


## The table of `profile` as label points. The runtime may report no
## profile, or a generic one for a Meta model, so an unknown profile uses
## `runtime_default_profile`. Empty only for rejected data.
func table_points(profile: String) -> Dictionary:
	var key: String = profile if profiles.has(profile) else runtime_default_profile
	if not profiles.has(key):
		return {}
	return with_shared_points(profiles[key])


## The leader points for a runtime model under `root` (null when it is not
## in the tree yet), as {"points": ..., "source": SOURCE_*}: measured parts
## first, then the profile's table, then `generic` for rejected data.
func resolve(root: Node, relative_to: Node3D, hand: String, profile: String, generic: Dictionary) -> Dictionary:
	var table: Dictionary = table_points(profile)
	var fallback: Dictionary = table if not table.is_empty() else generic
	var source: String = SOURCE_TABLE if not table.is_empty() else SOURCE_GENERIC
	if root == null:
		return {"points": fallback, "source": source}
	var found: Dictionary = find_parts(root, relative_to)
	if not found.is_empty():
		source = SOURCE_NODES
	var line: String = "MELTDOWN_LABEL_ANCHORS hand=%s source=%s parts=%s" % [
		hand, source, ",".join(PackedStringArray(found.keys()))]
	# Once per change, for a logcat check on the headset (labels refresh often).
	if _logged.get(hand, "") != line:
		_logged[hand] = line
		print(line)
	return {"points": points_for_model(found, hand, fallback), "source": source}


## Component -> its part's position in `relative_to`'s space, for every
## component `node_names` finds under `model_root`. A part is a node or a
## skeleton bone (skinned glTF models import their parts as bones). Exact
## names win over names that merely contain a candidate.
func find_parts(model_root: Node, relative_to: Node) -> Dictionary:
	var parts: Array = []
	_collect(model_root, relative_to, parts)
	var found: Dictionary = {}
	for component: String in COMPONENTS:
		var part: Array = _pick(parts, node_names.get(component, []))
		if not part.is_empty():
			found[component] = part[1]
	return found


## Label points for one hand's runtime model from its measured `parts`
## (as `find_parts` gives them); the other components come from `fallback`.
## `hand` undoes the left hand's mirror.
static func points_for_model(parts: Dictionary, hand: String, fallback: Dictionary) -> Dictionary:
	var points: Dictionary = {}
	for component: String in COMPONENTS:
		if fallback.has(component):
			points[component] = fallback[component]
	for component: String in parts:
		var local: Vector3 = parts[component]
		points[component] = Vector3(-local.x, local.y, local.z) if hand == "left" else local
	return with_shared_points(points)


## The interaction profile the runtime reports for `hand`, or "".
static func tracker_profile(hand: String) -> String:
	var tracker: XRPositionalTracker = XRServer.get_tracker(&"left_hand" if hand == "left" else &"right_hand") as XRPositionalTracker
	return tracker.profile if tracker != null else ""


## `node`'s origin in `ancestor`'s space, walking the parents so it works
## outside the scene tree too.
static func local_position(node: Node3D, ancestor: Node) -> Vector3:
	return local_transform(node, ancestor).origin


static func local_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var xform: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		var spatial: Node3D = current as Node3D
		if spatial != null:
			xform = spatial.transform * xform
		current = current.get_parent()
	return xform


static func with_shared_points(points: Dictionary) -> Dictionary:
	var result: Dictionary = points.duplicate()
	for shared: String in SHARED_POINTS:
		if result.has(SHARED_POINTS[shared]):
			result[shared] = result[SHARED_POINTS[shared]]
	return result


## The first [lower-case name, position] in `parts` matching `candidates`.
static func _pick(parts: Array, candidates: Array) -> Array:
	for candidate: Variant in candidates:
		for part: Array in parts:
			if str(part[0]) == str(candidate):
				return part
	for candidate: Variant in candidates:
		for part: Array in parts:
			if str(part[0]).contains(str(candidate)):
				return part
	return []


static func _collect(node: Node, relative_to: Node, into: Array) -> void:
	for child: Node in node.get_children():
		var spatial: Node3D = child as Node3D
		if spatial != null:
			var xform: Transform3D = local_transform(spatial, relative_to)
			into.append([String(spatial.name).to_lower(), xform.origin])
			var skeleton: Skeleton3D = spatial as Skeleton3D
			if skeleton != null:
				for bone: int in skeleton.get_bone_count():
					var pose: Vector3 = skeleton.get_bone_global_pose(bone).origin
					into.append([skeleton.get_bone_name(bone).to_lower(), xform * pose])
		_collect(child, relative_to, into)


func _read_gripped_rest(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"%s\" must be an object" % GRIPPED_REST_KEY
	var table: Dictionary = value
	for control: Variant in table:
		if not GRIPPED_REST_CONTROLS.has(str(control)):
			return "%s has unknown control \"%s\"" % [GRIPPED_REST_KEY, str(control)]
	for control: String in GRIPPED_REST_CONTROLS:
		var point: Variant = table.get(control)
		if typeof(point) != TYPE_ARRAY or (point as Array).size() != 3 or not _all_numbers(point):
			return "%s \"%s\" must be three numbers" % [GRIPPED_REST_KEY, control]
		for axis: Variant in point:
			if absf(float(axis)) > GRIPPED_REST_RANGE_M:
				return "%s \"%s\" is more than %.2f m from the hand" % [
					GRIPPED_REST_KEY, control, GRIPPED_REST_RANGE_M]
		gripped_rest[control] = Vector3(float(point[0]), float(point[1]), float(point[2]))
	return ""


static func _all_numbers(values: Array) -> bool:
	for value: Variant in values:
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return false
	return true


static func _rejected(message: String) -> ControllerAnchors:
	var anchors: ControllerAnchors = ControllerAnchors.new()
	anchors.error = message
	return anchors
