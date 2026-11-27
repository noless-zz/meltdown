class_name HandsOverFade
extends RefCounted

## Draws the pilot's controllers over the dark fade while an end screen or the
## shaft choice holds the view dark (#1468, CRW-2, RUN-1, CMF-8, PLT-5), so the
## pilot can see the hands that point at the panel and press its buttons.
##
## The rule is render priority, as for the aim ray and the screens' words: the
## fade is a transparent quad at `FadeOverlay.RENDER_PRIORITY` with no depth
## test, so anything opaque, the controllers included, sits under it. While
## raised, every drawn surface of both controllers (the generic shape, the
## runtime model and the Meta model alike) gets a copy of its material in the
## transparent pass at `RENDER_PRIORITY`, one above the fade. The copy keeps its
## depth test, so the cockpit still hides a hand behind the dash, and the
## controllers are never drawn through it. Lowering puts every original
## material back, so in flight the controllers are exactly as they were.
##
## The flight control labels are left under the fade: they name what the
## controls do in flight (#1469 gives these screens their own). Only materials
## of the controller nodes change: no simulation, run, profile or comfort state
## is read or written (ARC-3, MP-2).

## One above the fade, the top of the transparent pass.
const RENDER_PRIORITY: int = Material.RENDER_PRIORITY_MAX
## Meta keys on a raised node: its own override and its surfaces' overrides.
const OVERRIDE_META: StringName = &"hands_over_fade_override"
const SURFACES_META: StringName = &"hands_over_fade_surfaces"

## Under which the controllers are looked for; null draws nothing.
var rig: Node = null

var _raised: bool = false


func attach(at: Node) -> void:
	rig = at


## Once per frame: raises both controllers while `dark`, lowers them once it
## ends. Raising runs every frame while dark, because a runtime model's meshes
## may arrive after the screen came up; surfaces already raised are skipped.
func update(dark: bool) -> void:
	if dark:
		for model: ControllerModel in models(rig):
			raise(model)
		_raised = true
	elif _raised:
		for model: ControllerModel in models(rig):
			lower(model)
		_raised = false


func raised() -> bool:
	return _raised


## The controller models under `root`, both hands.
static func models(root: Node) -> Array[ControllerModel]:
	var found: Array[ControllerModel] = []
	if root == null:
		return found
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is ControllerModel:
			found.append(node as ControllerModel)
			continue
		pending.append_array(node.get_children())
	return found


## Every drawn node under `root` outside the labels.
static func drawn(root: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	if root == null:
		return found
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is ControlLabelSet:
			continue
		pending.append_array(node.get_children())
		if node is GeometryInstance3D:
			found.append(node as GeometryInstance3D)
	return found


## Puts every drawn surface under `root` (labels aside) over the fade. Returns
## how many surfaces were raised by this call. Safe to call again.
static func raise(root: Node) -> int:
	var count: int = 0
	for node: GeometryInstance3D in drawn(root):
		if node.material_override != null:
			if not node.has_meta(OVERRIDE_META) and node.material_override is BaseMaterial3D:
				node.set_meta(OVERRIDE_META, node.material_override)
				node.material_override = over(node.material_override as BaseMaterial3D)
				count += 1
			continue
		if not node is MeshInstance3D or node.has_meta(SURFACES_META):
			continue
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var kept: Array = []
		for i: int in mesh_node.get_surface_override_material_count():
			kept.append(mesh_node.get_surface_override_material(i))
			var active: Material = mesh_node.get_active_material(i)
			if active is BaseMaterial3D:
				mesh_node.set_surface_override_material(i, over(active as BaseMaterial3D))
				count += 1
		mesh_node.set_meta(SURFACES_META, kept)
	return count


## Puts back every material `raise` replaced under `root`.
static func lower(root: Node) -> void:
	for node: GeometryInstance3D in drawn(root):
		if node.has_meta(OVERRIDE_META):
			node.material_override = node.get_meta(OVERRIDE_META) as Material
			node.remove_meta(OVERRIDE_META)
		if node.has_meta(SURFACES_META):
			var kept: Array = node.get_meta(SURFACES_META)
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			for i: int in mini(kept.size(), mesh_node.get_surface_override_material_count()):
				mesh_node.set_surface_override_material(i, kept[i] as Material)
			node.remove_meta(SURFACES_META)


## A copy of `material` drawn after the fade: in the transparent pass at
## `RENDER_PRIORITY`, its depth test kept. An opaque material keeps writing
## depth through the pre-pass, so the model still hides its own back faces.
static func over(material: BaseMaterial3D) -> BaseMaterial3D:
	var copy: BaseMaterial3D = material.duplicate() as BaseMaterial3D
	copy.render_priority = RENDER_PRIORITY
	if copy.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			or copy.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
			or copy.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	return copy


## True when `material` draws over the fade: transparent, above the fade's
## priority, and still depth-tested (so not through the cockpit).
static func draws_over_fade(material: Material) -> bool:
	if not material is BaseMaterial3D:
		return false
	var base: BaseMaterial3D = material as BaseMaterial3D
	return base.render_priority > FadeOverlay.RENDER_PRIORITY \
		and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		and base.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
		and base.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_HASH \
		and not base.no_depth_test


## True when every drawn surface under `root` (labels aside) draws over the fade.
static func is_raised(root: Node) -> bool:
	for node: GeometryInstance3D in drawn(root):
		if node.material_override != null:
			if not draws_over_fade(node.material_override):
				return false
			continue
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			for i: int in mesh_node.get_surface_override_material_count():
				if not draws_over_fade(mesh_node.get_active_material(i)):
					return false
	return true
