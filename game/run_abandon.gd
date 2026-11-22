class_name RunAbandon
extends RefCounted

## The one call the menu's "Return to base" row makes once the view is black
## (#1246, RUN-1, RUN-7, CRW-2), and that the `abandon_run` acceptance step
## makes too, so both judge the same path.
##
## The run ends through `RunWiring.abandon`, the run-end path a destroyed ship
## takes, then the new run's first level is loaded behind the dark view and the
## hub opens on it exactly as at a normal start (`StartChoice.open_hub`): the
## ship is held, and the hub's launch fades the view in. Nothing here writes
## simulation state: the session is replaced through `main.gd`'s
## `restart_level` (MP-2, ARC-3). It sits beside `main.gd` because it reads the
## run and the hub.


## Whether `level_start` flies one of its run's levels now: the only time the
## row is shown. Not in the hub, the test tunnel, a single level started from
## the Level entry or the flight test, which fly no run or another source.
static func flying_run(level_start: LevelStart) -> bool:
	if level_start == null or level_start.run == null or not level_start.run.active():
		return false
	return level_start.source == level_start.run.level_source()


## Abandons the run `level_start` flies and opens `hub` on the next one.
## `restart` is `main.gd`'s `restart_level`, called with `moved_on` true since
## the run has already moved on. False, changing nothing, when no run flies.
static func abandon(level_start: LevelStart, hub: HubWiring, destroyed: DestroyedWiring,
		restart: Callable) -> bool:
	if not flying_run(level_start) or not level_start.run.abandon():
		return false
	level_start.source = level_start.run.level_source()
	if restart.is_valid():
		restart.call(true)
	if hub != null and destroyed != null:
		StartChoice.open_hub(hub, level_start, destroyed)
	return true
