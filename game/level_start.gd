class_name LevelStart
extends RefCounted

## Builds the main scene's session for what the launch flies: the test tunnel,
## a level file (#291) or a generated seed (#382), and builds it again from its
## start when the destroyed ship's pilot restarts (#616). Split out of
## `main.gd` to keep it under 300 lines.
##
## It sits beside `main.gd` because it joins the `net/` session to the level
## drawing. A restart is a new session; nothing is written into the old one (MP-2).

## Where the test tunnel sits relative to the simulation origin, where the ship starts:
## 1 m below, the ship's radius, so the first tick does not push it off the floor.
const TUNNEL_OFFSET: Vector3 = Vector3(0.0, -1.0, 0.0)
## The ship's feel values, tuned after headset sessions without code changes.
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
const ROBOT_SPAWNS_PATH: String = "res://data/levels/test_tunnel_robots.json"  # (#228)

## What this launch flies, from `LevelSwitch.requested_path`: a level file
## path, `seed:<n>`, or "" for the test tunnel. Kept so a restart flies the
## same level, and a `--seed=random` pick is not drawn again.
var source: String = ""


## The test tunnel's session: inside the walls the tunnel is drawn around
## (FLT-3), with the tuning file's values or, if it is rejected, the defaults,
## the tunnel's robots, and every weapon file as a part a held part can be
## slotted from (#320), picked up and pulled as the salvage file says (#600).
static func tunnel_session(input: ShipInputSource) -> LocalSession:
	return LocalSession.new(0, input, TestTunnel.interior_box(TUNNEL_OFFSET),
		LocalSession.load_tuning(SHIP_TUNING_PATH), LocalSession.load_spawns(ROBOT_SPAWNS_PATH),
		null, LocalSession.load_parts()).use_salvage_rules(SpawnLoader.load_salvage_rules())


## The session for the level file or seed at `path`, from the level's start
## with its robots, with the level drawn under `world` where the tunnel was;
## null, drawing nothing, for "" or a rejected file.
static func level_session(world: Node3D, path: String, input: ShipInputSource) -> LocalSession:
	var level: LevelDef = LevelSwitch.load_level(path) if path != "" else null
	if level == null:
		return null
	var session: LocalSession = LocalSession.for_level(level, 0, input, LocalSession.load_tuning(SHIP_TUNING_PATH))
	LevelSwitch.show_level(world, level)
	return session


## A new session for `source` from its start: the level again, or the tunnel.
func fresh_session(world: Node3D, input: ShipInputSource) -> LocalSession:
	var session: LocalSession = level_session(world, source, input)
	return session if session != null else tunnel_session(input)
