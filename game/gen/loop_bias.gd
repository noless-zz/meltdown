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
## them if the way between stays clear. `open_axes` is `open_axes(generator)`,
## worked out once while the open list stays the same; empty, it is worked
## out here.
static func facing(generator: MineGenerator, bridges: LoopBridges, choice: PlacementChoice,
		open_axes: PackedInt32Array = PackedInt32Array()) -> int:
	if open_axes.is_empty():
		open_axes = LoopBias.open_axes(generator)
	var found: int = 0
	for index: int in choice.module.connectors.size():
		if index == choice.own:
			continue
		# `MineGenerator.placed_connector`'s position and direction, without
		# building the connector: this runs for every candidate (#919).
		var source: ModuleConnector = choice.module.connectors[index]
		var position: Vector3i = ModuleTurns.apply(choice.turn, source.position_mm) + choice.offset_mm
		var direction: Vector3i = ModuleTurns.apply(choice.turn, ModuleTurns.outward(source))
		var axis: int = 0 if direction.x != 0 else (1 if direction.y != 0 else 2)
		var outward_sign: int = direction[axis]
		for open_index: int in generator.open_connectors.size():
			# Only a connector on the same axis, facing the other way, can
			# face this one; `_faces_from` checks the rest.
			if open_index == choice.open_index or open_axes[2 * open_index] != axis \
					or open_axes[2 * open_index + 1] == outward_sign:
				continue
			if _faces_from(bridges, position, axis, outward_sign, source.size_class,
					generator.open_connectors[open_index]):
				found += 1
				break
	return found


## Each of `generator`'s open connectors' axis and sign, in turn, for `facing`.
static func open_axes(generator: MineGenerator) -> PackedInt32Array:
	var axes: PackedInt32Array = PackedInt32Array()
	for connector: ModuleConnector in generator.open_connectors:
		axes.append(connector.axis())
		axes.append(connector.axis_sign())
	return axes


## True when two open connectors face each other within `bridges`' gap and
## offset limits.
static func faces(bridges: LoopBridges, from: ModuleConnector, to: ModuleConnector) -> bool:
	return _faces_from(bridges, from.position_mm, from.axis(), from.axis_sign(), from.size_class, to)


## `faces` for a connector at `position` facing `outward_sign` along `axis`.
static func _faces_from(bridges: LoopBridges, position: Vector3i, axis: int, outward_sign: int,
		size_class: String, to: ModuleConnector) -> bool:
	if size_class != to.size_class or axis != to.axis() or outward_sign == to.axis_sign():
		return false
	var gap: int = (to.position_mm[axis] - position[axis]) * outward_sign
	if gap < bridges.min_gap_mm or gap > bridges.max_gap_mm:
		return false
	var shift: Vector3i = to.position_mm - position
	shift[axis] = 0
	# Squared in 64-bit ints, so whole millimetres compare exactly.
	var shift_x: int = shift.x
	var shift_y: int = shift.y
	var shift_z: int = shift.z
	return shift_x * shift_x + shift_y * shift_y + shift_z * shift_z \
			<= bridges.max_offset_mm * bridges.max_offset_mm
