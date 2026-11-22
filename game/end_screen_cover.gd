class_name EndScreenCover
extends RefCounted

## Hides the status panel and the held map while an end screen is up (#1228,
## RUN-3, CMF-8), so the end screen's line is the only text in the rig: the
## panel's own outcome row also reads `ESCAPED`, and the panel and the map sat
## over the end screen. Both come back as they were once the screen closes.
## The dev menu hides the panel the same way, through its `visible` (#1206).
##
## View only (ARC-3): it touches the two nodes' `visible` and nothing else.
## `DestroyedWiring` drives it; the nodes are found by name under the rig, so
## the panel and map code need not know about the end screens.

## Under the rig origin once `attach` has run, null before.
var rig: Node3D = null

## The nodes hidden here and whether each was visible when first hidden; the
## same index in both. Looked up once when covering starts.
var _hidden: Array = []
var _was_visible: Array[bool] = []


func attach(at: Node3D) -> void:
	rig = at


## Once per frame: hides the panel and the map while `covering`, and puts back
## what it hid once `covering` ends. Hiding runs every frame, because the dev
## menu shows the panel again each frame it is closed.
func update(covering: bool) -> void:
	if not covering:
		restore()
		return
	if _hidden.is_empty():
		for node: Node3D in nodes():
			_hidden.append(node)
			_was_visible.append(node.visible)
	for item: Variant in _hidden:
		# A rebuilt panel leaves a freed node here, which a typed variable may not hold.
		if is_instance_valid(item) and (item as Node3D).visible:
			(item as Node3D).visible = false


## Puts back what `update` hid, each node as it was. The map is closed by its
## own wiring on the new level that follows a restart (#914).
func restore() -> void:
	for i: int in _hidden.size():
		var item: Variant = _hidden[i]
		if is_instance_valid(item) and (item as Node3D).visible != _was_visible[i]:
			(item as Node3D).visible = _was_visible[i]
	_hidden.clear()
	_was_visible.clear()


## True while `update` holds something hidden.
func covering() -> bool:
	return not _hidden.is_empty()


## The status panel and the map hologram under the rig, those that exist.
func nodes() -> Array[Node3D]:
	var found: Array[Node3D] = []
	if rig == null:
		return found
	var panel: Node3D = rig.get_node_or_null(StatusPanel.NODE_NAME) as Node3D
	if panel != null:
		found.append(panel)
	# The map hangs in whichever hand clicks `show_map`, so it is looked up by name.
	var map: Node3D = rig.find_child(MapHologram.NODE_NAME, true, false) as Node3D
	if map != null:
		found.append(map)
	return found
