// The worn surface on the home base room's merged hangar details (#1397,
// `HubRoomDetails`, GFX-2, PRF-4). Pieces that share a material are one mesh,
// so an instance uniform cannot hold each piece's size; each vertex carries
// its piece's values instead: CUSTOM0 is the position on the piece and 1 on a
// box, CUSTOM1 the piece's size, CUSTOM2 the normal on the piece.
shader_type spatial;

#include "res://view/hub_room_wear.gdshaderinc"

void vertex() {
	local_position = CUSTOM0.xyz;
	piece_box = CUSTOM0.w;
	piece_size = CUSTOM1.xyz;
	local_normal = CUSTOM2.xyz;
}
