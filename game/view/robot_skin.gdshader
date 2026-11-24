// A robot's surface (#661, `RobotSkin`): its type's colour with a pattern in
// an accent colour, and a face plate on its forward (-z) side so which way it
// points reads at a glance. No texture: the pattern is worked out from the
// position in the robot's own frame, so it is continuous across the body and
// its parts and turns with the robot.
//
// The hit flash, damage dim and wind-up glow of #604 are applied after the
// pattern, so they show over it: `brightness` dims everything, `flash` mixes
// the whole surface towards `flash_color`, and `energy` scales the emission.
//
// With `lit_body` (#1307, `RobotFinish`) the body is metal the headlight
// shows instead: panel seams and worn patches worked out in the robot's frame,
// as the pattern is, and only the pattern's lines glow in the type colour, so
// in the dark the robot is seen by its eye and lines first (LGT-1).
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
uniform float lit_body = 0.0;
uniform vec3 metal_albedo : source_color = vec3(0.35);
uniform float metal_roughness = 0.45;
uniform float metal_metallic = 0.8;
uniform float panel_scale = 2.0;
uniform float panel_depth = 0.5;
uniform float wear = 0.25;

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

// Smooth value noise in 0..1, for worn patches without a texture (ARC-5).
float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(cell), hash3(cell + vec3(1, 0, 0)), u.x),
			mix(hash3(cell + vec3(0, 1, 0)), hash3(cell + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(cell + vec3(0, 0, 1)), hash3(cell + vec3(1, 0, 1)), u.x),
			mix(hash3(cell + vec3(0, 1, 1)), hash3(cell + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void lit_fragment(inout vec3 albedo, inout vec3 emission, inout float metallic, inout float roughness) {
	float lines = mark(robot_position);
	vec3 q = robot_position * panel_scale;
	float seam = max(max(line(q.x, 0.08), line(q.y, 0.08)), line(q.z, 0.08));
	float worn = wear * smoothstep(1.0 - wear, 1.0 - wear + 0.15, value_noise(robot_position * 6.0));
	vec3 metal = metal_albedo * (1.0 - panel_depth * seam);
	metal = mix(metal, min(metal * 1.6 + vec3(0.06), vec3(1.0)), worn);
	metal = mix(metal, accent_color, lines);
	float ahead = dot(robot_position, face_axis);
	float blur = max(fwidth(ahead), 1e-4);
	float face = smoothstep(face_depth - blur, face_depth + blur, ahead);
	metal = mix(metal, face_color, face);
	albedo = clamp(mix(metal * brightness, flash_color, flash), vec3(0.0), vec3(1.0));
	emission = mix(base_color * lines * (1.0 - face) * brightness, flash_color, flash) * energy;
	metallic = metal_metallic * (1.0 - 0.5 * seam) * (1.0 - 0.4 * worn);
	roughness = clamp(mix(metal_roughness, metal_roughness + 0.35, worn), 0.0, 1.0);
}

void fragment() {
	if (lit_body > 0.5) {
		vec3 albedo;
		vec3 emission;
		float metallic;
		float roughness;
		lit_fragment(albedo, emission, metallic, roughness);
		ALBEDO = albedo;
		EMISSION = emission;
		METALLIC = metallic;
		ROUGHNESS = roughness;
	} else {
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
}
