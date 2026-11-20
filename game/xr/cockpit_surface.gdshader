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

varying vec2 face_uv;
varying vec2 face_size;

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

	vec3 color = base_color * tone;
	if (edge_width_m > 0.0) {
		vec2 from_edge = min(face_uv, 1.0 - face_uv) * face_size;
		float far_away = 1e3;
		float nearest = min(mix(far_away, from_edge.x, edge_axis.x), mix(far_away, from_edge.y, edge_axis.y));
		float edge = 1.0 - smoothstep(edge_width_m, edge_width_m + pixel_m, nearest);
		color = mix(color, edge_color, edge);
	}
	ALBEDO = color;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	EMISSION = color * glow;
}
