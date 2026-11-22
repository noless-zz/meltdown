class_name DebrisMaterials
extends RefCounted

## The materials `DebrisView` draws debris with, painted from a `DebrisLook`
## dictionary (ARC-4). Every material glows by itself because the mine is dark
## (LGT-1); none adds a light (GFX-4). The see-through ones show both faces, so
## the glow still shows with the ship inside it.

var solid: StandardMaterial3D
var warn: StandardMaterial3D
var held: StandardMaterial3D
var slab: StandardMaterial3D
var slab_warn: StandardMaterial3D
var fire: StandardMaterial3D


func _init() -> void:
	solid = _new_material(false)
	warn = _new_material(true)
	held = _new_material(true)
	slab = _new_material(false)
	slab_warn = _new_material(true)
	fire = _new_material(true)


## Paints every material from `look`, with the fire glow as at `fire_tick`.
func paint(look: Dictionary, fire_tick: int) -> void:
	_paint(solid, look["solid_color"], float(look["solid_energy"]), 1.0)
	_paint(warn, look["warn_color"], float(look["warn_energy"]), float(look["warn_alpha"]))
	_paint(held, look["held_color"], float(look["held_energy"]), float(look["held_alpha"]))
	_paint(slab, look["slab_color"], float(look["slab_energy"]), 1.0)
	_paint(slab_warn, look["slab_warn_color"], float(look["slab_warn_energy"]),
		float(look["slab_warn_alpha"]))
	_paint(fire, look["fire_color"], DebrisLook.fire_energy_at(look, fire_tick),
		float(look["fire_alpha"]))


## Sets the fire glow for `tick` only; the flicker follows the simulation tick,
## never the clock (CMF-8).
func flicker_fire(look: Dictionary, tick: int) -> void:
	fire.emission_energy_multiplier = DebrisLook.fire_energy_at(look, tick)


func _new_material(see_through: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.emission_enabled = true
	material.roughness = 1.0
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _paint(material: StandardMaterial3D, color: Color, energy: float, alpha: float) -> void:
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission = color
	material.emission_energy_multiplier = energy
