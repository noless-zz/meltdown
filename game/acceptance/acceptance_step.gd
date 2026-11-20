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
const KNOWN_CHECKS: Array[String] = [CHECK_XR_SESSION, CHECK_FINAL_HASH, CHECK_NO_SCRIPT_ERRORS,
	CHECK_ROBOTS_CLEARED, CHECK_SHIP_ALIVE, CHECK_OUTCOME, CHECK_DEBRIS_FALLEN, CHECK_LEVEL_HASH,
	CHECK_DOOR_FALLEN, CHECK_NO_HIDDEN_HITS, CHECK_REFRESH_RATE, CHECK_SHIP_DESTROYED_INERT, CHECK_PART_HELD,
	CHECK_FRAME_BUDGET]
## Checks that read the state the replay ended in, so a step listing one must
## fly a replay.
const REPLAY_CHECKS: Array[String] = [CHECK_FINAL_HASH, CHECK_ROBOTS_CLEARED, CHECK_SHIP_ALIVE,
	CHECK_OUTCOME, CHECK_DEBRIS_FALLEN, CHECK_LEVEL_HASH, CHECK_DOOR_FALLEN, CHECK_NO_HIDDEN_HITS,
	CHECK_SHIP_DESTROYED_INERT, CHECK_PART_HELD]

## Comfort presets are numbered 1..4 (CMF-3); 0 means the step sets none.
const NO_PRESET: int = 0
const MIN_PRESET: int = 1
const MAX_PRESET: int = 4
const NO_HASH: int = -1
const NO_OUTCOME: int = -1
const NO_SEED: int = -1

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


func has_check(check: String) -> bool:
	return checks.has(check)
