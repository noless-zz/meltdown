class_name EscapeEndWiring
extends RefCounted

## Joins an escaped run to its end screen (#751, RUN-3, RUN-7, CMF-8): once the
## session's outcome is `ESCAPED` the view fades dark, `ESCAPED` and the
## meltdown time left show, and after the hold a fresh press of the restart
## button flies the level again. `DestroyedWiring` calls it, so `main.gd`'s
## one `if destroyed.update(...): restart_level()` covers both ends of a run.
##
## The timing is the destroyed ship's own `DestroyedSequence`, fed "no hull
## left" while the run is escaped: the same fade, hold, release-then-press and
## fade back in, with the times from `escape_screen.json`. It sits beside
## `main.gd` because it reads the `net/` session; it reads the outcome and a
## copy of the reactor only, and the restart is answered to `main.gd` (MP-2).

var look: Dictionary = EscapeScreenLook.load_file()
var sequence: DestroyedSequence = DestroyedSequence.new(EscapeScreenLook.times(look))
## Under the rig origin once `attach` has run, null before.
var screen: EscapeScreen = null
## Set by `RunWiring` while the level flown is a run's last (#989): the line
## then says the run is won.
var run_won: bool = false


## Hangs the screen under `rig`. Calling it again adds nothing.
func attach(rig: Node3D) -> void:
	if screen != null or rig == null:
		return
	screen = EscapeScreen.new(look)
	rig.add_child(screen)


## Once per frame after the ticks, with the screen's place `head_point`.
## Holds still while the session is paused. Returns true on the frame the
## level should restart.
func update(session: LocalSession, delta_seconds: float, restart_held: bool, head_point: Transform3D,
		xr_running: bool) -> bool:
	var escaped: bool = session.sim.outcome() == ExitRule.Outcome.ESCAPED
	var due: bool = sequence.update(0.0 if escaped else 1.0, 0.0 if session.paused else delta_seconds,
		restart_held)
	if screen != null:
		screen.transform = head_point
		screen.set_line(look["run_won_text"] if run_won else look["line_text"])
		screen.show_state(sequence.line_shown(), sequence.prompt_shown(), seconds_left(session), xr_running)
	return due


## The meltdown time `session`'s reactor holds, in seconds; 0 without a reactor.
static func seconds_left(session: LocalSession) -> float:
	var reactor: ReactorState = SessionSnapshots.reactor(session.sim.reactor)
	return MeltdownWiring.seconds_left(reactor) if reactor != null else 0.0


## The fade's opacity this frame from the sequence, 0..1.
func fade_alpha() -> float:
	return sequence.fade_alpha()


## Back to flying with the end screen down and no fade (#917); see `DestroyedWiring.reset`.
func reset() -> void:
	sequence = DestroyedSequence.new(EscapeScreenLook.times(look))
	if screen != null:
		screen.visible = false
