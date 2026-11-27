// Cockpit glass (#1306, #1459, GFX-2): what the canopy does to the light
// coming through it. It multiplies the view by `filter_color`, the file's
// transmission times its near-neutral tint, so the mine keeps its own
// brightness, colours and contrast. The glass of #1306 mixed a light blue over
// the view instead; on a dark mine that added a haze, a veil that flattened the
// contrast and coloured everything (#1459).
//
// The faint edge reflection that says "glass" is the next pass,
// `cockpit_glass_reflection.gdshader`.
//
// The factor is linear, not a source colour: 0.95 lets 95 percent through.
// Unshaded and not fogged: the cockpit is inside the ship.
shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_never;

uniform vec3 filter_color = vec3(0.95, 0.95, 0.95);

void fragment() {
	ALBEDO = filter_color;
}
