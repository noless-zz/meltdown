class_name GrippedModels
extends RefCounted

## Shows the gripped scheme's stick and throttle models (#740) in the hands
## (#789, PLT-5, CMF-1), so the pilot sees what each hand holds. Without them
## the scheme reads as "nothing in my hands moves the ship".
##
## Each frame `update` reads the same values and grab points `GrippedSampler`
## (#739) flies from. A held control sits at its grab point, upright in the
## rig's axes (the axes `GrippedStickMapping` reads tilts in), and shows the
## same grab-relative pose the mapping gets. A control not held rests,
## released (centred, dimmed), beside its hand at the hand-local offset in
## `controller_anchors.json` (`gripped_rest`), so it never floats at the
## origin; before a hand has ever been seen it stays hidden. Values without
## poses (the keyboard, or the open dev menu's neutral values) move nothing.
##
## In the thumbstick scheme both are hidden; `set_shown` shows or hides them
## at once when the menu switches scheme (#778). View only: this reads the
## sampler and never writes `ShipInput` or simulation state (MP-2, ARC-3).

const NODE_NAME: String = "GrippedModels"

var stick: GrippedControlsModel = null
var throttle: GrippedControlsModel = null
var anchors: ControllerAnchors

var _root: Node3D = null
## Hand -> its last pose seen in the rig frame.
var _hands: Dictionary = {}


func _init(anchors_path: String = ControllerAnchors.DEFAULT_FILE) -> void:
	anchors = ControllerAnchors.load_file(anchors_path)
	if anchors.error != "":
		push_warning("GrippedModels uses the built-in rest points; %s" % anchors.error)


## Hangs both models under `rig` (the frame the sampled poses are in),
## hidden until `set_shown`. Calling it again adds nothing.
func attach(rig: Node3D, look_path: String = GrippedControlsLook.DEFAULT_FILE) -> void:
	if _root != null:
		return
	_root = Node3D.new()
	_root.name = NODE_NAME
	stick = GrippedControlsModel.new(GrippedControlsModel.STICK, look_path)
	throttle = GrippedControlsModel.new(GrippedControlsModel.THROTTLE, look_path)
	for model: GrippedControlsModel in [stick, throttle]:
		model.visible = false  # Until its hand is seen.
		_root.add_child(model)
	_root.visible = false
	rig.add_child(_root)


func is_shown() -> bool:
	return _root != null and _root.visible


## Shows the models in the gripped scheme, hides them in the other.
func set_shown(shown: bool) -> void:
	if _root != null:
		_root.visible = shown


## One frame: `gripped` says whether the gripped scheme is in use, `sampler`
## holds the grab points the frame's input was flown from, `values` are the
## frame's sampled values, and `left_handed` swaps which hand holds which.
func update(gripped: bool, sampler: GrippedSampler, values: Dictionary, left_handed: bool) -> void:
	set_shown(gripped)
	if _root == null or not values.has(ControllerSampler.POSES):
		return
	var poses: Dictionary = values[ControllerSampler.POSES]
	for hand: String in ControllerSampler.HANDS:
		if poses.has(hand):
			_hands[hand] = poses[hand]
	var stick_hand: String = "left" if left_handed else "right"
	var throttle_hand: String = "right" if left_handed else "left"
	_place(stick, stick_hand, sampler, poses)
	_place(throttle, throttle_hand, sampler, poses)


func _place(model: GrippedControlsModel, hand: String, sampler: GrippedSampler, poses: Dictionary) -> void:
	if sampler.holds(hand) and poses.has(hand):
		model.transform = Transform3D(Basis.IDENTITY, sampler.grab_point(hand).origin)
		model.show_pose(sampler.relative(hand, poses))
		model.visible = true
		return
	model.release()
	model.visible = _hands.has(hand)
	if model.visible:
		var at: Vector3 = (_hands[hand] as Transform3D) * anchors.rest_offset(model.kind, hand)
		model.transform = Transform3D(Basis.IDENTITY, at)
