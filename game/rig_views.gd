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
## a rig. `place` puts it at the head point each frame, in the corner saved or
## asked for with `--panel=` (#752).
static func add_status_panel(rig: Node3D) -> StatusPanel:
	if rig == null:
		return null
	PanelCorner.from_launch()
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
	place_at(head_point(recentre), frame, panel)


## Puts `frame` and `panel` (either may be null) at `at`, in the rig's space.
static func place_at(at: Transform3D, frame: CockpitFrame, panel: StatusPanel) -> void:
	if frame != null:
		frame.transform = at
	if panel != null:
		panel.transform = StatusPanel.rig_transform(at)


## Places `comfort`'s frame and `panel` where its `ViewGuard` says for the
## head `camera` (#651): at the head point, unless the head has been lost
## from the window long enough or tracking was just regained. Also writes
## the `MELTDOWN_VIEW` line when that log is on. `ship` is a copy, read for
## its hull only. Without a camera or a frame it places as `place` does.
static func place_guarded(recentre: HeadRecentre, comfort: ComfortWiring, panel: StatusPanel,
		camera: Node3D, ship: ShipState, xr_running: bool) -> void:
	show_swivel(panel, comfort)
	var frame: CockpitFrame = comfort.cockpit_frame
	if camera == null or frame == null or frame.spec == null:
		place(recentre, frame, panel)
		return
	var tracked: bool = HeadRecentre.head_tracked() if xr_running else true
	var now_s: float = float(comfort.clock.call())
	var at: Transform3D = comfort.view_guard.update(head_point(recentre), camera.transform,
		tracked, frame.spec, now_s)
	place_at(at, frame, panel)
	if comfort.view_log.enabled:
		comfort.view_log.sample(now_s, ViewLog.values(comfort.view_guard, camera.transform,
			comfort.shake_offset, comfort.number, ship.hull, tracked, now_s))


## Tells `panel` whether `comfort`'s active preset has swivel-chair mode on
## (#792). Called from `place_guarded`, the one per-frame call that sees both
## the comfort wiring and the panel; it reads the preset only (ARC-3).
static func show_swivel(panel: StatusPanel, comfort: ComfortWiring) -> void:
	if panel != null:
		panel.preset_row.show_swivel(comfort.preset != null and comfort.preset.swivel_enabled)


## Hands `panel` this frame's values from `ship`, a copy of the latest ship
## state; the panel never sees the session itself (ARC-3). `level_source` is
## what the launch flies, as `LevelStart.source` holds it (#747).
static func show_ship(panel: StatusPanel, ship: ShipState, preset_number: int,
		preset_name: String, build: String, delta_seconds: float, level_source: String = "") -> void:
	var level: PackedStringArray = LevelStart.shown_level(level_source)
	panel.show_level(level[0], level[1])
	var boost: String = ""
	if ship.afterburner_active:
		boost = StatusPanel.BOOST_ON
	elif ship.afterburner_locked:
		boost = StatusPanel.BOOST_RECHARGING
	var energy_fraction: float = ship.energy / ship.max_energy if ship.max_energy > 0.0 else 0.0
	panel.show_values(preset_number, preset_name, ship.velocity.length(),
		energy_fraction, boost, build)
	panel.advance(delta_seconds)
