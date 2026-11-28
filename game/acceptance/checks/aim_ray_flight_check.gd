extends RefCounted

## The `aim_ray_hidden_in_flight` check (#1508, PLT-5, CMF-8, CRW-2, MP-2),
## lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "aim_ray_hidden_in_flight", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "aim_ray_hidden_in_flight"]}
##
## After the replay the ship is lost and restart pressed, so the hub opens in
## the room (`hub_room_check.gd`); the ray must show there. The pilot then
## launches from the launch station through the scene's own `apply_controls`
## and `advance_frame` (`launch_fade_check.gd`'s `judge_launch`), and flies
## 120 ticks: on every frame the ray, its dot and the stations' highlight must
## be hidden. A tap opens the dev menu in flight, where the ray must show; a
## second tap closes it, and the ray must be hidden again.
##
## No controller is tracked in a headless run, so each frame asks the scene's
## own rig ray with a tracked aim in front of the seat, as the rig does every
## frame on the headset. Whether the mine looks clear of it stays a headset check.

const CHECK: String = "aim_ray_hidden_in_flight"
const HubRoomCheck := preload("res://acceptance/checks/hub_room_check.gd")
const LaunchFadeCheck := preload("res://acceptance/checks/launch_fade_check.gd")
const MenuCheck := preload("res://acceptance/checks/menu_at_base_check.gd")
const PROFILE_FILE: String = "user://meltdown_acceptance_aim_ray_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_aim_ray_fitting.json"
## One frame per simulation tick, so 120 frames fly 120 ticks.
const TICK: float = 1.0 / 60.0
const FLIGHT_TICKS: int = 120
## A right-hand aim in the rig's space, forward from about where a hand rests.
const AIM: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.2, 1.2, -0.3))


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var hub: HubWiring = main.get("hub") as HubWiring
	var menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var rig: Node = main.get_node_or_null("XRRig")
	var ray: AimRay = rig.call("aim_ray") as AimRay if rig != null else null
	if hub == null or menu == null or ray == null or level_start == null or level_start.run == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no hub, dev menu, rig ray or run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = HubRoomCheck.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS and not shown(rig, ray):
		verdict = [AcceptanceReport.RESULT_FAIL, "no aim ray at the home base"]
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = LaunchFadeCheck.judge_launch(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = judge_flight(main, hub, menu, rig, ray, measurements)
	if menu.is_open():
		menu.menu.close()
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


## In flight after the launch: 120 ticks with no ray, then the menu opened and closed.
static func judge_flight(main: Node, hub: HubWiring, menu: DevMenuWiring, rig: Node, ray: AimRay,
		measurements: Dictionary) -> Array:
	for tick: int in FLIGHT_TICKS:
		_fly_tick(main)
		if shown(rig, ray):
			return [AcceptanceReport.RESULT_FAIL, "the aim ray shows in flight at tick %d" % tick]
		if hub.stations != null and hub.stations.visible:
			return [AcceptanceReport.RESULT_FAIL, "the stations and their highlight show in flight at tick %d" % tick]
	measurements["flight_ticks_without_ray"] = FLIGHT_TICKS
	MenuCheck.tap(main)
	if not menu.is_open():
		return [AcceptanceReport.RESULT_FAIL, "a tap in flight did not open the dev menu"]
	if not shown(rig, ray):
		return [AcceptanceReport.RESULT_FAIL, "the open dev menu in flight shows no aim ray"]
	MenuCheck.tap(main)
	if menu.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the second tap did not close the dev menu"]
	if shown(rig, ray):
		return [AcceptanceReport.RESULT_FAIL, "the aim ray stayed after the dev menu closed in flight"]
	return [AcceptanceReport.RESULT_PASS, "ray at the base, none for %d ticks after the launch, shown in the open menu, gone when it closed" %
		FLIGHT_TICKS]


## The rig's ray after one frame's `follow` with a tracked aim.
static func shown(rig: Node, ray: AimRay) -> bool:
	ray.follow(rig, AIM, true)
	return ray.visible or ray.shows_dot()


## One frame of one tick's length with the controls idle.
static func _fly_tick(main: Node) -> void:
	main.call("apply_controls", ControllerSampler.idle_values())
	main.call("advance_frame", TICK)


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
