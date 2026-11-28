class_name LevelViewBoxes
extends RefCounted

## Sorts the walls, frames and bevels of a level into the boxes whose nodes
## draw them, so each box (room or tunnel) can be shown or hidden on its own
## (`LevelVisibility`, #1364, GFX-3). Kept apart from `LevelView` so the node
## holds only building and culling (#1446).


## The quads each box draws, by box index: `"walls"` holds the box's wall
## quads and the frames sunk into it (`frame_box`), `"bevels"` its edge bevels.
static func split(union: BoxUnion, quads: Array[Dictionary], frames: Array[Dictionary],
		bevels: Array[Dictionary]) -> Dictionary:
	var per_box: Array[Array] = []
	var bevels_per_box: Array[Array] = []
	for index: int in union.boxes.size():
		per_box.append([])
		bevels_per_box.append([])
	for quad: Dictionary in quads:
		per_box[int(quad["box"])].append(quad)
	for quad: Dictionary in frames:
		per_box[frame_box(union, quad)].append(quad)
	for bevel: Dictionary in bevels:
		bevels_per_box[int(bevel["box"])].append(bevel)
	return {"walls": per_box, "bevels": bevels_per_box}


## The box whose node draws frame `quad`: a frame is sunk behind its face, into
## the box that opens there, so it is drawn (and hidden) with that box. The
## lowest such box holding the frame's centre; its own box if none does.
static func frame_box(union: BoxUnion, quad: Dictionary) -> int:
	var centre: Vector3 = ((quad["min"] as Vector3) + (quad["max"] as Vector3)) * 0.5
	for index: int in union.boxes.size():
		if index == int(quad["box"]):
			continue
		var box: BoxBounds = union.boxes[index]
		var grow: Vector3 = Vector3.ONE * 1e-3
		if _inside(centre, box.min_corner - grow, box.max_corner + grow):
			return index
	return int(quad["box"])


static func _inside(point: Vector3, low: Vector3, high: Vector3) -> bool:
	return point.x >= low.x and point.y >= low.y and point.z >= low.z \
			and point.x <= high.x and point.y <= high.y and point.z <= high.z
