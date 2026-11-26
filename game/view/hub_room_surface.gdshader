// A worn surface of the home base room (#1369, `HubRoomParts`, GFX-2): the
// material's colour with darker, rougher worn patches, panel seams, and bare
// metal along a box's edges so the edges catch the room's lights, as the
// level walls and cockpit did (#1292, #1306). No texture: everything is worked
// out from the position on the part, in metres, so one material serves parts
// of any size and the pattern does not stretch.
shader_type spatial;

// The part's size in metres (set per part), and 1 when it is a box: the edge
// band is measured from its faces, which only a box's are.
instance uniform vec3 part_size = vec3(1.0);
instance uniform float edge_on = 0.0;

#include "res://view/hub_room_wear.gdshaderinc"

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
	piece_size = part_size;
	piece_box = edge_on;
}
