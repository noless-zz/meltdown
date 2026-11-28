extends RefCounted

## The `console_gauges` check (#1461, GFX-2, CMF-8, PLT-5, ARC-4, DEV-6,
## decision record 0005), lane-b's file under `acceptance/checks/`. In
## `suites/m6/look.json`:
##
##     {"id": "console_gauges", "replay": "res://acceptance/replays/low_hull_test_tunnel.replay",
##      "checks": ["final_hash", "outcome", "console_gauges", "no_script_errors"], ...}
##
## The replay is the `hull_warning` step's: robots wear the shield and then the
## hull down until the ship is lost, so the hull stays under the low threshold
## for about 1.8 s first. The console's instruments are fed by the scene's own
## frames (`CombatWiring.update`), and the check fails unless they were, and
## unless the hull instrument showed its low state on some of them.
##
## Then for each of the four presets the scene's own `set_comfort_preset`
## builds that cockpit, the core's ship this frame is shown on it, and each of
## hull, shield and energy must read the core's fraction, sit at the same
## yaw and pitch and span the same angle as on preset 1 (fixed to the
## cockpit, the same place everywhere), and show the low state exactly when
## its value is under the file's threshold. At the end of the replay the hull
## is gone, so every preset's screenshot, `<step id>_preset<n>.png` under
## `m6/`, shows the low state. The preset in force before is put back; the
## simulation never notices (ARC-3; the step's `final_hash`).

const CHECK: String = "console_gauges"
const SHOT_FOLDER: String = "m6"
const GAUGES: Array[String] = [ShipGauges.HULL, ShipGauges.SHIELD, ShipGauges.ENERGY]
## How far a shown value may be from the core's.
const VALUE_TOLERANCE: float = 0.001
## How far an instrument's place or span may differ from preset 1's, degrees.
const ANGLE_TOLERANCE_DEG: float = 0.2


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	var session: LocalSession = main.get("session") as LocalSession
	if comfort == null or comfort.cockpit_frame == null or session == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no cockpit frame or no session"]
	return judge_presets(comfort.cockpit_frame, session, measurements,
		func(number: int) -> void: main.call("set_comfort_preset", number), comfort.number,
		func(number: int) -> String: return _shot(runner, "%s_preset%d.png" % [step.id, number]))


## The verdict for the console of `frame` after a flight of `session`:
## `set_preset` builds preset n on `frame`, `before` is put back at the end,
## and `shoot` takes the preset number and returns the screenshot's path or
## why none was taken.
static func judge_presets(frame: CockpitFrame, session: LocalSession, measurements: Dictionary,
		set_preset: Callable, before: int, shoot: Callable) -> Array:
	var flown: ConsoleGauges = ConsoleGauges.of_frame(frame)
	if flown == null:
		return [AcceptanceReport.RESULT_FAIL, "the cockpit in force has no console instruments"]
	var hull_flown: CockpitInstrument = _for_gauge(flown, ShipGauges.HULL)
	var low_during: int = flown.low_frames.get(hull_flown.id, 0) if hull_flown != null else 0
	measurements["frames_shown_in_flight"] = flown.updates
	measurements["hull_low_frames_in_flight"] = low_during
	var problem: String = ""
	if flown.updates == 0:
		problem = "the scene's frames never fed the console's instruments"
	elif low_during == 0:
		problem = "the hull instrument never showed its low state while the hull wore down"
	var ship: ShipState = session.current_ship()
	var core: Dictionary[String, float] = {
		ShipGauges.HULL: ship.hull / ship.max_hull if ship.max_hull > 0.0 else 0.0,
		ShipGauges.SHIELD: ship.shield / ship.max_shield if ship.max_shield > 0.0 else 0.0,
		ShipGauges.ENERGY: ship.energy / ship.max_energy if ship.max_energy > 0.0 else 0.0,
	}
	for gauge: String in GAUGES:
		measurements["core_%s" % gauge] = snappedf(core[gauge], 0.001)
	var gauges: ShipGauges = ShipGauges.take(ship, SessionSnapshots.reactor(session.sim.reactor))
	var first: Dictionary = {}
	var shots: Array[String] = []
	for number: int in range(1, ComfortPresetFiles.PATHS.size() + 1):
		set_preset.call(number)
		var console: ConsoleGauges = ConsoleGauges.of_frame(frame)
		ConsoleGauges.feed(frame, gauges, 0.0)
		var found: String = _preset_problem(console, core, first, number, measurements)
		if problem == "" and found != "":
			problem = "preset %d: %s" % [number, found]
		shots.append(str(shoot.call(number)))
	set_preset.call(before)
	measurements["screenshots"] = ", ".join(PackedStringArray(shots))
	if problem != "":
		return [AcceptanceReport.RESULT_FAIL, problem]
	return [AcceptanceReport.RESULT_PASS, "hull, shield and energy read the core's values in the same place on all four presets; the hull showed low for %d frames of flight" % low_during]


## What is wrong with `console` on preset `number`, or "". `first` holds
## preset 1's places and spans by gauge, filled on preset 1.
static func _preset_problem(console: ConsoleGauges, core: Dictionary[String, float], first: Dictionary,
		number: int, measurements: Dictionary) -> String:
	if console == null:
		return "the cockpit declares no console instruments"
	for gauge: String in GAUGES:
		var instrument: CockpitInstrument = _for_gauge(console, gauge)
		if instrument == null:
			return "no instrument reads %s" % gauge
		var value: float = console.shown.get(instrument.id, -1.0)
		var low: bool = console.is_low_shown(instrument.id)
		var at: Vector3 = place_and_span(console, instrument)
		measurements["preset%d_%s" % [number, gauge]] = [snappedf(value, 0.001), "low" if low else "normal",
			snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)]
		if absf(value - core[gauge]) > VALUE_TOLERANCE:
			return "%s reads %.3f, the core has %.3f" % [gauge, value, core[gauge]]
		if low != (core[gauge] < instrument.low_below):
			return "%s at %.3f shows %s against its threshold %.2f" % [
				gauge, value, "low" if low else "normal", instrument.low_below]
		if not first.has(gauge):
			first[gauge] = at
		elif (first[gauge] as Vector3).distance_to(at) > ANGLE_TOLERANCE_DEG:
			return "%s sits at yaw %.1f, pitch %.1f, %.1f degrees wide; on preset 1 at %s" % [
				gauge, at.x, at.y, at.z, first[gauge]]
	return ""


## Yaw and pitch of `instrument`'s face seen from the eye, and its width in
## degrees.
static func place_and_span(console: ConsoleGauges, instrument: CockpitInstrument) -> Vector3:
	var index: int = console.instruments.find(instrument)
	var seen: Vector2 = CockpitGeometry.yaw_pitch(console.place(index).origin)
	var span: float = rad_to_deg(2.0 * atan(instrument.size_m.x * 0.5 / instrument.distance_m))
	return Vector3(seen.x, seen.y, span)


static func _for_gauge(console: ConsoleGauges, gauge: String) -> CockpitInstrument:
	for instrument: CockpitInstrument in console.instruments:
		if instrument.gauge == gauge:
			return instrument
	return null


static func _shot(runner: AcceptanceRunner, file: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped %s: headless display, nothing is drawn" % file
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped %s: %s" % [file, str(got)]
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(file)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped %s: cannot write %s: %s" % [file, path, error_string(error)]
