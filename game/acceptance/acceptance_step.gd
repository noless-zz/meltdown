class_name AcceptanceStep
extends RefCounted

## One step of an acceptance suite (DEV-6): optionally fly a replay under a
## comfort preset, then run the named checks. Built and validated by
## `AcceptanceSuite`; this class only holds the parsed values.

## Every check a step may name. A suite naming any other check is rejected, so
## a typo cannot turn a check into one that silently never runs.
const CHECK_XR_SESSION: String = "xr_session"
const CHECK_FINAL_HASH: String = "final_hash"
const CHECK_NO_SCRIPT_ERRORS: String = "no_script_errors"
## No live robot is left when the replay ends (gate G2, #334).
const CHECK_ROBOTS_CLEARED: String = "robots_cleared"
## The ship's hull is above zero when the replay ends (#334).
const CHECK_SHIP_ALIVE: String = "ship_alive"
## The run's outcome (`ExitRule.Outcome`) is `expected_outcome` when the
## replay ends (#376): a hash alone would pin a run that crashed or ran out
## of time just as firmly as one that escaped.
const CHECK_OUTCOME: String = "outcome"
## At least one meltdown debris entry is solid, or was held back by
## `DebrisRouteGuard`, when the replay ends (RUN-4, #460): an escape that
## outran every rock says nothing about flying out through falling debris.
const CHECK_DEBRIS_FALLEN: String = "debris_fallen"
## The level the replay flew in, as its session recorded it before the first
## tick (walls, start, reactor, debris, robots, tuning and weapons), hashes to
## `expected_level_hash` (#460). A seed step's level is rebuilt from the data
## files every run; a changed value that the flight happens not to feel (a
## rock's radius it never touched) still changes the level.
const CHECK_LEVEL_HASH: String = "level_hash"
## At least one box entry (a blast door) is solid when the replay ends (RUN-4,
## #516): a held-back door never fell, so unlike `debris_fallen` it does not
## count. Shows the escape still works with a door down.
const CHECK_DOOR_FALLEN: String = "door_fallen"
## No robot fired without a clear line to the ship through open space, and no
## robot shot crossed a wall, on any tick of the replay (#615, CMB-2, CMB-3):
## a pilot is never hit from where he cannot see the robot.
const CHECK_NO_HIDDEN_HITS: String = "no_hidden_hits"
## The ship's hold names a part when the replay ends (#600, SLV-1): flying
## through a destroyed robot's drop took it.
const CHECK_PART_HELD: String = "part_held"
## The display runs at no less than the active comfort preset's refresh rate
## (#598, CMF-1, PRF-1); skipped without an OpenXR runtime.
const CHECK_REFRESH_RATE: String = "refresh_rate"
## Ship 0 is destroyed during the replay, and from then on it fires nothing and
## stays where it stopped while the replay keeps sending thrust and fire (#601,
## RUN-7; `AcceptanceWreckCheck`).
const CHECK_SHIP_DESTROYED_INERT: String = "ship_destroyed_inert"
## Frame times while the step runs hold the refresh rate in use, at least
## 90 Hz (#643, PRF-1; `AcceptanceFrameBudgetCheck`); skipped off the headset.
const CHECK_FRAME_BUDGET: String = "frame_budget"
## Ship 0 hits a wall during the replay, the hits cost it hull or shield, and
## it is still moving on each contact tick and the two after it (#686, FLT-3:
## a bounce, not a stop; `AcceptanceWallCheck`).
const CHECK_WALL_BOUNCED: String = "wall_bounced"
## The view's rotation, sampled each rendered frame while the replay flies,
## keeps to the active comfort preset's limits (#687, CMF-3;
## `AcceptanceComfortCheck`). Needs a replay to sample.
const CHECK_COMFORT_MOTION: String = "comfort_motion"
## Both hands hold a tracked controller and every control the flight layout
## uses is bound in the runtime's interaction profile (#717, PLT-5;
## `AcceptanceControllersCheck`); skipped without an OpenXR runtime.
const CHECK_CONTROLLERS_BOUND: String = "controllers_bound"
## The escape's end screen shows, not the destroyed one, when the replay ends
## (#751, RUN-7; `AcceptanceEscapeScreenCheck`). Needs a replay that escapes.
const CHECK_ESCAPE_SCREEN: String = "escape_screen"
## The eye image, sampled every couple of seconds while the step runs, never
## collapses to one flat colour (#737, DEV-6, GFX-1; `AcceptanceViewFlatCheck`);
## skipped off the headset.
const CHECK_VIEW_NOT_FLAT: String = "view_not_flat"
## Ship 0's boosted top speed clearly beats normal flight, never passes
## `afterburner_max_speed`, and falls back under `max_speed` within 3 s of
## release, against the ship file's tuning (#775, FLT-2; `AcceptanceBoostCheck`).
const CHECK_AFTERBURNER: String = "afterburner"
## The first-launch flight test, answered from `flight_test_answers`, ends on
## `expected_preset` with the ship held while each answer was due (#762, CMF-4;
## `AcceptanceFlightTestCheck`). Flies no replay.
const CHECK_FLIGHT_TEST_RESULT: String = "flight_test_result"
## Ship 0 ends at the level's start pose within 1 mm and 0.1 degree, at rest,
## not turning and alive (#776, FLT-1, CMF-8; `AcceptanceResetCheck`). Needs a
## replay that sends `reset_to_start`.
const CHECK_AT_START: String = "at_start"
## No simulation tick, state hash change or camera movement while the step's
## solo pause holds, and the replay resumes on the next tick with no input
## skipped (#804, PLT-7, CMF-8; `AcceptancePauseCheck`). Needs `pause_at_tick`.
const CHECK_HELD_WHILE_PAUSED: String = "held_while_paused"
## The view's hit shake and spin, sampled each rendered frame while the replay
## flies, match the active preset's `hit_shake` and `hit_spin` (#849, CMF-1;
## `AcceptanceHitMotionCheck`). Needs a replay to sample.
const CHECK_HIT_VIEW_MOTION: String = "hit_view_motion"
## The held map draws no route before the reactor dies, then the escape route to
## the exit on every tick of the meltdown, with a cross wherever a fallen door
## blocks an explored opening (#884, MAP-2; `AcceptanceMapRouteCheck`). Needs a
## replay to sample.
const CHECK_MAP_ROUTE: String = "map_route"
## The cockpit's meltdown cue shows nothing before the reactor dies, then its
## countdown when due, counting down with the meltdown, and its arrow along the
## known route, and is gone after the escape (#885, RUN-5, MAP-2;
## `AcceptanceEscapeCueCheck`). Needs a replay to sample.
const CHECK_ESCAPE_CUE: String = "escape_cue"
const KNOWN_CHECKS: Array[String] = [CHECK_XR_SESSION, CHECK_FINAL_HASH, CHECK_NO_SCRIPT_ERRORS,
	CHECK_ROBOTS_CLEARED, CHECK_SHIP_ALIVE, CHECK_OUTCOME, CHECK_DEBRIS_FALLEN, CHECK_LEVEL_HASH,
	CHECK_DOOR_FALLEN, CHECK_NO_HIDDEN_HITS, CHECK_REFRESH_RATE, CHECK_SHIP_DESTROYED_INERT, CHECK_PART_HELD,
	CHECK_FRAME_BUDGET, CHECK_WALL_BOUNCED, CHECK_COMFORT_MOTION, CHECK_CONTROLLERS_BOUND, CHECK_ESCAPE_SCREEN,
	CHECK_VIEW_NOT_FLAT, CHECK_AFTERBURNER, CHECK_FLIGHT_TEST_RESULT, CHECK_AT_START,
	CHECK_HELD_WHILE_PAUSED, CHECK_HIT_VIEW_MOTION, CHECK_MAP_ROUTE, CHECK_ESCAPE_CUE]
