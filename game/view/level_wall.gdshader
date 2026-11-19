// The walls of every level (#609, `LevelLook`): a lit surface in one tint with
// a grid of lines fixed in world space, so the eye has detail to judge depth
// and motion by. No texture: the lines are worked out from the position, on
// the two axes along the surface (the third is the one the normal is nearest).
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
uniform vec3 fog_color : source_color = vec3(0.01, 0.012, 0.016);
uniform float fog_density = 0.035;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 facing = abs(world_normal);
	vec2 along = world_position.xy;
	if (facing.x >= facing.y && facing.x >= facing.z) {
		along = world_position.yz;
	} else if (facing.y >= facing.z) {
		along = world_position.xz;
	}
	// Distance to the nearest grid line on each axis, in metres.
	vec2 to_line = abs(fract(along / grid_spacing + 0.5) - 0.5) * grid_spacing;
	float nearest = min(to_line.x, to_line.y);
	// Soften by the screen-space change so far lines do not shimmer.
	float blur = max(fwidth(nearest), 1e-4);
	float on_line = 1.0 - smoothstep(line_width * 0.5 - blur, line_width * 0.5 + blur, nearest);
	ALBEDO = clamp(tint * mix(1.0, line_factor, on_line), vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness_value;
	// VERTEX is the view-space position here, so its length is the distance.
	FOG = vec4(fog_color, 1.0 - exp(-fog_density * length(VERTEX)));
}
