class_name VignetteWiring
extends RefCounted

## Drives the comfort vignette from the ship's motion as shown (CMF-1, #931):
## each frame the active preset's vignette row (`ComfortVignette.strength`)
## gives a target, `VignetteFeel` eases the shown strength towards it, and the
## `Vignette` node under the camera displays it.
##
## Kept beside `main.gd` because it reads the session's two latest ship states;
## it only copies numbers out of them and writes nothing but the vignette's
## strength, so it never changes simulation state (ARC-3, CMF-6) and never
## moves the view (CMF-8).
##
## A snap turn is shown at once (CMF-3), so the tick that flew it is not
## motion the eye follows: its rotation counts as none, and a preset 1 snap
## never darkens the view.

const NODE_PATH: NodePath = ^"Camera/Vignette"

## The easing; a rejected file is printed once and the defaults are used, so
## the vignette stays on rather than off.
var feel: VignetteFeel = load_feel(VignetteFeel.DEFAULT_FILE)
## The strength shown now, 0..1.
var shown: float = 0.0
## The strength the active preset asked for this frame, 0..1; for tests.
var target: float = 0.0


## Reads the feel file at `path`; a rejected one is printed and replaced by defaults.
static func load_feel(path: String) -> VignetteFeel:
	var loaded: VignetteFeel = VignetteFeel.load_file(path)
	if loaded.error != "":
		print("Meltdown: vignette feel uses defaults: %s" % loaded.error)
		return VignetteFeel.new()
	return loaded


## True when `preset` never shows a vignette (preset 4, CMF-2). Such a preset
## drops the shown strength to 0 at once instead of fading it out.
static func is_off(preset: ComfortPreset) -> bool:
	return preset == null or preset.vignette_trigger == ComfortPreset.VignetteTrigger.NEVER \
			or preset.vignette_strength <= 0.0


## The turn rate of the view, radians per second, while it is shown between
## `previous` and `current`: the rotation of that one tick, or none when the
## tick was a snap, which is shown at once rather than as a turn.
static func shown_turn_rate(previous: ShipState, current: ShipState, snapped: bool) -> float:
	if snapped:
		return 0.0
	var from: Quaternion = previous.orientation.orthonormalized().get_rotation_quaternion()
	var to: Quaternion = current.orientation.orthonormalized().get_rotation_quaternion()
	return from.angle_to(to) / ShipState.TICK_DT


## The ship's speed as shown, metres per second: interpolated between the two
## ticks `fraction` of the way, like the pose the rig follows.
static func shown_speed(previous: ShipState, current: ShipState, fraction: float) -> float:
	return lerpf(previous.velocity.length(), current.velocity.length(), clampf(fraction, 0.0, 1.0))


## Moves the shown strength on by one frame of `delta` seconds and returns it.
## A paused session shows no motion, so its vignette eases away.
func advance(preset: ComfortPreset, previous: ShipState, current: ShipState, fraction: float,
		snapped: bool, paused: bool, delta: float) -> float:
	if is_off(preset):
		target = 0.0
		shown = 0.0
		return shown
	target = 0.0 if paused else ComfortVignette.strength(preset,
		shown_turn_rate(previous, current, snapped), shown_speed(previous, current, fraction))
	shown = clampf(feel.step(shown, target, delta), 0.0, 1.0)
	return shown


## The frame's hook in `main.gd`, after the rig is placed: the active preset
## (custom mode included) from `comfort`, copies of the ship from `session`,
## and the strength handed to the vignette under `rig`'s camera.
func update(comfort: ComfortWiring, session: LocalSession, delta: float, rig: Node) -> void:
	advance(comfort.preset, session.previous_ship(), session.current_ship(), session.interpolation_fraction,
		comfort.latest_tick_snapped, session.paused, delta)
	var node: Vignette = rig.get_node_or_null(NODE_PATH) as Vignette if rig != null else null
	if node != null:
		node.set_strength(shown)
