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
// On top lies a physically based surface per theme (#1292, GFX-2,
// `LevelWallMaterial`): value noise in world space, projected on the three
// axis planes and blended by the normal (triplanar, so the boxes need no UVs),
// varies colour and roughness and dents the normal; a share of the plates is
// bare metal; plate edges are chamfered in the normal so seams read as cut
// edges. With every strength at 0 the walls draw exactly as before. Noise and
// bevels fade out where they get too small on screen, like the plating, so
// nothing shimmers far away.
// A material can also carry all three tints and pick one per face by the same
// rule (`tint_by_kind`, #1383): a box of the mine is then one surface, one
// draw call, for its walls and frames together, instead of one per kind.
// Ambient light is the shader's own, not the environment's (#1400, GFX-5):
// albedo times `ambient_light`, the look's global ambient, or, when
// `baked_ambient` is set, times the box's ambient baked into each vertex
// (`AmbientBake`, in CUSTOM0), so each room has its own mood at no cost per
// frame. Godot adds ambient the same way (albedo, none on metal), so with the
// global value the walls draw as before.
// After the reactor dies the walls take an emergency look (#1454, GFX-6,
// `MeltdownWalls`): a dim warning glow that pulses slowly, the ambient turned
// towards a warning hue and the guide strips in an alert colour, dimming with
// the pulse. One uniform, `meltdown`, carries it all, set once a frame from
// the time since the death; its default draws the walls exactly as before.
shader_type spatial;
render_mode ambient_light_disabled;

// The tint of every face, or of the walls only when `tint_by_kind` is set.
uniform vec3 tint : source_color = vec3(0.16, 0.15, 0.14);
uniform bool tint_by_kind = false;
uniform vec3 floor_tint : source_color = vec3(0.22, 0.19, 0.15);
uniform vec3 ceiling_tint : source_color = vec3(0.1, 0.11, 0.13);
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
// Surface per theme (`LevelWallMaterial`); these defaults are its NEUTRAL values.
uniform float noise_scale = 1.0;
uniform float albedo_noise = 0.0;
uniform float roughness_noise = 0.0;
uniform float metallic_value = 0.0;
uniform float metal_share = 0.0;
uniform float metal_roughness = 0.5;
uniform float normal_strength = 0.0;
uniform float bevel_strength = 0.0;
uniform float bevel_width = 0.05;
uniform float triplanar_sharpness = 4.0;
// Only the bevels along box edges glow (`LevelLook.bevel_material`, #1323);
// on the walls this stays black.
uniform vec3 glow : source_color = vec3(0.0);
// Guide light strips (#1463) are drawn in the bevels' surface with their glow
// in the vertex colour, black on the bevels. Every surface with this above 0
// must carry vertex colours: without them COLOR reads white.
uniform float strip_energy = 0.0;
// Linear and energy applied, as the renderer works out the environment's.
uniform vec3 ambient_light = vec3(0.0);
uniform bool baked_ambient = false;
// (ramp 0..1, wall emission, strip brightness), from `MeltdownWalls.amount`.
uniform vec3 meltdown = vec3(0.0, 0.0, 1.0);
uniform vec3 meltdown_glow : source_color = vec3(0.0);
// A hue at full brightness: each box keeps its own ambient's brightness.
uniform vec3 meltdown_ambient : source_color = vec3(1.0);
uniform float meltdown_ambient_shift = 0.0;
uniform vec3 meltdown_strip : source_color = vec3(1.0);

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 ambient;
varying vec3 strip_glow;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 calm = baked_ambient ? CUSTOM0.rgb : ambient_light;
	float peak = max(calm.r, max(calm.g, calm.b));
	ambient = mix(calm, meltdown_ambient * peak, meltdown.x * meltdown_ambient_shift);
	strip_glow = COLOR.rgb * strip_energy;
	// Only strip vertices are coloured; the rest of a bevel is black and stays so.
	float strip = step(1e-4, max(COLOR.r, max(COLOR.g, COLOR.b)));
	strip_glow = mix(strip_glow, meltdown_strip * strip * strip_energy, meltdown.x) * meltdown.z;
}

// A steady value in 0..1 for each plate, so neighbouring plates differ a little.
float plate_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

// A value in 0..1 per lattice point; sin-free, so it holds up at the large
// world coordinates of a mine on a phone GPU.
float lattice_hash(vec2 p) {
	p = 50.0 * fract(p * 0.3183099 + vec2(0.71, 0.113));
	return fract(p.x * p.y * (p.x + p.y));
}

