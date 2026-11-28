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
##
## Each hand's labels fade out after the hand has stayed away from the centre
## of view for a while and fade back in when it comes near (#147, `LabelFade`).
##
## The ship's headlight hangs under the rig origin (#609, `Headlight`). It is
## fixed to the ship, not the head, so it sits where the cockpit frame sits:
## at the recentred head point, which is the ship's centre with the ship's
## axes. The main scene places the frame there every frame before the rig
## runs, so the rig only copies that placement.
##
## The rig also carries the `RenderScaler` (#1417), which lowers and raises
## the headset's render scale with the frame times, and the `AimRay` (#1451),
## shown from the aiming hand's controller (`AimHand`, #1470) where pointing selects. The controller
## shapes are on the hands layer too, so the home base room draws them.
##
## Where pointing selects (the home base's stations and the shaft choice) the
## labels name what acts there instead (`BaseLabels`, #1469), drawn on the hands
## layer and above the shaft choice's fade; in flight the flight labels return.

const LEFT_COLOR: Color = Color(0.2, 0.6, 1.0)
const RIGHT_COLOR: Color = Color(1.0, 0.5, 0.2)
const MODEL_NAME: String = "Controller"
## Logs what the runtime offers for controller models (#145).
const REPORT_NAME: String = "RenderModelReport"
const CAMERA_NAME: String = "Camera"
## The authored eye height, used for the headlight before any cockpit frame
## exists (a rig built on its own, as the tests do).
const DEFAULT_EYE_HEIGHT_M: float = 1.6

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

## True while the slot control should say how to pick a part up (#606,
## `PickupHint`); the scene that owns the session sets it each frame.
var pickup_hint: bool = false:
	set(value):
		if value != pickup_hint:
			pickup_hint = value
			refresh_labels()

## What the labels were last built from, so a remap made in place on the
## layout dictionary is noticed too.
var _shown_signature: int = 0
## Hand -> its `LabelFade`; each hand fades on its own.
var _fades: Dictionary = {}
## What the labels say at the home base and the shaft choice (#1469). A
## refused file leaves no labels there, never the flight ones.
var base_labels: BaseLabels = _load_base_labels()
var _base_shown: bool = false


func _ready() -> void:
	build()


func _process(delta: float) -> void:
	if _signature() != _shown_signature or pointing_selects() != _base_shown:
		refresh_labels()
	place_headlight()
	point_ray()
	var camera: Node3D = get_node_or_null(CAMERA_NAME) as Node3D
	if camera == null or not is_inside_tree():
		return
	var hands: Dictionary = {}
	for model: ControllerModel in _models():
		hands[model.hand] = model.global_position
	fade_labels(delta, camera.global_transform, hands)


## Advances each hand's label fade by `delta` seconds. `view` is the eye's
## global transform and `hand_positions` maps `"left"`/`"right"` to the global
## position of that hand. Public so the tests can fly without a headset.
func fade_labels(delta: float, view: Transform3D, hand_positions: Dictionary) -> void:
	for model: ControllerModel in _models():
		if not hand_positions.has(model.hand):
			continue
		var fade: LabelFade = _fade_for(model.hand)
		var angle: float = LabelFade.angle_off_view(view, hand_positions[model.hand])
		model.set_label_alpha(fade.advance(delta, angle))


## Adds the controller shapes to both hands and labels them. Safe to call
## again; also usable outside the tree, which the tests rely on.
func build() -> void:
	_add_model(get_node_or_null("LeftHand") as Node3D, "left", LEFT_COLOR)
	_add_model(get_node_or_null("RightHand") as Node3D, "right", RIGHT_COLOR)
	if get_node_or_null(REPORT_NAME) == null:
		var report: RenderModelReport = RenderModelReport.new()
		report.name = REPORT_NAME
		add_child(report)
	if headlight() == null:
		add_child(Headlight.new())
	if aim_ray() == null:
		add_child(AimRay.new())  # Shown only where pointing selects (#1451).
	if get_node_or_null(RenderScaler.NODE_NAME) == null:
		add_child(RenderScaler.new())  # Dynamic resolution, headset only (#1417).
	place_headlight()
	refresh_labels()


## The ship's headlight, or null before `build`.
func headlight() -> Headlight:
	return get_node_or_null(Headlight.NODE_NAME) as Headlight


## The ship's centre and axes in the rig's space: the cockpit frame's
## placement when the rig has one, otherwise the authored eye point facing -Z.
func ship_frame() -> Transform3D:
	for child: Node in get_children():
		if child is CockpitFrame:
			return (child as CockpitFrame).transform
	return Transform3D(Basis.IDENTITY, Vector3(0.0, DEFAULT_EYE_HEIGHT_M, 0.0))


## Puts the headlight on the ship for this frame. View only: reads the frame
## the main scene placed, writes nothing but the light's own transform.
func place_headlight() -> void:
	var lamp: Headlight = headlight()
	if lamp != null:
		lamp.place(ship_frame())


## The aim ray, or null before `build`.
func aim_ray() -> AimRay:
	return get_node_or_null(AimRay.NODE_NAME) as AimRay


## Draws the aim ray from the right controller, the one the hub and the shaft
## choice select with, while it is tracked and pointing selects or the dev menu
## is open (#1451, #1508); in flight it hides.
func point_ray() -> void:
	var ray: AimRay = aim_ray()
	if ray != null:
		var held: Dictionary = AimHand.pose_on(self)  # The left controller in left-handed mode (#1470).
		ray.follow(self, held["aim"], bool(held["tracked"]))


## The node that logs the runtime's render models, or null before `build`.
func render_model_report() -> RenderModelReport:
	return get_node_or_null(REPORT_NAME) as RenderModelReport


## Rebuilds both hands' labels from the mapping as it is now: the flight
## labels, or `base_labels` while pointing selects (#1469).
func refresh_labels() -> void:
	_shown_signature = _signature()
	_base_shown = pointing_selects()
	var labels: Dictionary = {}
	if _base_shown:
		labels = base_labels.for_hand_mode(mapping != null and mapping.left_handed)
	elif mapping != null:
		labels = ControlLabels.for_mapping(mapping, pickup_hint)
	for model: ControllerModel in _models():
		model.set_labels(ControlLabels.for_hand(labels, model.hand))
		model.set_labels_at_base(_base_shown)


## True where pointing selects: the home base's stations or the shaft choice
## are shown, as the aim ray finds them (`AimTargets`). The open dev menu
## shows the ray too (#1508) but leaves the labels as they are.
func pointing_selects() -> bool:
	var ray: AimRay = aim_ray()
	return ray != null and ray.targets.selects(self)


## True while the labels shown are the base's, not flight's.
func base_labels_shown() -> bool:
	return _base_shown


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


func _fade_for(hand: String) -> LabelFade:
	if not _fades.has(hand):
		var fade: LabelFade = LabelFade.load_file()
		if fade.error != "":
			push_warning("label fade uses defaults: %s" % fade.error)
		_fades[hand] = fade
	return _fades[hand]


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


static func _load_base_labels() -> BaseLabels:
	var loaded: BaseLabels = BaseLabels.load_file()
	if loaded.error != "":
		push_warning("no control labels at the base: %s" % loaded.error)
	return loaded
