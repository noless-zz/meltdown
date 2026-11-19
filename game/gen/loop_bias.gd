class_name LoopBias
extends RefCounted

## Placement biased towards loops (#438, GEN-5): `LoopBridges` can only close a
## loop between open connectors that face each other, and with plain random
## placement few do (#411). With `loop_bias` above 0, for that share of the
## modules the generator draws up to `CANDIDATES` placements that fit and keeps
## the first that leaves one of the new module's open connectors facing an
## open connector already placed: same size class, outward axes opposite,
## pointing at each other within `loop_min_m`..`loop_max_m` along the axis and
## at most `loop_max_offset_m` apart across it. If none does, it keeps the
## first that fit.
##
## Every comparison is in whole millimetres and the share is drawn from the
## level's seeded generator against thousandths (GEN-2, ARC-2). With
## `loop_bias` 0 nothing extra is drawn, so levels are exactly as before.

## `loop_bias` 1 in `LoopBridges.loop_bias_permille`.
const SCALE: int = 1000
## Placements that fit drawn per biased choice, at most.
const CANDIDATES: int = 16


## How many of `choice`'s new open connectors face an open connector of
## `generator` other than the one `choice` joins, as `bridges` would bridge
## them if the way between stays clear.
static func facing(generator: MineGenerator, bridges: LoopBridges, choice: PlacementChoice) -> int:
	var found: int = 0
	for index: int in choice.module.connectors.size():
		if index == choice.own:
			continue
		var fresh: ModuleConnector = MineGenerator.placed_connector(choice.module, index,
				choice.turn, choice.offset_mm)
		for open_index: int in generator.open_connectors.size():
			if open_index != choice.open_index \
					and faces(bridges, fresh, generator.open_connectors[open_index]):
				found += 1
				break
	return found


## True when two open connectors face each other within `bridges`' gap and
## offset limits.
static func faces(bridges: LoopBridges, from: ModuleConnector, to: ModuleConnector) -> bool:
	if from.size_class != to.size_class or from.axis() != to.axis() or from.axis_sign() == to.axis_sign():
		return false
	var axis: int = from.axis()
	var gap: int = (to.position_mm[axis] - from.position_mm[axis]) * from.axis_sign()
	if gap < bridges.min_gap_mm or gap > bridges.max_gap_mm:
		return false
	var shift: Vector3i = to.position_mm - from.position_mm
	shift[axis] = 0
	# Squared in 64-bit ints, so whole millimetres compare exactly.
	var shift_x: int = shift.x
	var shift_y: int = shift.y
	var shift_z: int = shift.z
	return shift_x * shift_x + shift_y * shift_y + shift_z * shift_z \
			<= bridges.max_offset_mm * bridges.max_offset_mm
