class_name HandLayer
extends RefCounted

## Puts the pilot's hands on `HubRoom.HANDS_LAYER_BIT` as well as the layers
## they already have (#1451, CRW-2, PLT-5). The home base room's camera draws
## only its own layer and this one, so the controller models show at the base
## while the mine and its fade stay hidden behind the room.
##
## The control labels are left off here: the label set puts itself on this
## layer only while it shows the base's own labels (`ControlLabelSet.set_at_base`,
## #1469), so the flight labels never show at the base. Presentation only: no input, no simulation state,
## no comfort setting is read (ARC-3, MP-2).


## Adds the hands bit to every drawn node under `root` (itself included), except
## inside a `ControlLabelSet`. Returns how many nodes now carry it. Safe to call
## again, as runtime controller models arrive after the shape is built.
static func tag(root: Node) -> int:
	var count: int = 0
	if root == null:
		return count
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is ControlLabelSet:
			continue
		pending.append_array(node.get_children())
		if node is VisualInstance3D and not node is Light3D:
			(node as VisualInstance3D).layers |= HubRoom.HANDS_LAYER_BIT
			count += 1
	return count


## True when every drawn node under `root` outside the labels carries the bit.
static func is_tagged(root: Node) -> bool:
	if root == null:
		return false
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is ControlLabelSet:
			continue
		pending.append_array(node.get_children())
		if node is VisualInstance3D and not node is Light3D \
				and ((node as VisualInstance3D).layers & HubRoom.HANDS_LAYER_BIT) == 0:
			return false
	return true
