extends RefCounted

## `OpeningClearance` with box-shaped meltdown entries (#458, RUN-4, MAP-2,
## ARC-1, ARC-2): a solid door or cave-in blocks an opening when a ship can no
## longer pass it, and only then. Its corners are round, as a ship's reach is,
## and it counts less the further it lies along the crossing axis.

## A room (z -10..0) and a corridor (x -4..4, y -2..2, z -30..-8) off it. The
## opening is x -4..4, y -2..2, z -10..-8, crossed along z; with a ship of 1 m
## its centre line may cross anywhere in x -3..3, y -1..1.
const ROOM_MIN: Vector3i = Vector3i(-5000, -5000, -10000)
const ROOM_MAX: Vector3i = Vector3i(5000, 5000, 0)
const CORRIDOR_MIN: Vector3i = Vector3i(-4000, -2000, -30000)
const CORRIDOR_MAX: Vector3i = Vector3i(4000, 2000, -8000)
const SHIP_MM: int = 1000
## Random door layouts checked against a grid search.
const LAYOUTS: int = 300
## Grid step for that search, mm.
const GRID_MM: int = 50


func _blocked(debris_text: String) -> bool:
	var debris: MeltdownDebris = MeltdownDebris.parse_json(debris_text)
	debris.elapsed_ticks = 1
	return OpeningClearance.blocked(ROOM_MIN, ROOM_MAX, CORRIDOR_MIN, CORRIDOR_MAX, debris, SHIP_MM)


## One box entry, solid at once, as JSON.
func _door(centre: Vector3, extent: Vector3) -> String:
	return '{"position": [%s, %s, %s], "size": [%s, %s, %s], "after_seconds": 0.02}' % [
		centre.x, centre.y, centre.z, extent.x, extent.y, extent.z]


func test_a_door_over_the_whole_opening_blocks_it() -> String:
	if OpeningClearance.crossing_axis(ROOM_MIN, ROOM_MAX, CORRIDOR_MIN, CORRIDOR_MAX) != 2:
		return "the opening is not crossed along z, the test proves nothing"
	if not _blocked("[%s]" % _door(Vector3(0, 0, -9), Vector3(8, 4, 0.2))):
		return "a door filling the opening left it open"
	# Its centre alone, as a point, would leave room round it.
	if _blocked('[{"position": [0, 0, -9], "radius": 0.001, "after_seconds": 0.02}]'):
		return "a tiny rock at the door's centre blocked the opening"
	return ""


func test_a_door_over_half_the_opening_leaves_room_beside_it() -> String:
	# Covers x -4..0: the ship's line may pass at x 1..3.
	if _blocked("[%s]" % _door(Vector3(-2, 0, -9), Vector3(4, 4, 0.2))):
		return "half a door blocked the opening"
	# Covers x -4..2.2: the ship would need its line at x 3.2, past 3.
	if not _blocked("[%s]" % _door(Vector3(-0.9, 0, -9), Vector3(6.2, 4, 0.2))):
		return "a door leaving 1.8 m beside it, under a ship's 2 m, left the opening open"
	# Covers x -4..2 exactly: the ship just fits.
	if _blocked("[%s]" % _door(Vector3(-1, 0, -9), Vector3(6, 4, 0.2))):
		return "a door leaving exactly a ship's width blocked the opening"
	return ""


func test_a_door_counts_less_the_further_it_is_along_the_crossing() -> String:
	# Covers x -4..2.2; its near face 0.8 m beyond the opening leaves it 0.6 m of
	# reach, so the line may pass at x 2.8..3.
	if _blocked("[%s]" % _door(Vector3(-0.9, 0, -10.9), Vector3(6.2, 4, 0.2))):
		return "a door 0.8 m beyond the opening still blocked it"
	if not _blocked("[%s]" % _door(Vector3(-0.9, 0, -10.4), Vector3(6.2, 4, 0.2))):
		return "a door 0.3 m beyond the opening left it open"
	# A ship's radius or more away it blocks nothing, however wide.
	if _blocked("[%s]" % _door(Vector3(0, 0, -11.1), Vector3(8, 4, 0.2))):
		return "a door 1 m beyond the opening blocked it"
	return ""


func test_a_door_corner_is_round() -> String:
	# One door covers x -4..0, y -2..0; two more leave the line only x under 0.9
	# and y under 0.85. With square corners nothing is left; round, the line
	# still passes near (0.9, 0.85), more than 1 m from the first door's corner.
	var doors: Array[String] = [_door(Vector3(-2, -1, -9), Vector3(4, 2, 0.2)),
		_door(Vector3(2.95, 0, -9), Vector3(2.1, 4, 0.2)),
		_door(Vector3(0, 1.925, -9), Vector3(8, 0.15, 0.2))]
	if _blocked("[%s]" % ", ".join(doors)):
		return "the corner was taken as square"
	# Moving the first door's corner 0.3 m nearer leaves nothing.
	doors[0] = _door(Vector3(-1.85, -0.85, -9), Vector3(4.3, 2.3, 0.2))
	if not _blocked("[%s]" % ", ".join(doors)):
		return "with the corner nearer the opening was still open"
	return ""


