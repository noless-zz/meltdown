class_name BotStall
extends RefCounted

## Notices when the bot pilot has stopped getting anywhere (#658). At a corner
## where a robot's line of sight just grazes the ship, the bot used to settle
## into a cycle a tick or two long: in sight, it turned its nose to the robot
## and weaved out of the line of fire (`BotDodge`); out of sight, it turned to
## the route's next opening and flew back into the line. The nose never
## settled within the fire cone, and since #612 robots wind up before they
## fire, so neither side ever shot and the flight ran out its tick limit with
## the ship's shield full. Seeds 1 and 4 of the bot sweep did this for over
## 30,000 ticks each.
##
## The pilot asks `update` each tick it flies a level. Once the ship has stayed
## within `RADIUS` of one point for `TICKS` ticks it counts as stalled until it
## leaves that point; the pilot then stops weaving and waiting for robots and
## flies its route nose first, so it goes through the opening and meets the
## robot (not waiting since #603: seed 5 sat out its waits at one corner).
## `TICKS` is twice the longest the bot waits for robots on purpose (`BotPilot.MAX_WAIT_TICKS`),
## so waiting and sheltering are not mistaken for a stall. Pure arithmetic on
## the ship's position, so the same flight stalls on the same tick (ARC-1).

## How far the ship must move to count as getting somewhere, metres. 2 m until
## #603: after the pulse cannon went to 4 shots/s, seed 6 hung at a corner the
## same way, swinging 2 m either side of a point that drifted about 3 m in 20 s,
## so a 2 m circle restarted every few hundred ticks and never filled.
const RADIUS: float = 5.0
## Ticks within `RADIUS` before the bot counts as stalled (20 s).
const TICKS: int = 1200

var _anchor: Vector3 = Vector3.INF
var _still_ticks: int = 0


## Whether the ship at `position` has stayed within `RADIUS` of one point for
## `TICKS` ticks since it got there.
func update(position: Vector3) -> bool:
	if _anchor == Vector3.INF or position.distance_to(_anchor) > RADIUS:
		_anchor = position
		_still_ticks = 0
	else:
		_still_ticks += 1
	return _still_ticks >= TICKS
