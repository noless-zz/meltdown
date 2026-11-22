extends RefCounted

## The aiming reticle's target (CMB-6, ARC-4, #1211): dimmed at the look's
## distance with no robot ahead, at full alpha on a live robot inside the
## look's cone and the active weapon's range, at that robot's distance, and
## the weapon's range read from the selected slot.

const RANGE: float = 100.0


func _robot(position: Vector3) -> RobotState:
	var def: RobotDef = RobotDef.new()
	def.hull = 10.0
	return RobotState.new(def, position)


## A reticle placed for a ship at the origin facing -z with guns on the nose.
func _placed(robots: Array[RobotState], weapon_range: float = RANGE) -> AimReticle:
	var reticle: AimReticle = AimReticle.new()
	reticle.show_aim(Transform3D.IDENTITY, LookAim.NOSE, robots, weapon_range)
	return reticle


func test_the_dimmed_alpha_comes_from_the_look() -> String:
	var reticle: AimReticle = _placed([])
	var color: Color = reticle.shown_color()
	var full: Color = reticle.look["color"]
	var dim: float = float(reticle.look["dim_alpha"])
	reticle.free()
	if not is_equal_approx(color.a, full.a * dim) or color.a >= full.a:
		return "dimmed alpha %s, expected %s" % [color.a, full.a * dim]
	return ""


func test_with_no_robot_ahead_it_is_dimmed_at_the_look_distance() -> String:
	var reticle: AimReticle = _placed([])
	var on: bool = reticle.on_target
	var at: Vector3 = reticle.transform.origin
	var expected: Vector3 = Vector3(0.0, 0.0, -float(reticle.look["distance_m"]))
	var alpha: float = reticle.shown_color().a
	var full: float = (reticle.look["color"] as Color).a
	reticle.free()
	if on or alpha >= full:
		return "with nothing ahead: on target %s, alpha %s" % [on, alpha]
	if not at.is_equal_approx(expected):
		return "with nothing ahead the reticle sits at %s, expected %s" % [at, expected]
	return ""


func test_a_robot_ahead_in_range_brightens_it_at_its_distance() -> String:
	var near: RobotState = _robot(Vector3(0.5, 0.0, -40.0))
	var far: RobotState = _robot(Vector3(0.0, 0.0, -70.0))
	var reticle: AimReticle = _placed([far, near])
	var on: bool = reticle.on_target
	var at: Vector3 = reticle.transform.origin
	var alpha: float = reticle.shown_color().a
	var full: float = (reticle.look["color"] as Color).a
	var scale: float = reticle.transform.basis.get_scale().x
	var expected_scale: float = near.position.length() / float(reticle.look["distance_m"])
	reticle.free()
	var expected: Vector3 = Vector3(0.0, 0.0, -near.position.length())
	if not on or not is_equal_approx(alpha, full):
		return "with a robot ahead: on target %s, alpha %s of %s" % [on, alpha, full]
	if not at.is_equal_approx(expected):
		return "the reticle sits at %s, expected the nearer robot's distance %s" % [at, expected]
	if not is_equal_approx(scale, expected_scale):
		return "the ring is scaled %s at that distance, expected %s" % [scale, expected_scale]
	return ""


func test_a_robot_outside_the_cone_does_not_brighten_it() -> String:
	var cone: float = float(AimReticleLook.FALLBACK["cone_degrees"])
	var angle: float = deg_to_rad(cone + 2.0)
	var robot: RobotState = _robot(Vector3(sin(angle), 0.0, -cos(angle)) * 30.0)
	var reticle: AimReticle = _placed([robot])
	var on: bool = reticle.on_target
	reticle.free()
	return "a robot %s degrees off the aim brightened the reticle" % (cone + 2.0) if on else ""


func test_a_robot_beyond_range_or_dead_does_not_brighten_it() -> String:
	var beyond: RobotState = _robot(Vector3(0.0, 0.0, -(RANGE + 5.0)))
	var dead: RobotState = _robot(Vector3(0.0, 0.0, -20.0))
	dead.hull = 0.0
	var reticle: AimReticle = _placed([beyond, dead])
	var on: bool = reticle.on_target
	reticle.free()
	if on:
		return "a robot beyond range or a dead one brightened the reticle"
	var empty_slot: AimReticle = _placed([_robot(Vector3(0.0, 0.0, -20.0))], 0.0)
	var on_empty: bool = empty_slot.on_target
	empty_slot.free()
	return "with no weapon a robot ahead brightened the reticle" if on_empty else ""


func test_the_target_follows_the_gun_direction_not_the_nose() -> String:
	var aim: Vector3 = Vector3(sin(deg_to_rad(20.0)), 0.0, -cos(deg_to_rad(20.0)))
	var robot: RobotState = _robot(aim * 30.0)
	var reticle: AimReticle = AimReticle.new()
	reticle.show_aim(Transform3D.IDENTITY, aim, [robot], RANGE)
	var on: bool = reticle.on_target
	reticle.show_aim(Transform3D.IDENTITY, LookAim.NOSE, [robot], RANGE)
	var on_nose: bool = reticle.on_target
	reticle.free()
	if not on or on_nose:
		return "on the look-aim robot %s; with guns on the nose %s" % [on, on_nose]
	return ""


func test_the_weapon_range_is_speed_times_lifetime_of_the_selected_slot() -> String:
	var ship: ShipState = ShipState.new()
	if CombatWiring.weapon_range(ship) != 0.0:
		return "an empty slot has range %s" % CombatWiring.weapon_range(ship)
	var weapon: WeaponDef = WeaponDef.new()
	weapon.projectile_speed = 80.0
	weapon.lifetime = 1.25
	ship.primary_slots[ship.selected_primary] = weapon
	if not is_equal_approx(CombatWiring.weapon_range(ship), 100.0):
		return "range %s, expected 100" % CombatWiring.weapon_range(ship)
	return ""
