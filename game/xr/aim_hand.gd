class_name AimHand
extends RefCounted

## The controller that points where pointing selects, and its aim pose (#1470,
## CRW-2, PLT-5, ARC-3). It is the right controller, or the left one in
## left-handed mode, read from the rig's `mapping`. The home base's stations
## (`HubWiring`), the shaft choice (`ShaftChoiceWiring`) and the aim ray
## (`XRRig.point_ray`) all ask this one place, so the highlight, the ray and the
## hand it hangs from always agree.
##
## In the flat simulator the controllers report untracked, so tests and
## acceptance checks can script a pose per hand (`script_pose`, DEV-6). A
## scripted pose is ignored while a headset session runs, so a headset never
## reads it. It only reads nodes and the mapping; it writes nothing but the
## scripted pose's metadata on the rig (MP-2).

const LEFT: String = "left"
const RIGHT: String = "right"
const NODE_NAMES: Dictionary[String, String] = {LEFT: "LeftHand", RIGHT: "RightHand"}
## Metadata on the rig holding scripted poses: {hand: Transform3D in the rig's space}.
const SCRIPTED_META: StringName = &"meltdown_scripted_aim"

## The rig whose controllers aim (the XR origin); null before the wiring attaches.
var rig: Node = null


func _init(p_rig: Node = null) -> void:
	rig = p_rig


## `LEFT` in left-handed mode, `RIGHT` otherwise.
func hand() -> String:
	return hand_on(rig)


## {"tracked": true while the aiming hand has a pose, "aim": that pose in the
## rig's space (identity when not tracked)}.
func pose() -> Dictionary:
	return pose_on(rig)


static func hand_on(p_rig: Node) -> String:
	if p_rig == null:
		return RIGHT
	var mapping: ThumbstickMapping = p_rig.get("mapping") as ThumbstickMapping
	return LEFT if mapping != null and mapping.left_handed else RIGHT


## The aiming hand's controller node under `p_rig`, or null.
static func controller_on(p_rig: Node) -> XRController3D:
	if p_rig == null:
		return null
	return p_rig.get_node_or_null(NODE_NAMES[hand_on(p_rig)]) as XRController3D


static func pose_on(p_rig: Node) -> Dictionary:
	var untracked: Dictionary = {"tracked": false, "aim": Transform3D.IDENTITY}
	if p_rig == null:
		return untracked
	var scripted: Variant = scripted_pose(p_rig, hand_on(p_rig))
	if scripted is Transform3D:
		return {"tracked": true, "aim": scripted}
	var controller: XRController3D = controller_on(p_rig)
	if controller == null or not controller.get_is_active():
		return untracked
	return {"tracked": true, "aim": controller.transform}


## Scripts `p_hand`'s aim pose `aim` (in `p_rig`'s space) for tests and
## acceptance checks in the flat simulator.
static func script_pose(p_rig: Node, p_hand: String, aim: Transform3D) -> void:
	var poses: Dictionary = p_rig.get_meta(SCRIPTED_META, {}) as Dictionary
	poses[p_hand] = aim
	p_rig.set_meta(SCRIPTED_META, poses)


## Drops every scripted pose, so the controllers aim again.
static func clear_scripted(p_rig: Node) -> void:
	if p_rig != null and p_rig.has_meta(SCRIPTED_META):
		p_rig.remove_meta(SCRIPTED_META)


## `p_hand`'s scripted pose on `p_rig`, or null: none scripted, or a headset
## session is running.
static func scripted_pose(p_rig: Node, p_hand: String) -> Variant:
	if p_rig == null or not p_rig.has_meta(SCRIPTED_META) or headset_running():
		return null
	return (p_rig.get_meta(SCRIPTED_META) as Dictionary).get(p_hand, null)


## True while an XR interface is initialised, which is a headset session (or
## the XR smoke test's runtime): scripted poses are not read then.
static func headset_running() -> bool:
	var xr: XRInterface = XRServer.primary_interface
	return xr != null and xr.is_initialized()
