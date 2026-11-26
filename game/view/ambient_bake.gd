class_name AmbientBake
extends RefCounted

## Baked ambient light per box of a mine (#1400, GFX-5): each box gets its own
## ambient from `AmbientRules`, written into its wall vertices when the level is
## built, so rooms differ in mood at no cost per frame and with no light or draw
## call added (GFX-4, PRF-4).
##
## The ambient at a point is one field over the whole mine: a weighted mean of
## the point's own box and the boxes overlapping it, each weighted by how close
## the point is to that box, fading to nothing `blend_m` away. Two vertices at
## the same place in an opening, one on each box's side, so get the same light
## and no seam shows. Boxes that do not touch the point's box are left out:
## rock is between them. The bake reads only the union, the rules and the
## reactor's position, so the same level always bakes the same (ARC-1).
##
## Values are linear colour times energy, as the environment's ambient reaches
## the shader; `level_wall.gdshader` adds albedo times this in place of it.

var blend_m: float = 4.0
var piece_m: float = 2.0
## Ambient of each box, linear, energy applied.
var ambients: Array[Color] = []
## For each box, the boxes that overlap it (the ones it opens into).
var neighbours: Array[PackedInt32Array] = []
var _boxes: Array[BoxBounds] = []


## Linear ambient of `color` at `energy`, as the renderer works out the environment's.
static func linear(color: Color, energy: float) -> Color:
	var lin: Color = color.srgb_to_linear()
	return Color(lin.r * energy, lin.g * energy, lin.b * energy)


## The global ambient of `look` (`ambient_color` at `ambient_energy`), the fallback.
static func global(look: Dictionary) -> Color:
	return linear(look["ambient_color"], float(look["ambient_energy"]))


## A bake of `union` by `rules` (parsed by `AmbientRules`). `reactor` is the
## reactor's position in the union's space, or null for a level without one.
static func make(union: BoxUnion, rules: Dictionary, reactor: Variant) -> AmbientBake:
	var bake: AmbientBake = AmbientBake.new()
	bake.blend_m = float(rules["blend_m"])
	bake.piece_m = float(rules["piece_m"])
	bake._boxes = union.boxes
	var pull: Dictionary = rules["reactor"] if reactor is Vector3 else {}
	for box: BoxBounds in union.boxes:
		bake.ambients.append(box_ambient(rules, box, pull, reactor))
	for index: int in union.boxes.size():
		var touching: PackedInt32Array = PackedInt32Array()
		for other: int in union.boxes.size():
			if other != index and _overlap(union.boxes[index], union.boxes[other]):
				touching.append(other)
		bake.neighbours.append(touching)
	return bake


## The ambient of `box`: its size's, pulled towards `pull`'s (the reactor
## rule, empty for none) the nearer `reactor` is to the box's centre. The
## centre, not the nearest wall: a long tunnel with one end at the reactor room
## should not glow red all along; the blend across its opening carries the red in.
static func box_ambient(rules: Dictionary, box: BoxBounds, pull: Dictionary, reactor: Variant) -> Color:
	var size: Dictionary = AmbientRules.size_for(rules, box.max_corner - box.min_corner)
	var own: Color = linear(size["color"], float(size["energy"]))
	if pull.is_empty() or not reactor is Vector3:
		return own
	var centre: Vector3 = (box.min_corner + box.max_corner) * 0.5
	var near: float = 1.0 - clampf((reactor as Vector3).distance_to(centre) / float(pull["reach_m"]), 0.0, 1.0)
	var hot: Color = linear(pull["color"], float(pull["energy"]))
	return own.lerp(hot, near * float(pull["strength"]))


## Distance from `point` to `box`; 0 inside or on it.
static func distance(point: Vector3, box: BoxBounds) -> float:
	var nearest: Vector3 = point.clamp(box.min_corner, box.max_corner)
	return point.distance_to(nearest)


## The ambient at `point` on a wall of box `own`.
func at(point: Vector3, own: int) -> Color:
	var weight: float = _weight(point, own)
	var sum: Color = ambients[own] * weight
	var total: float = weight
	for other: int in neighbours[own]:
		var other_weight: float = _weight(point, other)
		if other_weight > 0.0:
			sum += ambients[other] * other_weight
			total += other_weight
	if total <= 0.0:
		return ambients[own]
	return sum / total


