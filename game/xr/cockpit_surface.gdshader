// Cockpit surface (#659, GFX-2, GFX-4): a lit interior tone with simple panel
// lines and optional rivets, an edge highlight along a shape's long edges, and
// a little self-light so the frame never reads black on black in a dark mine.
//
// Every value comes from the cockpit data file through `CockpitLook`; nothing
// is imported art. The pattern is computed, not sampled, so there is no
// texture to mipmap: instead it fades to the plain tone wherever a panel
// covers too few pixels to draw it cleanly, which is what a mipmap would do
// and keeps it from shimmering (#659 criterion 3).
//
// The frame is drawn from unit quads and boxes, one instance per 10 degree
// cell, scaled per instance. The pattern is laid out in metres across each
// face, with a whole number of panels per cell, so cells line up. Cells
// overlap their neighbours by a few percent; inside that margin every piece
// draws a panel line, so both overlapping pieces show the same thing there.
//
// Since #1306 each surface is physically based (`CockpitFinish`): its own
// roughness and metalness, panel seams pressed in and bolts raised in the
// shading normal, so the headlight and bolt lights catch their edges, and
// worn patches rubbed toward bare metal. The normal is bent from the slope of
// a computed height, so there is no normal map either. With every finish
// value neutral the surface draws exactly as before.
//
// Not fogged: the cockpit is inside the ship, like the status panel.
shader_type spatial;
render_mode blend_mix, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 base_color : source_color = vec3(0.3, 0.33, 0.38);
uniform vec3 edge_color : source_color = vec3(0.6, 0.7, 0.8);
// Width of the edge highlight, metres; 0 draws none.
uniform float edge_width_m = 0.0;
// Which face directions get the edge highlight: x across the cell's yaw
// edges, y across its pitch edges. (0, 0) for the shell.
uniform vec2 edge_axis = vec2(0.0, 0.0);
// Fraction of the surface's own colour it gives off with no light at all.
uniform float glow = 0.4;
// Panel size, metres.
uniform float pattern_scale_m = 0.1;
// How much darker a panel line is, and how much lighter a rivet, 0..1.
uniform float pattern_contrast = 0.1;
// Rivet diameter as a fraction of a panel; 0 draws none.
uniform float rivet_size = 0.0;
// Fraction of each face edge that overlaps a neighbour (CockpitFrame.OVERLAP).
uniform float overlap_margin = 0.0238;
// The surface's finish (#1306); the defaults are the look before it.
uniform float roughness = 0.75;
uniform float metallic = 0.0;
// Depth of the seams and height of the bolts in the shading normal, metres.
uniform float seam_depth_m = 0.0;
uniform float bolt_height_m = 0.0;
// Share of the surface worn toward bare metal, and the size of a worn patch.
uniform float wear = 0.0;
uniform float wear_scale_m = 0.05;
// The dash: each instance's colour scales the base colour, and its custom
// data is the colour of the lamp it carries (`CockpitDash`).
uniform bool instance_tint = false;

// How bright a dash lamp glows; it lights nothing else (GFX-4).
const float LAMP_ENERGY = 1.5;

varying vec2 face_uv;
varying vec2 face_size;
varying vec3 tint;
varying vec3 lamp;
varying vec2 wear_offset;

void vertex() {
	// The instance's scale along each local axis is its size in metres.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 n = abs(NORMAL);
	if (n.z > 0.5) {
		face_uv = VERTEX.xy + 0.5;
		face_size = scale.xy;
	} else if (n.x > 0.5) {
		face_uv = VERTEX.zy + 0.5;
		face_size = scale.zy;
	} else {
		face_uv = VERTEX.xz + 0.5;
		face_size = scale.xz;
	}
	tint = vec3(1.0);
	lamp = vec3(0.0);
	if (instance_tint) {
		tint = COLOR.rgb;
		lamp = INSTANCE_CUSTOM.rgb;
	}
	// Each piece wears differently, so the cells do not repeat one patch.
	wear_offset = vec2(float(INSTANCE_ID) * 7.31, float(INSTANCE_ID) * 3.17);
}

