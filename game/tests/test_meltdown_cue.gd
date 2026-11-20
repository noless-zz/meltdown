extends RefCounted

## The meltdown's cockpit cue and exit sign (#617, RUN-2, RUN-5, MAP-2, CMF-8):
## the large countdown shows just after the reactor dies, hides after the
## first show time and shows again at and below the threshold; the arrow
## points at the route's next corner, not at the exit through a wall; the
## exit ring stands across the start heading.

const LOOK: Dictionary = EscapeCueLook.FALLBACK


func test_countdown_visibility_at_the_boundaries() -> String:
	var first: float = LOOK["first_show_seconds"]
	var threshold: float = LOOK["warning_seconds"]
	# [elapsed since the reactor died, seconds left, shown]
	var cases: Array[Array] = [
		[0.0, 120.0, true],  # Just after the reactor dies.
		[first - 0.01, 120.0 - first, true],
		[first, 120.0 - first, false],  # After the first show time.
		[60.0, threshold + 0.01, false],
		[60.0, threshold, true],  # At the threshold.
		[60.0, threshold - 0.5, true],  # Below it.
		[119.0, 0.0, true],
		[0.0, -1.0, false],  # No meltdown.
	]
	for case: Array in cases:
		if MeltdownCue.large_visible(case[0], case[1], LOOK) != case[2]:
			return "%s s after, %s s left: shown should be %s" % case
	return ""


func test_a_short_meltdown_shows_without_a_gap() -> String:
	# Under the threshold from the start, the countdown never hides.
	for tenth: int in 200:
		var elapsed: float = tenth / 10.0
		if not MeltdownCue.large_visible(elapsed, 20.0 - elapsed, LOOK):
			return "a 20 s meltdown hid the countdown at %s s" % elapsed
	return ""


func test_the_node_shows_text_line_and_warning_colour() -> String:
	var cue: MeltdownCue = MeltdownCue.new(LOOK)
	cue.show_countdown(95.4, 0.5)
	var early: Array = [cue.countdown.visible, cue.line.visible, cue.countdown.text,
		cue.line.text, cue.countdown.modulate]
	cue.show_countdown(90.0, 6.0)
	var hidden: bool = not cue.countdown.visible and not cue.line.visible
	cue.show_countdown(12.7, 108.0)
	var late: Array = [cue.countdown.visible, cue.countdown.text, cue.countdown.modulate]
	cue.show_countdown(-1.0, 0.0)
	var none: bool = not cue.countdown.visible and not cue.line.visible
	cue.free()
	if early != [true, true, "1:35", "Escape through the entrance", LOOK["text_color"]]:
		return "just after the reactor died the cue read %s" % [early]
	if not hidden:
		return "the cue still showed after the first show time"
	if late != [true, "0:12", LOOK["warning_color"]]:
		return "below the threshold the cue read %s" % [late]
	if not none:
		return "the cue showed without a meltdown"
	return ""


func test_the_waypoint_is_the_corner_after_the_ship() -> String:
	var route: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -10),
		Vector3(10, 0, -10)])
	if MeltdownCue.waypoint(route) != [true, Vector3(0, 0, -10)]:
		return "the waypoint is %s, not the turn" % [MeltdownCue.waypoint(route)]
	if MeltdownCue.waypoint(PackedVector3Array([Vector3.ONE]))[0] \
			or MeltdownCue.waypoint(PackedVector3Array())[0]:
		return "a route without two corners gave a waypoint"
	return ""


## A route that turns: the ship at the origin, an opening 10 m ahead, the exit
## 10 m to the right of that. The ship is turned and rolled, so the arrow's
## direction must come out right in the world whatever the cockpit's pose.
func test_the_arrow_points_at_the_turn_not_the_exit() -> String:
	var cue: MeltdownCue = MeltdownCue.new(LOOK)
	var turn: Vector3 = Vector3(0, 0, -10)
	var exit_at: Vector3 = Vector3(10, 0, -10)
	var pose: Transform3D = Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.FORWARD, 0.4),
		Vector3(0.0, 0.0, 0.0))
	var target: Array = MeltdownCue.waypoint(PackedVector3Array([Vector3.ZERO, turn, exit_at]))
	cue.point_at(target[0], target[1], pose)
	var shown: bool = cue.arrow.visible
	var direction: Vector3 = cue.arrow_direction(pose)
	var from: Vector3 = pose * cue.arrow.position
	cue.point_at(false, Vector3.ZERO, pose)
	var hidden: bool = not cue.arrow.visible
	cue.free()
	if not shown:
		return "the arrow was hidden with a route"
	var want: Vector3 = (turn - from).normalized()
	if direction.angle_to(want) > 0.01:
		return "the arrow points %s, the turn is %s" % [direction, want]
	if direction.angle_to((exit_at - from).normalized()) < 0.5:
		return "the arrow points at the exit through the wall"
	if not hidden:
		return "the arrow stayed without a route"
	return ""


func test_the_arrow_points_straight_up_or_down() -> String:
	var cue: MeltdownCue = MeltdownCue.new(LOOK)
	var from: Vector3 = cue.arrow.position
	cue.point_at(true, from + Vector3(0, 30, 0), Transform3D.IDENTITY)
	var up: Vector3 = cue.arrow_direction(Transform3D.IDENTITY)
	cue.point_at(true, from + Vector3(0, -30, 0), Transform3D.IDENTITY)
	var down: Vector3 = cue.arrow_direction(Transform3D.IDENTITY)
	cue.free()
	if up.angle_to(Vector3.UP) > 0.01 or down.angle_to(Vector3.DOWN) > 0.01:
		return "straight up gave %s and straight down %s" % [up, down]
	return ""


func test_the_exit_ring_stands_across_the_start_heading() -> String:
	var marker: ExitMarker = ExitMarker.new(LOOK)
	var facing: Basis = Basis(Vector3.UP, PI / 2.0)  # Facing -x.
	marker.place(Vector3(4, 5, 6), facing)
	var axis: Vector3 = marker.ring_axis()
	var at: Vector3 = marker.position
	var text: String = marker.text.text
	var above: bool = marker.text.position.y > float(LOOK["exit_ring_radius_m"])
	marker.free()
	if absf(axis.dot(Vector3.RIGHT)) < 0.999:
		return "the ring's axis is %s, not along the start heading" % axis
	if at != Vector3(4, 5, 6) or text != "EXIT" or not above:
		return "the sign is at %s reading %s, above the ring %s" % [at, text, above]
	return ""
