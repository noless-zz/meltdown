class_name DriftWiring
extends RefCounted

## Feeds preset 4's inertia drift (CMF-1, #840) from the ship the view shows.
## Kept beside `comfort_wiring.gd`, which is at its size limit: that file only
## asks this one for the frame's offset and joins it to the hit shake's, which
## `main.gd` puts on top of the ship's pose where it places the rig.
##
## It keeps copies of the ship's velocity and orientation and never writes
## `ShipState` or `Sim` (ARC-3, MP-2), so a replay flown with it ends on the
## same state hash (CMF-6).

## The drift, or null when its data file was rejected: the drift stays off.
var drift: InertiaDrift = load_drift(InertiaDrift.DEFAULT_FILE)

## The ship's velocity and orientation as last shown, copied by `see`.
var _velocity: Vector3 = Vector3.ZERO
var _orientation: Basis = Basis.IDENTITY


## Reads the drift file at `path`. A rejected file is printed once, here, and
## gives null, so no drift shows rather than one with guessed values.
static func load_drift(path: String) -> InertiaDrift:
	var loaded: InertiaDrift = InertiaDrift.load_file(path)
	if loaded.error != "":
		print("Meltdown: inertia drift off: %s" % loaded.error)
		return null
	return loaded


## Takes copies of `ship`'s velocity and orientation. Called once a frame
## where the rig is placed (`RigViews.place_guarded`), so the next frame's
## drift follows the ship as it was last shown: one frame behind the
## simulation, which a lag effect does not notice.
func see(ship: ShipState) -> void:
	if ship != null:
		_velocity = ship.velocity
		_orientation = ship.orientation


## The drift's offset after `delta` seconds under `preset`; the identity
## without a drift file or on a preset without `inertia_drift`.
func advance(preset: ComfortPreset, delta: float) -> Transform3D:
	if drift == null:
		return Transform3D.IDENTITY
	return drift.advance(preset, _velocity, _orientation, delta)