float hash2(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// Smooth value noise, 0..1, one cell per unit.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Distance in metres from `uv` to the nearest panel border along one axis,
// with `size` metres of face and panels of about `scale` metres between the
// overlap margins. Inside a margin it is 0: a line.
float border_distance(float uv, float size, float scale) {
	float inner = 1.0 - 2.0 * overlap_margin;
	float t = (uv - overlap_margin) / inner;
	if (t <= 0.0 || t >= 1.0) {
		return 0.0;
	}
	float panels = max(1.0, round(size * inner / scale));
	float g = fract(t * panels);
	return min(g, 1.0 - g) * size * inner / panels;
}

void fragment() {
	vec2 metres = face_uv * face_size;
	vec2 pixel = fwidth(metres);
	float pixel_m = max(max(pixel.x, pixel.y), 1e-6);
	// Fade the pattern out where a panel spans fewer than about ten pixels.
	float detail = 1.0 - smoothstep(0.08, 0.2, pixel_m / pattern_scale_m);
	float contrast = pattern_contrast * detail;

	vec2 d = vec2(border_distance(face_uv.x, face_size.x, pattern_scale_m),
		border_distance(face_uv.y, face_size.y, pattern_scale_m));
	float line_half = pattern_scale_m * 0.035;
	float line = 1.0 - smoothstep(line_half, line_half + pixel_m, min(d.x, d.y));

	float rivet = 0.0;
	if (rivet_size > 0.0) {
		// A rivet near each panel corner, inset from both borders.
		vec2 inset = d - vec2(pattern_scale_m * 0.15);
		float radius = rivet_size * pattern_scale_m * 0.5;
		rivet = 1.0 - smoothstep(radius, radius + pixel_m, length(inset));
	}
	float tone = 1.0 - contrast * line + contrast * rivet * (1.0 - line);

	vec3 color = base_color * tint * tone;
	float rough = roughness;
	float metal = metallic;
	if (wear > 0.0) {
		float n = value_noise(metres / wear_scale_m + wear_offset) * 0.65
			+ value_noise(metres / wear_scale_m * 2.7 + wear_offset.yx) * 0.35;
		float worn = smoothstep(1.0 - wear * 0.7, 1.05 - wear * 0.6, n) * detail;
		color *= 1.0 + 0.35 * worn;
		rough = mix(rough, rough * 0.45, worn);
		metal = mix(metal, 1.0, worn * 0.6);
	}
	if (seam_depth_m > 0.0 || bolt_height_m > 0.0) {
		// A height in metres: seams pressed in with a bevel as wide as the
		// line, bolts domed. It fades out with the pattern, so it never shimmers.
		float seam = 1.0 - smoothstep(line_half, line_half * 2.5, min(d.x, d.y));
		float dome = 0.0;
		if (rivet_size > 0.0) {
			float radius = rivet_size * pattern_scale_m * 0.5;
			vec2 inset = d - vec2(pattern_scale_m * 0.15);
			dome = 1.0 - smoothstep(0.0, radius, length(inset));
			dome = dome * dome * (1.0 - seam);
		}
		float height = (bolt_height_m * dome - seam_depth_m * seam) * detail;
		// Bump from the screen-space slope of the height (Mikkelsen 2010).
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 slope = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
		vec3 bent = abs(det) * NORMAL - slope;
		if (dot(bent, bent) > 1e-20) {
			NORMAL = normalize(bent);
		}
	}
	if (edge_width_m > 0.0) {
		vec2 from_edge = min(face_uv, 1.0 - face_uv) * face_size;
		float far_away = 1e3;
		float nearest = min(mix(far_away, from_edge.x, edge_axis.x), mix(far_away, from_edge.y, edge_axis.y));
		float edge = 1.0 - smoothstep(edge_width_m, edge_width_m + pixel_m, nearest);
		color = mix(color, edge_color, edge);
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.3;
	EMISSION = color * glow + lamp * LAMP_ENERGY;
}
