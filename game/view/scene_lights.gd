class_name SceneLights
extends Node3D

## Fixed dynamic lights a level's scene file places in the room (#1288,
## PRF-8, GFX-4): the stress scene's eight. Each is an `OmniLight3D` without
## shadows, since only the headlight casts shadows (GFX-4). They hang under the
## level's drawing, so a new level or the tunnel, which rebuild or free that
## drawing, take them away too.
##
## Positions, colours, ranges and energies come from the data file, read by
## the caller (ARC-4); this only draws them and never touches the simulation.

const NODE_NAME: String = "SceneLights"


## Puts `lights` (each {"position": Vector3, "color": Color, "range": float,
## "energy": float}) under `parent`, replacing any put there before. Returns
## the node, or null when `lights` is empty or there is no parent.
static func place(parent: Node3D, lights: Array[Dictionary]) -> SceneLights:
	if parent == null:
		return null
	var old: Node = parent.get_node_or_null(NODE_NAME)
	if old != null:
		parent.remove_child(old)
		old.free()
	if lights.is_empty():
		return null
	var node: SceneLights = SceneLights.new()
	node.name = NODE_NAME
	for light: Dictionary in lights:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.position = light["position"]
		lamp.light_color = light["color"]
		lamp.omni_range = light["range"]
		lamp.light_energy = light["energy"]
		lamp.shadow_enabled = false
		node.add_child(lamp)
	parent.add_child(node)
	return node


## How many lights are drawn under `parent`.
static func count(parent: Node) -> int:
	var node: Node = parent.get_node_or_null(NODE_NAME) if parent != null else null
	return node.get_child_count() if node != null else 0
