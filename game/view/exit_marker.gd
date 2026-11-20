class_name ExitMarker
extends Node3D

## The sign at the exit (#617, RUN-3, RUN-5): a ring of light around the
## entrance, which is the exit, and the word EXIT above it, so the pilot sees
## it when first passing it and finds it again during the escape.
##
## The ring stands across the way the ship faced at the start, so the pilot
## flies out through it the way they came in. Its look comes from
## `res://view/escape_cue_look.json` (ARC-4). It is handed a pose and reads
## nothing of the simulation (MP-2). The ring is unshaded and casts no light,
## so it costs no more than a few hundred triangles (PRF-2).

const NODE_NAME: String = "ExitMarker"
const RING_NAME: String = "Ring"
const TEXT_NAME: String = "Text"
## The text's glyph size in pixels; its height in metres comes from the look.
const TEXT_FONT_SIZE: int = 64
## Space between the ring's top and the text's baseline, metres.
const TEXT_GAP_M: float = 0.3

var ring: MeshInstance3D
var text: Label3D


func _init(look: Dictionary = EscapeCueLook.shared()) -> void:
	name = NODE_NAME
	var radius: float = float(look["exit_ring_radius_m"])
	var thickness: float = float(look["exit_ring_thickness_m"])
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = look["exit_color"]
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius - thickness / 2.0
	torus.outer_radius = radius + thickness / 2.0
	torus.rings = 48
	torus.ring_segments = 6
	ring = MeshInstance3D.new()
	ring.name = RING_NAME
	ring.mesh = torus
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The torus lies flat around its own +Y; a quarter turn about X stands it
	# across the ship's forward axis, Z.
	ring.basis = Basis(Vector3.RIGHT, PI / 2.0)
	add_child(ring)
	text = Label3D.new()
	text.name = TEXT_NAME
	text.text = look["exit_text"]
	text.font_size = TEXT_FONT_SIZE
	text.pixel_size = float(look["exit_text_height_m"]) / TEXT_FONT_SIZE
	text.modulate = look["exit_color"]
	text.shaded = false
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	text.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	text.position = Vector3(0.0, radius + thickness + TEXT_GAP_M, 0.0)
	add_child(text)


## Puts the marker at `at`, the exit, turned as the ship started there.
func place(at: Vector3, facing: Basis) -> void:
	transform = Transform3D(facing, at)


## The ring's axis in the marker's parent's space: the way through it.
func ring_axis() -> Vector3:
	return (basis * ring.basis * Vector3.UP).normalized()