// Value noise and its two derivatives: (value, d/dx, d/dy).
vec3 value_noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = lattice_hash(i);
	float b = lattice_hash(i + vec2(1.0, 0.0));
	float c = lattice_hash(i + vec2(0.0, 1.0));
	float d = lattice_hash(i + vec2(1.0, 1.0));
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
			du * vec2(b - a + k * u.y, c - a + k * u.x));
}

// Three octaves of value noise, centred on 0, with derivatives per noise unit.
// `footprint` is how many noise units a pixel covers: an octave fades out
// before its blotches shrink under about three pixels.
vec3 wear(vec2 x, float footprint) {
	vec3 sum = vec3(0.0);
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int octave = 0; octave < 3; octave++) {
		float keep = 1.0 - smoothstep(0.15, 0.35, footprint * frequency);
		vec3 n = value_noise(x * frequency);
		sum += amplitude * keep * vec3(n.x - 0.5, n.yz * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return sum / 0.875;
}

void fragment() {
	vec3 facing = abs(world_normal);
	// The first axis is a horizontal one, so long wall plates lie level.
	vec2 along = world_position.xy;
	vec3 axis_u = vec3(1.0, 0.0, 0.0);
	vec3 axis_v = vec3(0.0, 1.0, 0.0);
	if (facing.x >= facing.y && facing.x >= facing.z) {
		along = world_position.zy;
		axis_u = vec3(0.0, 0.0, 1.0);
	} else if (facing.y >= facing.z) {
		along = world_position.xz;
		axis_v = vec3(0.0, 0.0, 1.0);
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

	vec3 unit_normal = normalize(world_normal);
	// Height slope along the surface, in world axes, for the light only.
	vec3 slope = vec3(0.0);
	float grain = 0.0;
	if (albedo_noise + roughness_noise + normal_strength > 0.0) {
		vec3 weight = pow(facing, vec3(triplanar_sharpness));
		weight /= weight.x + weight.y + weight.z;
		vec3 p = world_position / noise_scale;
		float footprint = length(fwidth(p));
		// Axis-aligned faces use one projection; the others are skipped whole.
		if (weight.x > 0.01) {
			vec3 n = wear(p.zy, footprint);
			grain += weight.x * n.x;
			slope += weight.x * vec3(0.0, n.z, n.y);
		}
		if (weight.y > 0.01) {
			vec3 n = wear(p.xz, footprint);
			grain += weight.y * n.x;
			slope += weight.y * vec3(n.y, 0.0, n.z);
		}
		if (weight.z > 0.01) {
			vec3 n = wear(p.xy, footprint);
			grain += weight.z * n.x;
			slope += weight.z * vec3(n.y, n.z, 0.0);
		}
		slope *= normal_strength;
	}
	if (bevel_strength > 0.0) {
		// Each plate rises from its seams over `bevel_width`: the slope points
		// into the plate from the nearer edge on each axis.
		vec2 side = sign(0.5 - fract(cell));
		vec2 ramp = 1.0 - smoothstep(seam_width * 0.5, seam_width * 0.5 + bevel_width, to_seam);
		vec2 bevel = side * ramp * bevel_strength * detail;
		slope += bevel.x * axis_u + bevel.y * axis_v;
	}
	bool metal = plate_hash(floor(cell) + vec2(17.0, 31.0)) < metal_share;

	vec3 face_tint = tint_by_kind ? floor_tint * kind.x + tint * kind.y + ceiling_tint * kind.z : tint;
	vec3 base = face_tint * plate_tone * seam_tone * (1.0 + albedo_noise * 2.0 * grain);
	vec3 albedo = clamp(base * mix(1.0, line_factor, on_line), vec3(0.0), vec3(1.0));
	ALBEDO = albedo;
	float rough = metal ? metal_roughness : roughness_value;
	ROUGHNESS = clamp(rough + roughness_noise * 2.0 * grain, 0.05, 1.0);
	float metallic = metal ? metallic_value : 0.0;
	METALLIC = metallic;
	vec3 bent = normalize(unit_normal - (slope - dot(slope, unit_normal) * unit_normal));
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	// VERTEX is the view-space position here, so its length is the distance.
	EMISSION = glow + strip_glow + albedo * (1.0 - metallic) * ambient + meltdown_glow * meltdown.y;
	FOG = vec4(fog_color, 1.0 - exp(-fog_density * length(VERTEX)));
}
