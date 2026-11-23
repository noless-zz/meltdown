extends RefCounted

## A destroyed robot's blast (#1309, owner's playtest of 23 Nov, GFX-6, CMB-3):
## it has depth (a see-through shell and a hot core that shrinks first, added
## onto the scene so robots behind still show, and sparks), fades quickly, and
## at point-blank range keeps clear of the eye instead of blanking the view.

const EPSILON: float = 1e-4


func _burst(at: Vector3) -> Array[Dictionary]:
	return [{"position": at, "radius": 1.0, "start": 0.0, "id": "drone"}] as Array[Dictionary]


func test_the_blast_is_added_onto_the_scene_not_painted_over_it() -> String:
	var code: String = (load("res://view/blast_glow.gdshader") as Shader).code
	for mode: String in ["blend_add", "unshaded", "depth_draw_never", "cull_back"]:
		if not mode in code:
			return "the blast shader lacks %s" % mode
	return ""


func test_a_far_blast_swells_while_its_core_shrinks_and_both_fade() -> String:
	var bursts: RobotBursts = RobotBursts.new()
	var effects: Dictionary = RobotLook.DEFAULT_EFFECTS
	var seconds: float = effects["burst_seconds"]
	bursts.set_viewer(Vector3(0.0, 0.0, 50.0))
	bursts.show_bursts(_burst(Vector3.ZERO), effects, seconds * 0.1)
	var shell_early: float = bursts.shell(0).scale.x
	var core_early: float = bursts.core(0).scale.x
	var strength_early: float = (bursts.shell(0).material_override as ShaderMaterial).get_shader_parameter("strength")
	bursts.show_bursts(_burst(Vector3.ZERO), effects, seconds * 0.3)
	var result: String = ""
	if bursts.shell(0).scale.x <= shell_early or bursts.core(0).scale.x >= core_early:
		result = "the shell did not swell or the core did not shrink"
	var strength_late: float = (bursts.shell(0).material_override as ShaderMaterial).get_shader_parameter("strength")
	if result == "" and strength_late >= strength_early:
		result = "the shell did not fade"
	bursts.show_bursts(_burst(Vector3.ZERO), effects, seconds * 0.5)
	if result == "" and bursts.core(0).visible:
		result = "the core outlived its share of the blast"
	if result == "" and bursts.sparks().shown().size() != 1:
		result = "the blast threw %d spark bursts, not one" % bursts.sparks().shown().size()
	bursts.free()
	return result


func test_a_point_blank_blast_keeps_clear_of_the_eye() -> String:
	var bursts: RobotBursts = RobotBursts.new()
	var effects: Dictionary = RobotLook.DEFAULT_EFFECTS
	var result: String = ""
	for distance: float in [0.3, 1.0, 2.0, 3.0]:
		bursts.set_viewer(Vector3(0.0, 0.0, distance))
		for share: float in [0.05, 0.3, 0.6, 0.9]:
			bursts.show_bursts(_burst(Vector3.ZERO), effects, float(effects["burst_seconds"]) * share)
			for node: MeshInstance3D in [bursts.shell(0), bursts.core(0)]:
				if node.visible and node.scale.x > distance - RobotBursts.NEAR_M + EPSILON:
					result = "at %.1f m a ball of %.2f m reaches the eye" % [distance, node.scale.x]
	if result == "" and bursts.visible_count() != 1:
		result = "the burst was not counted"
	bursts.set_viewer(Vector3(0.0, 0.0, 1.0))
	bursts.show_bursts(_burst(Vector3.ZERO), effects, 0.01)
	var near: float = (bursts.shell(0).material_override as ShaderMaterial).get_shader_parameter("strength")
	if result == "" and near > 0.25:
		result = "a blast at the pilot's nose is at strength %.2f" % near
	bursts.free()
	return result
