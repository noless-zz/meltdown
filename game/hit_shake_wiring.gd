class_name HitShakeWiring
extends RefCounted

## The hit shake of the active comfort preset (CMF-1, CMF-3, #169) joined to
## preset 4's inertia drift (#840) into one view offset, and the ship pose that
## offset goes on top of. Split out of `comfort_wiring.gd` (#1157), which keeps
## its old names and forwards here.
##
## It reads simulation events and ship states as copies and never writes
## `ShipState` or `Sim` (ARC-3, MP-2), so a replay flown with it ends on the
## same state hash (CMF-6).

## The "Hits" row of the active preset; its `preset` follows `set_preset`.
## Null when the data file was rejected: the shake stays off.
var hit_shake: HitShake = load_hit_shake(HitShake.DEFAULT_FILE)
## The shake's offset for this frame joined to the drift, in the cockpit's
## frame; the identity when nothing shows. `advance` sets it, the rig applies it.
var offset: Transform3D = Transform3D.IDENTITY
var drift: DriftWiring = DriftWiring.new()


## Reads the hit-shake file at `path`; a rejected file is printed once and gives null (no shake).
static func load_hit_shake(path: String) -> HitShake:
	var shake: HitShake = HitShake.load_file(path)
	if shake.error != "":
		print("Meltdown: hit shake off: %s" % shake.error)
		return null
	return shake


## Makes `preset` the one whose "Hits" row the shake follows.
func set_preset(preset: ComfortPreset) -> void:
	if hit_shake != null:
		hit_shake.preset = preset


## Hands the shake the events of the ticks just run for ship `ship` (orientation `ship_basis`, copies).
func feed(events: Array[SimEvent], ship: int, ship_basis: Basis) -> void:
	if hit_shake != null:
		hit_shake.feed(events, ship, ship_basis)


## Moves the shake and the drift (under `preset`) on by one frame of `delta`
## seconds and keeps their offset.
func advance(preset: ComfortPreset, delta: float) -> void:
	var shake: Transform3D = hit_shake.advance(delta) if hit_shake != null else Transform3D.IDENTITY
	offset = drift.advance(preset, delta) * shake


## The ship's pose `fraction` of the way from `previous` to `current`:
## position lerped, rotation slerped. Frames fall between ticks, so showing
## either tick's pose alone would judder at 72 or 90 Hz against a 60 Hz sim.
## With `snapped` (the latest tick was a snap) the rotation is shown at once:
## slerping it would show a snap as smooth rotation (CMF-3).
static func interpolated_pose(previous: ShipState, current: ShipState, fraction: float,
		snapped: bool = false) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	var from_rotation: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to_rotation: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	var rotation: Quaternion = to_rotation if snapped else from_rotation.slerp(to_rotation, weight)
	return Transform3D(Basis(rotation), previous.position.lerp(current.position, weight))
