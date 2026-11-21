class_name ComponentItem
extends RefCounted

## A heap of one component kind left where a robot was destroyed (CRF-1),
## until a ship flies through it (`ComponentPickup`). Plain data owned by
## `Sim`, like a salvage part, so the server simulates it and the view can draw
## it from the same state (MP-2). Components do not drift yet: `velocity` is
## kept so a later pull, like the salvage one, changes no file format.

## Component kind id: a file in `ComponentList.COMPONENTS_DIR`.
var kind_id: String = ""
## How many of the kind the heap holds, 1..`ComponentDrop.COUNT_MAX`.
var count: int = 1
var position: Vector3 = Vector3.ZERO
## Metres per second; zero for every item dropped so far.
var velocity: Vector3 = Vector3.ZERO


func _init(p_kind_id: String = "", p_count: int = 1, p_position: Vector3 = Vector3.ZERO,
		p_velocity: Vector3 = Vector3.ZERO) -> void:
	kind_id = p_kind_id
	count = p_count
	position = p_position
	velocity = p_velocity


## Tagged fields, so a value moving from one field to another changes the hash.
func state_hash() -> int:
	return hash(["kind", kind_id, "count", count, "position", position, "velocity", velocity])
