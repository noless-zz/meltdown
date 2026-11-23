// Cockpit glass (#1306, GFX-2): the flat tint of the canopy plus a faint
// reflection toward the window's edge, so the glass reads as glass without
// hiding the view.
//
// Fresnel reflection grows as the line of sight grazes the glass. The glass
// is drawn on a sphere round the eye point, which every line of sight meets
// square on, but a real canopy's curve is flatter than that sphere and is
// grazed more the farther from straight ahead one looks. So the reflection
// follows Schlick's curve over the fraction of the way to the window's edge:
// none straight ahead, where `glass_tint_alpha` stays the whole opacity, and
// `fresnel` more at the edge.
//
// Unshaded and not fogged, like the flat tint before it: the cockpit is
// inside the ship.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.75, 0.85, 0.1);
uniform vec3 fresnel_color : source_color = vec3(0.75, 0.85, 1.0);
// Opacity the reflection adds at the window's edge.
uniform float fresnel = 0.0;
uniform float fresnel_power = 3.0;
// The window's half-angles, radians.
uniform vec2 window_half_angle = vec2(0.7, 0.5);

varying vec3 local;

void vertex() {
	// The glass mesh is built in the frame's space, eye at the origin.
	local = VERTEX;
}

void fragment() {
	float yaw = atan(local.x, -local.z);
	float pitch = atan(local.y, length(local.xz));
	vec2 toward_edge = abs(vec2(yaw, pitch)) / max(window_half_angle, vec2(1e-3));
	float edge = clamp(max(toward_edge.x, toward_edge.y), 0.0, 1.0);
	float reflection = fresnel * pow(edge, fresnel_power);
	float alpha = tint.a + reflection * (1.0 - tint.a);
	ALBEDO = mix(tint.rgb, fresnel_color, reflection / max(alpha, 1e-4));
	ALPHA = alpha;
}
