// The canopy's faint edge reflection (#1306, #1459, GFX-2), drawn after the
// glass filter (`cockpit_glass.gdshader`) and added to the view.
//
// Fresnel reflection grows as the line of sight grazes the glass. The glass
// is drawn on a sphere round the eye point, which every line of sight meets
// square on, but a real canopy's curve is flatter than that sphere and is
// grazed more the farther from straight ahead one looks. So the reflection
// follows Schlick's curve over the fraction of the way to the window's edge:
// none straight ahead, and `fresnel` at the edge.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_never;

uniform vec3 fresnel_color : source_color = vec3(0.75, 0.85, 1.0);
// Light the reflection adds at the window's edge, as a fraction of its colour.
uniform float fresnel = 0.0;
uniform float fresnel_power = 6.0;
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
	// Premultiplied into the colour, so the sum is the same whichever factor
	// the add blend gives the source.
	ALBEDO = fresnel_color * reflection;
	ALPHA = 1.0;
}
