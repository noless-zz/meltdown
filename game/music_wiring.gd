class_name MusicWiring
extends RefCounted

## Joins the session to the adaptive music (#1303, AUD-3, RUN-2, RUN-6): each
## frame it reads the mood (hub, flying, meltdown, end screen) and the alarm
## level from session copies and hands them to the `MusicPlayer`.
##
## It sits beside `main.gd`, like `CombatWiring`, which owns it and calls it with
## the sound cues, because it reads the `net/` session, which `view/` may not
## depend on. It only reads: the reactor through `SessionSnapshots.reactor`,
## the alarm through `SessionSnapshots.alarm_level` (#1342) and the outcome
## through `Sim.outcome`, so the simulation hash is the same with the music
## on or off (ARC-1, MP-2).
##
## It also drives the pilot's own engine (#1398, AUD-1), which plays in the
## same moods the run music does and goes quiet with it on end screens and at
## the base; keeping it here leaves `CombatWiring` at its size.

## The music, under the world node once `attach` has run, null before.
var player: MusicPlayer = null
## The pilot's engine, beside the music once `attach` has run, null before.
var engine: EngineSound = null
var _engine_sim: Sim = null


## Puts the music player and the engine under `world`. Calling it again adds nothing.
func attach(world: Node) -> void:
	if player != null:
		return
	player = MusicPlayer.new()
	world.add_child(player)
	engine = EngineSound.new()
	world.add_child(engine)


## Moves the music and the engine `seconds` on for `session`; `hub_open` says
## the home base is up. A new level starts the engine from silence. Returns
## the music layers sounding, empty before `attach`.
func update(session: LocalSession, hub_open: bool, seconds: float) -> Array[String]:
	if player == null or session == null:
		return []
	var now: MusicMix.Mood = mood(session, hub_open)
	if session.sim != _engine_sim:
		engine.reset()
		_engine_sim = session.sim
	follow_engine(engine, session, now, seconds)
	return player.follow(now, alarm_level(session), seconds)


## Moves `engine` `seconds` on with `session`'s local ship in `now`'s mood:
## heard while flying and in the meltdown, faded out otherwise. Reads
## session copies only (MP-2).
static func follow_engine(engine_sound: EngineSound, session: LocalSession, now: MusicMix.Mood,
		seconds: float) -> void:
	if engine_sound == null:
		return
	var flying: bool = now == MusicMix.Mood.RUN or now == MusicMix.Mood.MELTDOWN
	var pose: Transform3D = ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction)
	engine_sound.follow(session.previous_ship(), session.current_ship(), pose, session.frame_events(),
		flying, seconds)


## The mood of `session`: the hub while it is open, the end while an end
## screen is up, the meltdown once the reactor is gone, otherwise a flight.
static func mood(session: LocalSession, hub_open: bool) -> MusicMix.Mood:
	if hub_open:
		return MusicMix.Mood.HUB
	return mood_of(session.sim.outcome(), SessionSnapshots.reactor(session.sim.reactor))


## The mood for `outcome` with `reactor`, a session copy or null (a level with
## no reactor, such as the test tunnel, never melts down).
static func mood_of(outcome: ExitRule.Outcome, reactor: ReactorState) -> MusicMix.Mood:
	if outcome != ExitRule.Outcome.RUNNING:
		return MusicMix.Mood.ENDED
	if reactor != null and reactor.destroyed:
		return MusicMix.Mood.MELTDOWN
	return MusicMix.Mood.RUN


## The alarm level of `session`, 0..1, from its session copy (RUN-6, #1342): the
## tension layers join by the table as it rises. A level flown without an
## alarm (alone, or the tunnel) stays at 0, so only the calm layer plays.
static func alarm_level(session: LocalSession) -> float:
	return SessionSnapshots.alarm_level(session.sim.alarm)