## Checks that read the state the replay ended in, so a step listing one must
## fly a replay.
const REPLAY_CHECKS: Array[String] = [CHECK_FINAL_HASH, CHECK_ROBOTS_CLEARED, CHECK_SHIP_ALIVE,
	CHECK_OUTCOME, CHECK_DEBRIS_FALLEN, CHECK_LEVEL_HASH, CHECK_DOOR_FALLEN, CHECK_NO_HIDDEN_HITS,
	CHECK_SHIP_DESTROYED_INERT, CHECK_PART_HELD, CHECK_WALL_BOUNCED, CHECK_AFTERBURNER, CHECK_AT_START]

## Comfort presets are numbered 1..4 (CMF-3); 0 means the step sets none.
const NO_PRESET: int = 0
const MIN_PRESET: int = 1
const MAX_PRESET: int = 4
const NO_HASH: int = -1
const NO_OUTCOME: int = -1
const NO_SEED: int = -1
const NO_PAUSE: int = -1

## Unique within its suite; names the step in the report.
var id: String = ""
## Path of a replay file in the format `Replay` reads, or "" for none.
var replay_path: String = ""
## Level name the main scene switches to before the replay flies, as
## `--level=<name>` would (#291), or "" to fly the test tunnel.
var level: String = ""
## Generated level the replay flies (#460, GEN-1, GEN-2), or NO_SEED. The
## level is built from this seed and the shipped data files by `SeedLevel`, as
## `--seed=<n>` builds it, so the replay holds only inputs and a change to the
## generator, robot or debris data shows up as a changed flight.
var level_seed: int = NO_SEED
## Comfort preset to fly under, or NO_PRESET.
var preset: int = NO_PRESET
## Names from KNOWN_CHECKS, in the order the suite lists them.
var checks: Array[String] = []
## State hash the replay must end with, for the final_hash check, or NO_HASH.
var expected_hash: int = NO_HASH
## Level hash the step's level must have, for the level_hash check, or NO_HASH.
var expected_level_hash: int = NO_HASH
## `ExitRule.Outcome` the replay must end on, for the outcome check, or
## NO_OUTCOME. Written in a suite by name: "RUNNING", "ESCAPED" or "LOST".
var expected_outcome: int = NO_OUTCOME
## A check that cannot run on this device (no OpenXR runtime for xr_session)
## is skipped; a required step fails instead, so a headset run cannot pass
## without the check it was started for.
var required: bool = false
## For the frame_budget check (`AcceptanceFrameBudgetCheck`): seconds not
## measured after the step starts, seconds measured, the share of frames
## allowed over budget and the slack added to the frame time.
var settle_seconds: float = 0.0
var measure_seconds: float = 0.0
var max_over_budget_share: float = 0.0
var budget_slack_ms: float = 0.0
## The replay starts again from its first tick each time it ends, until the
## frame_budget check's seconds have passed (#788, `AcceptanceLoopReplay`).
var loop_replay: bool = false
## For the view_not_flat check: seconds the eye image is sampled.
var view_seconds: float = 0.0
## Ticks into the replay at which the runner saves a screenshot, and whether
## it saves one at the replay's end (#718; `AcceptanceScreenshots`).
var screenshot_ticks: Array[int] = []
var screenshot_at_end: bool = false
## For the flight_test_result check: one answer per plan segment, in order,
## and the preset the test must end on.
var flight_test_answers: Array[String] = []
var expected_preset: int = NO_PRESET
## Comfort presets switched to while the replay flies (#777, CMF-4): at
## `preset_change_ticks[i]` the runner changes to `preset_change_presets[i]`
## (`AcceptancePresetChanges`). Ticks rise; both lists are empty for none.
var preset_change_ticks: Array[int] = []
var preset_change_presets: Array[int] = []
## The solo pause (#804, `AcceptancePauseCheck`): the tick the headset comes
## off before, or NO_PAUSE, and how long it stays off.
var pause_at_tick: int = NO_PAUSE
var pause_seconds: float = 0.0
## A flight scripted as raw controller values (#818, PLT-5), flown through the
## scene's `ThumbstickMapping` in place of the replay's inputs, or "" for none;
## and whether the mapping is left-handed while it flies
## (`AcceptanceControlsScript`).
var controls_path: String = ""
var left_handed: bool = false
## A shipped custom comfort file to fly in the custom mode built from it
## (#836, CMF-1; `AcceptanceCustomComfort`), or "" for none. A step names this
## or `preset`, not both.
var custom_file: String = ""
## The pilot's 120 Hz option is on for this step only (#851, PRF-1;
## `AcceptanceRefresh120`); the refresh_rate check then wants 120 Hz.
var refresh_120: bool = false


func has_check(check: String) -> bool:
	return checks.has(check)
