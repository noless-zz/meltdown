class_name SlotPopup
extends Node3D

## The slot popup's look (#1263, decision record 0011): three choices just
## above the choosing hand's stick, left "Replace left gun", right "Replace
## right gun", down "Dump", and a cancel hint above them. Wording, sizes,
## distances and colours come from `res://xr/slot_popup.json` (ARC-4); where
## the stick is comes from `res://xr/controller_anchors.json`, the right
## hand's point, mirrored for the left (PLT-5).
##
## It hangs under the hand's controller node, so it moves with the stick, and
## turns to face the eye each frame, so left reads as left whatever the wrist
## does. View only: it shows what `SlotPopupInput` says and writes nothing
## (ARC-3, MP-2).

const ANCHOR_COMPONENT: String = "stick_click"

## The parsed look; `look["error"]` is set when the file was rejected.
var look: Dictionary = SlotPopupLook.load_file()
## The hand it is placed for, "left" or "right".
var hand: String = "right"
var left_label: Label3D = null
var right_label: Label3D = null
var down_label: Label3D = null
var cancel_label: Label3D = null


func _init(p_look: Dictionary = {}) -> void:
	if not p_look.is_empty():
		look = p_look
	name = "SlotPopup"
	visible = false
	var spread: float = float(look["spread_m"])
	left_label = _label("Left", str(look["left_text"]), Vector3(-spread, 0.0, 0.0),
		HORIZONTAL_ALIGNMENT_RIGHT, false)
	right_label = _label("Right", str(look["right_text"]), Vector3(spread, 0.0, 0.0),
		HORIZONTAL_ALIGNMENT_LEFT, false)
	down_label = _label("Down", str(look["down_text"]), Vector3(0.0, -spread, 0.0),
		HORIZONTAL_ALIGNMENT_CENTER, false)
	cancel_label = _label("Cancel", str(look["cancel_text"]), Vector3(0.0, spread, 0.0),
		HORIZONTAL_ALIGNMENT_CENTER, true)


## The error from the look file, or "" when it loaded.
func look_error() -> String:
	return str(look.get("error", ""))


## Where the popup's centre sits in `p_hand`'s controller space: above the
## stick's point in `anchors` by `look`'s height. Rejected anchors leave the
## stick at the controller's origin.
static func place_for(anchors: ControllerAnchors, p_hand: String, p_look: Dictionary) -> Vector3:
	var stick: Vector3 = Vector3.ZERO
	if anchors != null and anchors.error == "":
		stick = anchors.table_points("").get(ANCHOR_COMPONENT, Vector3.ZERO)
	if p_hand == "left":
		stick.x = -stick.x
	return stick + Vector3(0.0, float(p_look["height_m"]), 0.0)


## Moves it to above `p_hand`'s stick, as `place_for` gives.
func place(anchors: ControllerAnchors, p_hand: String) -> void:
	hand = p_hand
	position = place_for(anchors, p_hand, look)


## Shows it while `open`, turned to face `camera` when both are in the tree.
func show_open(open: bool, camera: Node3D) -> void:
	visible = open
	if open and camera != null and is_inside_tree() and camera.is_inside_tree():
		var at: Vector3 = global_position
		global_transform = Transform3D(camera.global_basis.orthonormalized(), at)


func _label(label_name: String, text: String, at: Vector3, align: HorizontalAlignment,
		hint: bool) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.text = text
	label.position = at
	label.pixel_size = float(look["pixel_size"])
	label.font_size = int(look["cancel_font"] if hint else look["choice_font"])
	label.modulate = look["cancel_color"] if hint else look["choice_color"]
	label.horizontal_alignment = align
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# Always readable, even with the hand inside a wall's shadow or a bolt.
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = false
	add_child(label)
	return label
