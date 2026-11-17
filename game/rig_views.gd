class_name RigViews
extends RefCounted

## The views the main scene hangs on the rig around the eye: the reset fade
## under the camera, and the cockpit frame and status panel under the rig
## origin at the recentred head point (CMF-1, #146, #478).
##
## Split out of `main.gd` to keep it under 300 lines. Everything here reads
## copies of ship state and never writes `ShipState` or `Sim` (ARC-3, MP-2).


## Adds a fade quad under `rig`'s camera and returns it, or null when the rig
## has no camera. The fade must cover the eyes, so it turns with the head.
static func add_fade_overlay(rig: Node3D) -> FadeOverlay:
	var camera: Node3D = rig.get_node_or_null("Camera") as Node3D if rig != null else null
	if camera == null:
		return null
	var fade: FadeOverlay = FadeOverlay.new()
	camera.add_child(fade)
	return fade


## Adds a status panel under `rig`'s origin and returns it, or null without
## a rig. `place` puts it at the head point each frame.
static func add_status_panel(rig: Node3D) -> StatusPanel:
	if rig == null:
		return null
	var panel: StatusPanel = StatusPanel.new()
	rig.add_child(panel)
	return panel


## The recentred head point in the rig's space: the eye point the cockpit
## frame was built around. The ship's centre sits there (`HeadRecentre`).
static func head_point(recentre: HeadRecentre) -> Transform3D:
	return recentre.offset.affine_inverse()


## Puts `frame` and `panel` (either may be null) at the head point, so the
## head turns inside them and only a recentre moves them, both together.
static func place(recentre: HeadRecentre, frame: CockpitFrame, panel: StatusPanel) -> void:
	var at: Transform3D = head_point(recentre)
	if frame != null:
		frame.transform = at
	if panel != null:
		panel.transform = StatusPanel.rig_transform(at)


## Hands `panel` this frame's values from `ship`, a copy of the latest ship
## state; the panel never sees the session itself (ARC-3).
static func show_ship(panel: StatusPanel, ship: ShipState, preset_number: int,
		preset_name: String, build: String, delta_seconds: float) -> void:
	var boost: String = ""
	if ship.afterburner_active:
		boost = StatusPanel.BOOST_ON
	elif ship.afterburner_locked:
		boost = StatusPanel.BOOST_RECHARGING
	var energy_fraction: float = ship.energy / ship.max_energy if ship.max_energy > 0.0 else 0.0
	panel.show_values(preset_number, preset_name, ship.velocity.length(),
		energy_fraction, boost, build)
	panel.advance(delta_seconds)