## `quad` (`LevelFaces` layout) cut into pieces at most `piece_m` across where
## a neighbour with a different ambient lies within `blend_m`, so the blend has
## vertices to show on; whole where nothing blends. Cuts fall at the blend's
## edges as well, so a whole part meets the pieces where the field is flat.
func pieces(quad: Dictionary) -> Array[Dictionary]:
	var own: int = quad["box"]
	var near: Array[BoxBounds] = []
	for other: int in neighbours[own]:
		if not ambients[other].is_equal_approx(ambients[own]) \
				and _rect_distance(quad["min"], quad["max"], _boxes[other]) < blend_m:
			near.append(_boxes[other])
	if near.is_empty():
		var whole: Array[Dictionary] = [quad]
		return whole
	var axis: int = quad["axis"]
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var low: Vector3 = quad["min"]
	var high: Vector3 = quad["max"]
	var us: Array[float] = _cuts(low[u], high[u], near, u)
	var vs: Array[float] = _cuts(low[v], high[v], near, v)
	var result: Array[Dictionary] = []
	for j: int in vs.size() - 1:
		for i: int in us.size() - 1:
			var part_low: Vector3 = low
			var part_high: Vector3 = high
			part_low[u] = us[i]
			part_high[u] = us[i + 1]
			part_low[v] = vs[j]
			part_high[v] = vs[j + 1]
			var blends: bool = false
			for box: BoxBounds in near:
				blends = blends or _rect_distance(part_low, part_high, box) < blend_m
			if blends:
				result.append_array(_split(quad, part_low, part_high, u, v))
			else:
				result.append(LevelFaces.make_quad(own, axis, quad["normal"], part_low, part_high))
	return result


func _weight(point: Vector3, box: int) -> float:
	var reach: float = 1.0 - clampf(distance(point, _boxes[box]) / blend_m, 0.0, 1.0)
	return reach * reach


## Cuts from `low` to `high` on `component`, at each near box's blend edges.
func _cuts(low: float, high: float, near: Array[BoxBounds], component: int) -> Array[float]:
	var raw: Array[float] = [low, high]
	for box: BoxBounds in near:
		for edge: float in [box.min_corner[component] - blend_m, box.max_corner[component] + blend_m]:
			if edge > low and edge < high:
				raw.append(edge)
	return _distinct(raw)


## The part from `low` to `high` of `quad` cut evenly into pieces at most `piece_m` across.
func _split(quad: Dictionary, low: Vector3, high: Vector3, u: int, v: int) -> Array[Dictionary]:
	var count_u: int = maxi(1, ceili((high[u] - low[u]) / piece_m - 1e-4))
	var count_v: int = maxi(1, ceili((high[v] - low[v]) / piece_m - 1e-4))
	var result: Array[Dictionary] = []
	for j: int in count_v:
		for i: int in count_u:
			var piece_low: Vector3 = low
			var piece_high: Vector3 = high
			piece_low[u] = lerpf(low[u], high[u], float(i) / count_u)
			piece_high[u] = lerpf(low[u], high[u], float(i + 1) / count_u)
			piece_low[v] = lerpf(low[v], high[v], float(j) / count_v)
			piece_high[v] = lerpf(low[v], high[v], float(j + 1) / count_v)
			result.append(LevelFaces.make_quad(quad["box"], quad["axis"], quad["normal"], piece_low, piece_high))
	return result


static func _distinct(raw: Array[float]) -> Array[float]:
	raw.sort()
	var result: Array[float] = []
	for value: float in raw:
		if result.is_empty() or value - result[result.size() - 1] > LevelFaces.EPSILON_M:
			result.append(value)
	return result


## Distance between the axis-aligned rectangle (or box) `low`..`high` and `box`.
static func _rect_distance(low: Vector3, high: Vector3, box: BoxBounds) -> float:
	var gap: Vector3 = Vector3.ZERO
	for axis: int in 3:
		gap[axis] = maxf(0.0, maxf(box.min_corner[axis] - high[axis], low[axis] - box.max_corner[axis]))
	return gap.length()


static func _overlap(a: BoxBounds, b: BoxBounds) -> bool:
	for axis: int in 3:
		if a.max_corner[axis] <= b.min_corner[axis] + LevelFaces.EPSILON_M \
				or b.max_corner[axis] <= a.min_corner[axis] + LevelFaces.EPSILON_M:
			return false
	return true


## The bake `look`'s rules give `union`: {"bake": AmbientBake or null, "error":
## String}. No rules means no bake and no error; bad rules name the field and
## also give no bake, so the walls keep the global ambient.
static func for_look(union: BoxUnion, look: Dictionary, reactor: Variant) -> Dictionary:
	if not look.has(AmbientRules.KEY):
		return {"bake": null, "error": ""}
	var rules: Dictionary = AmbientRules.parse(look[AmbientRules.KEY])
	if rules.has("error"):
		return {"bake": null, "error": rules["error"]}
	return {"bake": make(union, rules, reactor), "error": ""}
