// A robot's surface (#661, `RobotSkin`): its type's colour with a pattern in
// an accent colour, and a face plate on its forward (-z) side so which way it
// points reads at a glance. No texture: the pattern is worked out from the
// position in the robot's own frame, so it is continuous across the body and
// its parts and turns with the robot.
//
// The hit flash, damage dim and wind-up glow of #604 are applied after the
// pattern, so they show over it: `brightness` dims everything, `flash` mixes
// the whole surface towards `flash_color`, and `energy` scales the emission.
shader_type spatial;

// 0 plain, 1 rings, 2 chevrons, 3 checks, 4 bands, 5 stripes, 6 grid, 7 dots;
// the order of `RobotSkin.PATTERNS`.
uniform int pattern = 0;
uniform float pattern_scale = 3.0;
uniform float pattern_width = 0.3;
uniform vec3 base_color : source_color = vec3(0.8);
uniform vec3 accent_color : source_color = vec3(0.2);
uniform vec3 face_color : source_color = vec3(1.0);
// The face plate covers the robot where its local z is below -face_depth.
uniform float face_depth = 4.0;
uniform vec3 face_axis = vec3(0.0, 0.0, -1.0);
uniform float brightness = 1.0;
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float energy = 1.0;

// The part's size and offset in the robot's frame, so a part's vertex can be
// placed in the robot's frame (set per part by `RobotView`).
instance uniform vec3 part_size = vec3(1.0);
instance uniform vec3 part_offset = vec3(0.0);

varying vec3 robot_position;

void vertex() {
	robot_position = VERTEX * part_size + part_offset;
}

// 1 on a line of `width` (a share of each cell) along `value`, 0 off it,
// softened by the screen-space change so far lines do not shimmer (GFX-2).
float line(float value, float width) {
	float to_centre = abs(fract(value) - 0.5);
	float blur = max(fwidth(value), 1e-4);
	return 1.0 - smoothstep(width * 0.5 - blur, width * 0.5 + blur, 0.5 - to_centre);
}

float mark(vec3 p) {
	vec3 q = p * pattern_scale;
	if (pattern == 1) {
		return line(length(q.xz), pattern_width);
	} else if (pattern == 2) {
		return line(q.z + abs(q.x), pattern_width);
	} else if (pattern == 3) {
		vec3 cell = floor(q);
		return mod(cell.x + cell.y + cell.z, 2.0);
	} else if (pattern == 4) {
		return line(q.z, pattern_width);
	} else if (pattern == 5) {
		return line(q.x, pattern_width);
	} else if (pattern == 6) {
		return max(max(line(q.x, pattern_width), line(q.y, pattern_width)), line(q.z, pattern_width));
	} else if (pattern == 7) {
		vec3 to_dot = fract(q) - 0.5;
		float blur = max(fwidth(length(q)), 1e-4);
		return 1.0 - smoothstep(pattern_width * 0.5 - blur, pattern_width * 0.5 + blur, length(to_dot));
	}
	return 0.0;
}

void fragment() {
	vec3 surface = mix(base_color, accent_color, mark(robot_position));
	float ahead = dot(robot_position, face_axis);
	float blur = max(fwidth(ahead), 1e-4);
	surface = mix(surface, face_color, smoothstep(face_depth - blur, face_depth + blur, ahead));
	surface = mix(surface * brightness, flash_color, flash);
	ALBEDO = clamp(surface, vec3(0.0), vec3(1.0));
	// Emissive as well as shaded, so the colours read in a dark tunnel.
	EMISSION = ALBEDO * energy;
	ROUGHNESS = 0.7;
}
