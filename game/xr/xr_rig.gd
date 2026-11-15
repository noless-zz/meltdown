extends XROrigin3D

## Player rig: tracked head camera and two tracked controllers.
##
## Without an XR session the camera keeps its authored height and works as an
## ordinary flat camera. Each hand shows a simple controller shape with a
## label beside every bound control (PLT-5, CMF-4); left is blue and right is
## orange so tracking mix-ups are obvious in the headset. Where the runtime
## supplies its own controller model, that replaces the shape (#93).
##
## The labels are read from `mapping`, the thumbstick mapping that flies the
## ship, and are rebuilt whenever its layout, hand or pitch setting changes.
## The rig only reads the mapping; it never writes input or ship state (ARC-3).

const LEFT_COLOR: Color = Color(0.2, 0.6, 1.0)
const RIGHT_COLOR: Color = Color(1.0, 0.5, 0.2)
const MODEL_NAME: String = "Controller"
## Logs what the runtime offers for controller models (#145).
const REPORT_NAME: String = "RenderModelReport"

## The mapping whose bindings the labels show. The scene that owns the real
## mapping assigns it here; until then the default layout is shown.
var mapping: ThumbstickMapping = ThumbstickMapping.new():
	set(value):
		mapping = value
		refresh_labels()
## On by default until onboarding exists; one switch for both hands.
var show_labels: bool = true:
	set(value):
		show_labels = value
		for model: ControllerModel in _models():
			model.show_labels = value

## What the labels were last built from, so a remap made in place on the
## layout dictionary is noticed too.
var _shown_signature: int = 0


func _ready() -> void:
	build()


func _process(_delta: float) -> void:
	if _signature() != _shown_signature:
		refresh_labels()


## Adds the controller shapes to both hands and labels them. Safe to call
## again; also usable outside the tree, which the tests rely on.
func build() -> void:
	_add_model(get_node_or_null("LeftHand") as Node3D, "left", LEFT_COLOR)
	_add_model(get_node_or_null("RightHand") as Node3D, "right", RIGHT_COLOR)
	if get_node_or_null(REPORT_NAME) == null:
		var report: RenderModelReport = RenderModelReport.new()
		report.name = REPORT_NAME
		add_child(report)
	refresh_labels()


## The node that logs the runtime's render models, or null before `build`.
func render_model_report() -> RenderModelReport:
	return get_node_or_null(REPORT_NAME) as RenderModelReport


## Rebuilds both hands' labels from the mapping as it is now.
func refresh_labels() -> void:
	_shown_signature = _signature()
	var labels: Dictionary = ControlLabels.for_mapping(mapping) if mapping != null else {}
	var left: ControllerModel = model_for("left")
	var right: ControllerModel = model_for("right")
	if left != null:
		left.set_labels(ControlLabels.for_hand(labels, "left"))
	if right != null:
		right.set_labels(ControlLabels.for_hand(labels, "right"))


## The controller shape on `hand` (`"left"` or `"right"`), or null before `build`.
func model_for(hand: String) -> ControllerModel:
	var node_name: String = "LeftHand" if hand == "left" else "RightHand"
	return get_node_or_null(NodePath(node_name + "/" + MODEL_NAME)) as ControllerModel


func _add_model(hand_node: Node3D, hand: String, color: Color) -> void:
	if hand_node == null:
		return
	var model: ControllerModel = hand_node.get_node_or_null(MODEL_NAME) as ControllerModel
	if model == null:
		model = ControllerModel.new(hand, color)
		model.name = MODEL_NAME
		hand_node.add_child(model)
	model.show_labels = show_labels
	var controller: XRController3D = hand_node as XRController3D
	if controller != null:
		model.pose_name = controller.pose
	model.build()


func _models() -> Array[ControllerModel]:
	var models: Array[ControllerModel] = []
	for hand: String in ["left", "right"]:
		var model: ControllerModel = model_for(hand)
		if model != null:
			models.append(model)
	return models


## Dictionary hashes follow content, so this is cheap enough to check every frame.
func _signature() -> int:
	if mapping == null:
		return 0
	return hash([mapping.layout, mapping.left_handed, mapping.invert_pitch])
