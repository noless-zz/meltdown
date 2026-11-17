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
const KNOWN_CHECKS: Array[String] = [CHECK_XR_SESSION, CHECK_FINAL_HASH, CHECK_NO_SCRIPT_ERRORS,
	CHECK_ROBOTS_CLEARED, CHECK_SHIP_ALIVE]
## Checks that read the state the replay ended in, so a step listing one must
## fly a replay.
const REPLAY_CHECKS: Array[String] = [CHECK_FINAL_HASH, CHECK_ROBOTS_CLEARED, CHECK_SHIP_ALIVE]

## Comfort presets are numbered 1..4 (CMF-3); 0 means the step sets none.
const NO_PRESET: int = 0
const MIN_PRESET: int = 1
const MAX_PRESET: int = 4
const NO_HASH: int = -1

## Unique within its suite; names the step in the report.
var id: String = ""
## Path of a replay file in the format `Replay` reads, or "" for none.
var replay_path: String = ""
## Level name the main scene switches to before the replay flies, as
## `--level=<name>` would (#291), or "" to fly the test tunnel.
var level: String = ""
## Comfort preset to fly under, or NO_PRESET.
var preset: int = NO_PRESET
## Names from KNOWN_CHECKS, in the order the suite lists them.
var checks: Array[String] = []
## State hash the replay must end with, for the final_hash check, or NO_HASH.
var expected_hash: int = NO_HASH
## A check that cannot run on this device (no OpenXR runtime for xr_session)
## is skipped; a required step fails instead, so a headset run cannot pass
## without the check it was started for.
var required: bool = false


func has_check(check: String) -> bool:
	return checks.has(check)
