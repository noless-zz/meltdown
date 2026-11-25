class_name MapPlacement
extends RefCounted

## Puts the map hologram where the pilot chose (#1321, MAP-1): in the hand, as
## before, or mounted at the active cockpit's `map_mount` spot on the side away
## from the status panel, and turned with the ship or not (`MapChoice`).
##
## The cockpit frame is the holder because it is the node placed at the eye
## point and moved by the view guard, so the mounted map stays put in the
## cockpit as the head turns, like the panel. Without a frame (a scene with no
## cockpit) the map stays in the hand. Only the hologram node moves: nothing
## here reads or writes simulation state (ARC-3, CMF-6, MP-2).

## The cockpit frame's node name under the rig (`CockpitFrame._init`).
const FRAME_NAME: String = "CockpitFrame"


## Turns `hologram` as `MapChoice.current_turn` says and, when the cockpit
## place is chosen and `rig` has a cockpit frame, mounts it there for the
## panel's corner. Returns whether it is mounted; false leaves the hand to the caller.
static func apply(hologram: MapHologram, rig: Node) -> bool:
	hologram.set_follows_ship(MapChoice.current_turn == MapChoice.TURN_FOLLOWS)
	if MapChoice.current_place != MapChoice.PLACE_COCKPIT:
		return false
	var frame: CockpitFrame = cockpit_frame(rig)
	if frame == null or frame.spec == null:
		return false
	var mount: CockpitMapMount = frame.spec.map_mount
	hologram.mount_on(frame, mount.spot(PanelCorner.current), mount.size_m)
	return true


## The rig's cockpit frame, or null without one.
static func cockpit_frame(rig: Node) -> CockpitFrame:
	return rig.get_node_or_null(FRAME_NAME) as CockpitFrame if rig != null else null
