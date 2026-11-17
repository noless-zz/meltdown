class_name MeltdownWiring
extends RefCounted

## Joins the level's reactor and the run's outcome to what the main scene shows
## (RUN-2, RUN-5, LGT-1, #359): the reactor view in the level, the meltdown
## countdown and the outcome row on the status panel.
##
## It sits beside `main.gd`, like `CombatWiring` and `MapWiring`, because it
## reads the `net/` session, which `view/` and `xr/` may not depend on. The
## reactor reaches the view as a `SessionSnapshots.reactor` copy and the outcome
## through the read-only `Sim.outcome`, so nothing here writes simulation state
## (MP-2). The panel rows never move or animate (CMF-3).

## The reactor, under the world node while the session has one, null otherwise.
var reactor_view: ReactorView = null

## The node whose space is the simulation's; set by `attach`.
var _world: Node3D = null


## Remembers `world`, the node whose space is the simulation's, and shows
## `session`'s reactor there at once, so no frame goes without it. A session
## without a reactor (the test tunnel) gets no view.
func attach(world: Node3D, session: LocalSession) -> void:
	_world = world
	update(session, null)


## Once per frame, after the ticks: places the reactor view from a copy of the
## session's reactor, and hands `panel`, if given, the countdown (hidden unless
## the reactor is destroyed) and the outcome (hidden while running).
func update(session: LocalSession, panel: StatusPanel) -> void:
	if session == null:
		return
	var reactor: ReactorState = SessionSnapshots.reactor(session.sim.reactor)
	_follow(reactor)
	if panel != null:
		panel.show_meltdown(seconds_left(reactor) if reactor != null and reactor.destroyed else -1.0)
		panel.show_outcome(session.sim.outcome())


## Seconds of meltdown left on `reactor`, a session copy: its ticks at 60 a second.
static func seconds_left(reactor: ReactorState) -> float:
	return float(reactor.meltdown_ticks_left) / float(ReactorState.TICKS_PER_SECOND)


## The hull `reactor`, a session copy, has left as a fraction of its start;
## a start of zero reads as none left.
static func hull_fraction(reactor: ReactorState) -> float:
	return reactor.hull / reactor.max_hull if reactor.max_hull > 0.0 else 0.0


## Creates, moves or removes the view so it matches `reactor`, a copy or null.
func _follow(reactor: ReactorState) -> void:
	if reactor == null:
		if reactor_view != null:
			reactor_view.get_parent().remove_child(reactor_view)
			reactor_view.queue_free()
			reactor_view = null
		return
	if reactor_view == null:
		if _world == null:
			return
		reactor_view = ReactorView.new()
		_world.add_child(reactor_view)
	reactor_view.show_state(reactor.position(), reactor.radius(), hull_fraction(reactor),
		reactor.destroyed, seconds_left(reactor))
