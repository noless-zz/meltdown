extends RefCounted

## The bot pilot gets past a corner where a robot's line of sight grazes the
## ship (#658, DEV-3, GEN-3, DEV-6). Before #658, seed 4 of the bot sweep with
## robots and debris held the ship at such a corner from about tick 2,000 to
## the 36,000-tick limit: in sight it turned to the skimmer and weaved out of
## the line, out of sight it turned to the opening and flew back in, and since
## #612 the skimmer winds up before firing, so no one ever fired. `BotStall`
## notices the ship has stopped getting anywhere and the pilot then flies
## through.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const SeedSweepRef := preload("res://tests/seed_sweep.gd")
const STALLED_SEED: int = 4
## Seed 4 escapes at about tick 8,400 with the stall check; well inside
## `Sweep.TICK_LIMIT` (36,000) with room for harmless changes elsewhere.
const ESCAPE_BY_TICK: int = 15000


func test_a_ship_that_keeps_moving_never_stalls() -> String:
	var stall: BotStall = BotStall.new()
	for tick: int in range(BotStall.TICKS * 3):
		# 0.1 m a tick: 6 m/s, out of any 2 m circle within a second.
		if stall.update(Vector3(0.1 * tick, 0.0, 0.0)):
			return "stalled at tick %d while moving" % tick
	return ""


func test_a_ship_held_in_place_stalls_after_ticks() -> String:
	var stall: BotStall = BotStall.new()
	for tick: int in range(BotStall.TICKS):
		# Jitters a few centimetres either way, as the stalled bot did.
		var jitter: float = 0.05 if tick % 2 == 0 else -0.05
		if stall.update(Vector3(jitter, 0.0, 0.0)):
			return "stalled at tick %d, before %d" % [tick, BotStall.TICKS]
	if not stall.update(Vector3.ZERO):
		return "not stalled after %d ticks in place" % BotStall.TICKS
	return ""


## Seed 6 after #603: the ship swung about 2 m either way while the middle of
## the swing crept about 3 m in 20 s. That still counts as going nowhere.
func test_a_ship_swinging_round_a_creeping_point_stalls() -> String:
	var stall: BotStall = BotStall.new()
	var stalled: bool = false
	for tick: int in range(BotStall.TICKS + 1):
		var creep: float = 3.0 * float(tick) / float(BotStall.TICKS)
		var swing: float = 2.0 if tick % 80 < 40 else -2.0
		stalled = stall.update(Vector3(creep * 0.5 + swing * 0.5, swing * 0.8, creep * 0.5))
	if not stalled:
		return "not stalled after %d ticks swinging round a creeping point" % BotStall.TICKS
	return ""


func test_leaving_the_spot_ends_the_stall() -> String:
	var stall: BotStall = BotStall.new()
	for tick: int in range(BotStall.TICKS + 1):
		stall.update(Vector3.ZERO)
	if stall.update(Vector3(BotStall.RADIUS + 0.5, 0.0, 0.0)):
		return "still stalled after moving %.1f m" % (BotStall.RADIUS + 0.5)
	return ""


func test_stalls_outlast_the_bots_own_waits() -> String:
	if BotStall.TICKS <= BotPilot.MAX_WAIT_TICKS:
		return "stall after %d ticks would cut short a %d-tick wait" % [BotStall.TICKS,
				BotPilot.MAX_WAIT_TICKS]
	return ""


func test_the_bot_gets_past_the_corner_on_seed_4() -> String:
	var level: LevelDef = Sweep.generate(STALLED_SEED, SeedSweepRef.load_modules(),
			SeedSweepRef.load_loop_bridges()).to_level_def(SeedSweepRef.load_reactor_plan(),
			SeedSweepRef.ship_radius(), SeedSweepRef.load_robot_plan(), Sweep.load_debris_plan())
	var flown: Sweep.SeedResult = Sweep.fly(STALLED_SEED, level,
			LocalSession.load_tuning(Sweep.SHIP_TUNING_PATH))
	if not flown.escaped:
		return flown.line()
	if flown.tick > ESCAPE_BY_TICK:
		return "escaped at tick %d, after %d" % [flown.tick, ESCAPE_BY_TICK]
	return ""
