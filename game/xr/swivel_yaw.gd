class_name SwivelYaw
extends RefCounted

## Swivel-chair mode (CMF-7): turning the body in a real chair turns the ship.
## Off by default and not wired yet (#722); it only answers a yaw stick value.
##
## The headset's yaw is compared with a reference heading. Inside the dead
## zone the answer is 0, so looking around the cockpit never turns the ship;
## past it the answer grows with the angle up to `max_input`. The value is
## added to the stick's yaw before `ComfortInputFilter`, so it is just more
## stick: preset 1 still turns only by snaps (CMF-3), preset 2's rate caps
## still hold, and the core sees an ordinary input on every preset (CMF-6).
## Nothing here touches the simulation (ARC-3).
##
## The reference drifts towards the body at `follow_deg_per_s`, so a player
## who settles facing a new direction stops turning without a recentre. A
## recentre puts the reference back on the head at once.
##
## Kept apart from look-aim (#678), which also reads the head direction but
## for aiming, not turning. The switch and tuning are rows of the comfort
## preset (#779), so the custom comfort file can turn the mode on (CMF-1).

## Off unless the preset says otherwise.
var enabled: bool = false
## Head yaw either side of the reference that gives nothing, degrees, 0..90.
var dead_zone_deg: float = 30.0
## Stick yaw per degree past the dead zone, 0..1.
var gain_per_deg: float = 0.03
## Largest stick yaw this may give, 0..1.
var max_input: float = 1.0
## How fast the reference follows the body, degrees per second, 0..180.
## 0 never follows.
var follow_deg_per_s: float = 5.0

## Set when the preset was rejected; empty otherwise.
var error: String = ""
## Head yaw that counts as facing forward, radians about +Y.
var reference_rad: float = 0.0


## Takes the swivel settings of `preset`. A missing preset, or one that fails
## `ComfortPreset.validation_error()`, gives a swivel that stays off with
## `error` naming the reason.
static func from_preset(preset: ComfortPreset) -> SwivelYaw:
	var swivel: SwivelYaw = SwivelYaw.new()
	if preset == null:
		swivel.error = "no comfort preset"
		return swivel
	var invalid: String = preset.validation_error()
	if not invalid.is_empty():
		swivel.error = invalid
		return swivel
	swivel.enabled = preset.swivel_enabled
	swivel.dead_zone_deg = preset.swivel_dead_zone_deg
	swivel.gain_per_deg = preset.swivel_gain_per_deg
	swivel.max_input = preset.swivel_max_input
	swivel.follow_deg_per_s = preset.swivel_follow_deg_per_s
	return swivel


## Makes `head_yaw_rad` the forward heading, for the recentre event.
func recentre(head_yaw_rad: float = 0.0) -> void:
	reference_rad = head_yaw_rad


## Returns this frame's yaw stick value, -1..1, + turning the nose right like
## the stick's x. `head_yaw_rad` is the headset's yaw relative to the cockpit,
## radians about +Y (+ is turned left, as `HeadRecentre.heading` gives it).
## `delta` is the frame time in seconds, used only to move the reference.
func update(head_yaw_rad: float, delta: float) -> float:
	if not enabled:
		return 0.0
	var turned: float = wrapf(head_yaw_rad - reference_rad, -PI, PI)
	var value: float = stick_for(turned)
	var step: float = deg_to_rad(follow_deg_per_s) * maxf(delta, 0.0)
	reference_rad = wrapf(reference_rad + clampf(turned, -step, step), -PI, PI)
	return value


## The stick yaw for a head turned `turned_rad` from the reference.
func stick_for(turned_rad: float) -> float:
	var past: float = absf(rad_to_deg(turned_rad)) - dead_zone_deg
	if not enabled or past <= 0.0:
		return 0.0
	# Head turned left (+) means the nose should go left: negative stick yaw.
	return -signf(turned_rad) * minf(past * gain_per_deg, max_input)


## A copy of `input` with `stick_yaw` (-1..1, + nose right) added to its yaw,
## the result kept within the stick's full rate. Feed this to
## `ComfortInputFilter.filter` so the preset still applies.
static func added_to(input: ShipInput, stick_yaw: float) -> ShipInput:
	var full: int = roundi(ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
	var out: ShipInput = ComfortInputFilter.copy_input(input)
	var extra: int = roundi(-stick_yaw * ThumbstickMapping.MAX_YAW_RATE * ShipInput.SCALE)
	out.turn_q = Vector3i(out.turn_q.x, clampi(out.turn_q.y + extra, -full, full), out.turn_q.z)
	return out

