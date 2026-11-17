class_name PlacementChoice
extends RefCounted

## One way `MineGenerator` could attach the next module (#438): the module,
## its turn and offset in whole millimetres, which open connector it joins and
## by which of its own connectors, and the doorway box. Kept so the generator
## can draw several that fit and keep the one `LoopBias` prefers.

var module: ModuleDef = null
var turn: int = 0
var offset_mm: Vector3i = Vector3i.ZERO
## Index into the generator's open connectors of the one joined.
var open_index: int = -1
## Index into the module's connectors of the one joined.
var own: int = -1
## The doorway box's corners [min, max].
var door: Array[Vector3i] = []
