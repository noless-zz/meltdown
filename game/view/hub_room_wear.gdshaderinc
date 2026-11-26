// The worn surface of the home base room's parts (#1369, GFX-2), shared by
// `hub_room_surface.gdshader` (one part per mesh, its size an instance
// uniform) and `hub_room_detail.gdshader` (#1397: many parts merged into one
// mesh, each vertex carrying its part's values), so a merged detail wears the
// same way as a part of its own. The including shader's vertex() fills the
// four varyings below.

uniform vec3 albedo : source_color = vec3(0.5);
uniform float metallic = 0.0;
uniform float roughness = 0.8;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// Share of the surface in worn patches, 0..1.
uniform float wear = 0.0;
// How strongly a box's edges are worn to bare metal, 0..1.
uniform float edge = 0.0;
// Panel size in metres; 0 draws no seams.
uniform float panel_m = 0.0;
// Width of the worn band along an edge, and of a seam, in metres.
const float EDGE_M = 0.025;
const float SEAM_M = 0.008;

// Position and normal on the part, in metres from its centre; the part's size;
// 1 when it is a box, whose edges are worn bare.
varying vec3 local_position;
varying vec3 local_normal;
varying vec3 piece_size;
varying float piece_box;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// 1 on a seam line across `value` (metres / panel), softened by its screen
// change so far seams do not shimmer.
float seam(float value, float width) {
	float to_line = abs(fract(value + 0.5) - 0.5);
	float blur = max(fwidth(value), 1e-4);
	return 1.0 - smoothstep(width - blur, width + blur, to_line);
}

void fragment() {
	vec3 p = local_position;
	// Distance to the nearest face on each axis: the smallest is the face being
	// drawn, the middle one is the distance to its nearest edge.
	vec3 to_face = piece_size * 0.5 - abs(p);
	float lo = min(to_face.x, min(to_face.y, to_face.z));
	float hi = max(to_face.x, max(to_face.y, to_face.z));
	float to_edge = to_face.x + to_face.y + to_face.z - lo - hi;
	float blur = max(fwidth(to_edge), 1e-4);
	float bare = edge * piece_box * (1.0 - smoothstep(EDGE_M - blur, EDGE_M + blur, to_edge));

	float n = noise(p * 2.1) * 0.7 + noise(p * 8.3) * 0.3;
	float worn = wear > 0.0 ? smoothstep(1.0 - wear - 0.12, 1.0 - wear + 0.12, n) : 0.0;

	float seams = 0.0;
	if (panel_m > 0.0) {
		// A seam runs across the face, never along its normal, or the whole face would darken.
		vec3 across = vec3(1.0) - abs(normalize(local_normal));
		vec3 q = p / panel_m;
		float width = SEAM_M / panel_m;
		seams = max(seam(q.x, width) * across.x, max(seam(q.y, width) * across.y, seam(q.z, width) * across.z));
	}

	vec3 base = albedo * mix(1.0, 0.8, worn) * (1.0 - 0.5 * seams);
	ALBEDO = mix(base, max(albedo * 1.7, vec3(0.55)), bare);
	METALLIC = mix(metallic, 0.85, bare);
	ROUGHNESS = clamp(mix(roughness + 0.18 * worn, 0.3, bare), 0.05, 1.0);
	EMISSION = emission_color * emission_energy;
}
