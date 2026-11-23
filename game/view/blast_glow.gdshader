// A glowing ball for blasts (#1309, GFX-6): added onto what is behind it, so
// it never hides a robot, and bright at its rim and faint in its middle, so it
// reads as a round shell with depth rather than a flat disc. Drawn on the
// blast's own sphere only: no full-screen pass.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.75, 0.35, 1.0);
// 0 hides the ball, 1 is full brightness.
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// How much of the middle is let through: 0 an even ball, 1 a rim only.
uniform float hollow : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = 1.0 - facing;
	float shell = mix(1.0, rim * rim * 0.85 + 0.15, hollow);
	ALBEDO = tint.rgb;
	ALPHA = clamp(strength * shell, 0.0, 1.0);
}
