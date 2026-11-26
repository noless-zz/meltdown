class_name HubLaunch
extends RefCounted

## What the pilot sees and hears leaving the home base and coming back to it
## (#1396, CRW-2, CMF-1, CMF-3, CMF-8, AUD-1): the `LaunchFade` look shown on
## the room. Choosing Launch raises the cradle ship's engine glow with a rising
## launch sound, then fades the room out to the look's colour; the hub's
## unchanged launch runs on the frame the colour is full, so the level loads
## behind it, and the mine fades in. Arriving at the base fades the room in.
##
## The room is drawn on its own render layer, so it gets a fade quad of its own
## on that layer (`room_overlay`); the scene's quad (`view_overlay`) darkens the
## mine, and the hub hands it the fade's opacity through `HubWiring.alpha`.
## Nothing here moves the camera or the room, and nothing reads or writes the
## simulation (ARC-3, MP-2). It sits beside `main.gd` with `HubWiring`, which
## drives it.

const ROOM_OVERLAY_NAME: String = "HubFadeOverlay"

var fade: LaunchFade = LaunchFade.load_file()
## The quad that fades the room, on the room's layer only; null in tests without a camera.
var room_overlay: FadeOverlay = null
## The scene's own fade quad, whose colour the launch sets; null without one.
var view_overlay: FadeOverlay = null
## The launch sound at the cradle ship; null when the room has no ship.
var sound: LaunchSound = null

var _ship: ShipModel = null


## Hangs the room's fade quad on `camera` and the sound on `room`'s ship.
## Either may be null. Calling it again adds nothing.
func attach(camera: Node3D, room: HubRoom) -> void:
	if camera != null and room_overlay == null:
		view_overlay = camera.get_node_or_null(FadeOverlay.NODE_NAME) as FadeOverlay
		room_overlay = FadeOverlay.new()
		room_overlay.name = ROOM_OVERLAY_NAME
		room_overlay.layers = HubRoom.LAYER_BIT
		camera.add_child(room_overlay)
	if room != null and room.ship() != null and _ship == null:
		_ship = room.ship()
		sound = LaunchSound.new()
		_ship.add_child(sound)
	_show()


## The pilot arrives at the base: the engine is at idle and the room fades in.
func arrive() -> void:
	fade.start_fade_in()
	_show()


## Starts the launch: the glow and the sound, then the fade out. False while
## one is already under way.
func start() -> bool:
	if not fade.start_launch():
		return false
	if sound != null:
		sound.sound()
	_show()
	return true


## After a resume, which leaves at once: the mine fades in.
func left() -> void:
	fade.start_fade_in()
	_show()


## Runs the fade by `seconds`. True on the frame the launch is due: the view
## is fully dark and the fade in begins.
func advance(seconds: float) -> bool:
	var due: bool = fade.advance(seconds)
	_show()
	return due


func is_launching() -> bool:
	return fade.is_launching()


## The fade's opacity this frame, 0..1.
func alpha() -> float:
	return fade.alpha()


## The cradle ship's engine and both quads, from the fade's state.
func _show() -> void:
	if _ship != null:
		_ship.set_thrust(fade.glow())
	var shown: float = fade.alpha()
	if room_overlay != null:
		room_overlay.set_color(fade.color)
		room_overlay.set_alpha(shown)
	if view_overlay != null:
		# The other fades are black; the launch's colour shows only while it fades.
		view_overlay.set_color(fade.color if shown > 0.0 else Color.BLACK)
