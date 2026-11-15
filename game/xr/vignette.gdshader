// Comfort vignette (CMF-1): darkens the edge of view by `strength`.
//
// Drawn as one quad placed straight in clip space, so it covers each eye's
// view whatever the headset's field of view, and it never reads the screen:
// no full-screen post-process pass, no screen texture (GFX-6 spirit, PRF-2).
// The owning node hides itself at strength 0, so presets without a vignette
// pay nothing.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 0 draws nothing; 1 leaves only the centre of view clear.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Width of the soft edge between clear and dark, in clip-space units.
uniform float softness : hint_range(0.01, 1.0) = 0.35;

varying vec2 clip_xy;

void vertex() {
	// A 2 by 2 quad: its corners land on the clip-space corners of each eye.
	clip_xy = VERTEX.xy;
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float radius = length(clip_xy);
	// At strength 1 the clear area shrinks to a radius of 0.35 of the
	// half-view; at small strengths it starts just outside the view corners.
	float clear_radius = mix(1.45, 0.35, strength);
	float dark = smoothstep(clear_radius, clear_radius + softness, radius);
	ALBEDO = vec3(0.0);
	ALPHA = dark * step(0.001, strength);
}