func test_doors_and_rocks_together_block_where_neither_alone_does() -> String:
	var door: String = _door(Vector3(-2, 0, -9), Vector3(4, 4, 0.2))
	var rock: String = '{"position": [2, 0, -9], "radius": 1.5, "after_seconds": 0.02}'
	if _blocked("[%s]" % door) or _blocked("[%s]" % rock):
		return "one of them alone blocked the opening, the test proves nothing"
	if not _blocked("[%s, %s]" % [door, rock]):
		return "the door and the rock together left the opening open"
	return ""


func test_a_door_that_has_not_fallen_or_was_held_blocks_nothing() -> String:
	var debris: MeltdownDebris = MeltdownDebris.parse_json("[%s]" % _door(Vector3(0, 0, -9),
		Vector3(8, 4, 0.2)))
	if OpeningClearance.blocked(ROOM_MIN, ROOM_MAX, CORRIDOR_MIN, CORRIDOR_MAX, debris, SHIP_MM):
		return "a door not yet fallen blocked the opening"
	debris.elapsed_ticks = 1
	debris.skipped[0] = true
	if OpeningClearance.blocked(ROOM_MIN, ROOM_MAX, CORRIDOR_MIN, CORRIDOR_MAX, debris, SHIP_MM):
		return "a held door blocked the opening"
	return ""


## Seeded random doors and rocks: wherever a grid search finds a point at least
## 1 mm clear of everything, the opening must not be called blocked. Enough
## layouts of each kind are checked that both answers are exercised.
func test_random_layouts_agree_with_a_grid_search() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 458
	var checked_open: int = 0
	var checked_blocked: int = 0
	for layout: int in LAYOUTS:
		var debris: MeltdownDebris = MeltdownDebris.new()
		for entry: int in rng.randi_range(1, 4):
			debris.positions_mm.append(Vector3i(rng.randi_range(-4000, 4000),
				rng.randi_range(-2000, 2000), rng.randi_range(-11000, -7000)))
			var box: bool = rng.randf() < 0.75
			debris.radii_mm.append(0 if box else rng.randi_range(300, 2500))
			debris.sizes_mm.append(Vector3i(rng.randi_range(100, 6000), rng.randi_range(100, 4000),
				rng.randi_range(100, 1000)) if box else Vector3i.ZERO)
			debris.after_ticks.append(1)
			debris.skipped.append(false)
		debris.elapsed_ticks = 1
		var blocked: bool = OpeningClearance.blocked(ROOM_MIN, ROOM_MAX, CORRIDOR_MIN,
			CORRIDOR_MAX, debris, SHIP_MM)
		var free_point: Vector2i = _grid_free(debris, 1.0)
		if blocked and free_point.x != _NONE:
			return "layout %d called blocked, but (%d, %d) mm is clear" % [layout, free_point.x,
				free_point.y]
		if blocked:
			checked_blocked += 1
		else:
			checked_open += 1
	if checked_open < 20 or checked_blocked < 20:
		return "only %d open and %d blocked layouts, too few to prove much" % [checked_open,
			checked_blocked]
	return ""


const _NONE: int = -999999


## The first grid point (u, v) of the ship's line clear of every solid entry
## by `margin_mm`, or (_NONE, _NONE).
func _grid_free(debris: MeltdownDebris, margin_mm: float) -> Vector2i:
	for pu: int in range(-3000, 3001, GRID_MM):
		for pv: int in range(-1000, 1001, GRID_MM):
			if _clear(debris, pu, pv, margin_mm):
				return Vector2i(pu, pv)
	return Vector2i(_NONE, _NONE)


## Whether the ship's line at (pu, pv) across z -10..-8 keeps its 1 m reach,
## plus `margin_mm`, from every entry: the nearest distance over the depth.
func _clear(debris: MeltdownDebris, pu: int, pv: int, margin_mm: float) -> bool:
	for index: int in debris.size():
		var at: Vector3i = debris.positions_mm[index]
		var half: Vector3 = Vector3(debris.sizes_mm[index]) * 0.5
		var du: float = maxf(0.0, absf(pu - at.x) - half.x)
		var dv: float = maxf(0.0, absf(pv - at.y) - half.y)
		var dz: float = maxf(0.0, maxf(-10000.0 - (at.z + half.z), (at.z - half.z) + 8000.0))
		var reach: float = float(debris.radii_mm[index] + SHIP_MM) + margin_mm
		if du * du + dv * dv + dz * dz < reach * reach:
			return false
	return true
