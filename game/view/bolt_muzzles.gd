class_name BoltMuzzles
extends RefCounted

## Where a ship's bolts are drawn from (#602, CMB-1): two muzzles, low left and
## low right ahead of the eye, used in turn. The simulation fires every shot
## from the ship's centre, which is where the pilot's eye sits, so a bolt drawn
## there flies out of the pilot's head. The view instead starts it at a muzzle
## and closes the gap evenly over the first `converge_m` of flight, after
## which the drawn bolt is on the simulated line, where it hits.
##
## View only: the offsets never reach the simulation (MP-2, CMF-6).

## Metres to each side of the eye.
var side_m: float = 0.3
## Metres below the eye.
var drop_m: float = 0.25
## Metres ahead of the eye.
var forward_m: float = 0.6
## Metres of flight over which a bolt closes onto the simulated line.
var converge_m: float = 4.0

## The muzzle each ship fires its next bolt from: 0 left, 1 right; by ship.
var _next: Dictionary[int, int] = {}


## Takes the muzzle keys of a parsed `ProjectileLook`.
func set_look(look: Dictionary) -> void:
	side_m = look["muzzle_side_m"]
	drop_m = look["muzzle_drop_m"]
	forward_m = look["muzzle_forward_m"]
	converge_m = look["converge_m"]


## Muzzle `index` (0 left, 1 right) in the ship's own axes, the eye at the origin
## and forward along -Z.
func point(index: int) -> Vector3:
	var side: float = -side_m if index % 2 == 0 else side_m
	return Vector3(side, -drop_m, -forward_m)


## The muzzle ship `ship` fires from now, in its own axes; the next call for
## that ship gives the other one.
func take(ship: int) -> Vector3:
	var muzzle: int = _next.get(ship, 0)
	_next[ship] = 1 - muzzle
	return point(muzzle)


## How much of its muzzle offset a bolt still carries after flying `flown_m`:
## all of it at the muzzle, falling evenly to none at `converge_m`.
func weight(flown_m: float) -> float:
	return 1.0 - clampf(flown_m / converge_m, 0.0, 1.0)
