// The walls of every level (#609, #660, `LevelLook`): a lit surface in one
// tint, plated in panels with dark seams, under a grid of lines fixed in
// world space, so the eye has detail to judge depth and motion by. No
// texture: everything is worked out from the position, on the two axes along
// the surface (the third is the one the normal is nearest).
// Floor, wall and ceiling are told apart by the face normal here, with the
// same 45 degree rule as `LevelLook.surface_class`, and each kind gets its own
// plate size, shape and row offset, so up and down read from the pattern as
// well as the tint (#660). Levels are drawn unrotated, so world space is the
// level's frame and plates line up across the separate boxes of the test tunnel.
// Fog is done here, on the walls only, rather than in the environment: on the
// desktop smoke run environment fog cost about a fifth of the frame rate,
// this costs nothing measurable (#609). Far walls darken towards the
// near-black fog colour.
shader_type spatial;

uniform vec3 tint : source_color = vec3(0.16, 0.15, 0.14);
uniform float roughness_value = 0.9;
uniform float grid_spacing = 2.0;
uniform float line_width = 0.06;
uniform float line_factor = 2.2;
// Per face kind, in the order floor, wall, ceiling.
uniform vec3 plate_size = vec3(1.0, 1.0, 0.5);
uniform vec3 plate_aspect = vec3(1.0, 2.0, 4.0);
uniform vec3 plate_stagger = vec3(0.0, 0.5, 0.0);
uniform float seam_width = 0.03;
uniform float plate_contrast = 0.12;
uniform float floor_min_up = 0.7071;
uniform vec3 fog_color : source_color = vec3(0.01, 0.012, 0.016);
uniform float fog_density = 0.035;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// A steady value in 0..1 for each plate, so neighbouring plates differ a little.
float plate_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 facing = abs(world_normal);
	// The first axis is a horizontal one, so long wall plates lie level.
	vec2 along = world_position.xy;
	if (facing.x >= facing.y && facing.x >= facing.z) {
		along = world_position.zy;
	} else if (facing.y >= facing.z) {
		along = world_position.xz;
	}
	// Distance to the nearest grid line on each axis, in metres.
	vec2 to_line = abs(fract(along / grid_spacing + 0.5) - 0.5) * grid_spacing;
	float nearest = min(to_line.x, to_line.y);
	// Soften by the screen-space change so far lines do not shimmer.
	float blur = max(fwidth(nearest), 1e-4);
	float on_line = 1.0 - smoothstep(line_width * 0.5 - blur, line_width * 0.5 + blur, nearest);

	float up = normalize(world_normal).y;
	// One of (1,0,0) floor, (0,1,0) wall, (0,0,1) ceiling, to pick each kind's values.
	vec3 kind = vec3(0.0, 1.0, 0.0);
	if (up > floor_min_up) {
		kind = vec3(1.0, 0.0, 0.0);
	} else if (up < -floor_min_up) {
		kind = vec3(0.0, 0.0, 1.0);
	}
	float size = dot(plate_size, kind);
	vec2 plate = vec2(size * dot(plate_aspect, kind), size);
	vec2 cell = along / plate;
	// Fade plate detail out where a plate covers under about three pixels: the
	// plating is the filter, so it does not shimmer far away (#660).
	float detail = 1.0 - smoothstep(0.15, 0.35, max(fwidth(cell.x), fwidth(cell.y)));
	cell.x += dot(plate_stagger, kind) * floor(cell.y);
	vec2 to_seam = (0.5 - abs(fract(cell) - 0.5)) * plate;
	float seam_nearest = min(to_seam.x, to_seam.y);
	float seam_blur = max(fwidth(seam_nearest), 1e-4);
	float on_seam = 1.0 - smoothstep(seam_width * 0.5 - seam_blur, seam_width * 0.5 + seam_blur, seam_nearest);
	float plate_tone = 1.0 + plate_contrast * (plate_hash(floor(cell)) - 0.5) * detail;
	float seam_tone = 1.0 - plate_contrast * 2.0 * on_seam * detail;

	ALBEDO = clamp(tint * plate_tone * seam_tone * mix(1.0, line_factor, on_line), vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness_value;
	// VERTEX is the view-space position here, so its length is the distance.
	FOG = vec4(fog_color, 1.0 - exp(-fog_density * length(VERTEX)));
}
