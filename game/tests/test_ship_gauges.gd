extends RefCounted

## One snapshot of hull, shield, energy and the meltdown countdown a frame
## (#1216, ARC-3, CMF-6): the fractions from a known ship, the countdown from
## the reactor, and the status panel showing exactly what it did before.


static func _ship() -> ShipState:
	var ship: ShipState = ShipState.new()
	ship.max_hull = 100.0
	ship.hull = 40.0
	ship.max_shield = 50.0
	ship.shield = 10.0
	ship.max_energy = 100.0
	ship.energy = 75.0
	return ship


func test_fractions_from_a_known_ship_state() -> String:
	var gauges: ShipGauges = ShipGauges.take(_ship(), null)
	var got: Vector3 = Vector3(gauges.hull, gauges.shield, gauges.energy)
	if not got.is_equal_approx(Vector3(0.4, 0.2, 0.75)):
		return "hull, shield, energy read %s, not (0.4, 0.2, 0.75)" % got
	if gauges.has_countdown() or gauges.countdown != ShipGauges.NO_COUNTDOWN:
		return "no reactor gives a countdown of %s" % gauges.countdown
	return ""


func test_a_zero_maximum_reads_empty_and_fractions_clamp() -> String:
	var ship: ShipState = _ship()
	ship.max_shield = 0.0
	ship.hull = 150.0
	ship.energy = -5.0
	var gauges: ShipGauges = ShipGauges.take(ship, null)
	if gauges.shield != 0.0 or gauges.hull != 1.0 or gauges.energy != 0.0:
		return "read hull %s, shield %s, energy %s" % [gauges.hull, gauges.shield, gauges.energy]
	return ""


func test_the_countdown_runs_only_after_the_reactor_is_destroyed() -> String:
	var reactor: ReactorState = ReactorState.new()
	reactor.meltdown_ticks_left = 90 * ReactorState.TICKS_PER_SECOND
	var intact: ShipGauges = ShipGauges.take(_ship(), reactor)
	reactor.destroyed = true
	var running: ShipGauges = ShipGauges.take(_ship(), reactor)
	if intact.has_countdown():
		return "an intact reactor gives a countdown of %s" % intact.countdown
	if not is_equal_approx(running.countdown, 90.0):
		return "a destroyed reactor with 90 s of ticks gives %s" % running.countdown
	if not is_equal_approx(running.value(ShipGauges.COUNTDOWN), 90.0) \
			or not is_equal_approx(running.value(ShipGauges.HULL), 0.4):
		return "value() reads %s and %s" % [running.value(ShipGauges.COUNTDOWN), running.value(ShipGauges.HULL)]
	return ""


func test_taking_the_gauges_writes_nothing() -> String:
	var ship: ShipState = _ship()
	var reactor: ReactorState = ReactorState.new()
	reactor.destroyed = true
	reactor.meltdown_ticks_left = 600
	var ship_hash: int = ship.state_hash()
	var ticks: int = reactor.meltdown_ticks_left
	for frame: int in 5:
		ShipGauges.take(ship, reactor)
	if ship.state_hash() != ship_hash or reactor.meltdown_ticks_left != ticks or not reactor.destroyed:
		return "taking the gauges changed the ship or the reactor"
	return ""


## The panel draws from the gauges what it drew before #1216 from the separate
## calls: bars at the fractions, the hull warning, the countdown text.
func test_the_panel_shows_the_same_values_as_before() -> String:
	var ship: ShipState = _ship()
	ship.hull = 20.0  # Under the 25 % warning.
	var reactor: ReactorState = ReactorState.new()
	reactor.destroyed = true
	reactor.meltdown_ticks_left = 75 * ReactorState.TICKS_PER_SECOND
	var panel: StatusPanel = StatusPanel.new()
	panel.show_gauges(ShipGauges.take(ship, reactor))
	var bars: Vector3 = Vector3(panel.hull_bar_scale(), panel.shield_bar_scale(), panel.energy_bar_scale())
	var warning: bool = panel.hull_warning_shown()
	var countdown: String = String(panel.texts()[StatusPanel.MELTDOWN_NAME])
	var shown: bool = panel.meltdown_visible()
	reactor.destroyed = false
	panel.show_gauges(ShipGauges.take(ship, reactor))
	var hidden: bool = not panel.meltdown_visible()
	panel.free()
	if not bars.is_equal_approx(Vector3(0.2, 0.2, 0.75)):
		return "bars hull, shield, energy drew %s" % bars
	if not warning:
		return "a 20 % hull shows no warning"
	if not shown or not countdown.contains("1:15"):
		return "75 s of meltdown reads '%s', shown %s" % [countdown, shown]
	if not hidden:
		return "the countdown row stays up with no countdown"
	return ""


func test_the_main_scene_panel_reads_the_ships_gauges() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	for frame: int in 3:
		main.call("advance_frame", 1.0 / 90.0)
	var panel: StatusPanel = main.get("status_panel")
	var session: LocalSession = main.get("session")
	var want: ShipGauges = ShipGauges.take(session.current_ship(),
		SessionSnapshots.reactor(session.sim.reactor))
	var got: ShipGauges = panel.gauges
	main.free()
	for gauge: String in ShipGauges.NAMES:
		if not is_equal_approx(got.value(gauge), want.value(gauge)):
			return "%s on the panel is %s, the ship's is %s" % [gauge, got.value(gauge), want.value(gauge)]
	return ""
