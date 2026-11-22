extends RefCounted

## `HitShakeWiring` on its own (#1157; CMF-1, CMF-3, ARC-3): a hit feeds a
## shake that decays to zero, the shake follows the preset it is handed, and
## it never writes the ship it reads.

## One headset frame at 90 Hz.
const FRAME_S: float = 1.0 / 90.0


static func _hit() -> Array[SimEvent]:
	var events: Array[SimEvent] = [SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 30.0, Vector3.BACK)]
	return events


func test_a_hit_feeds_a_shake_that_decays_to_zero() -> String:
	var wiring: HitShakeWiring = HitShakeWiring.new()
	if wiring.hit_shake == null:
		return "the shipped hit-shake file was rejected"
	var preset: ComfortPreset = ComfortPresetFiles.load_number(3)
	wiring.set_preset(preset)
	wiring.feed(_hit(), 0, Basis.IDENTITY)
	if not wiring.hit_shake.strength() > 0.0:
		return "a hard wall impact gave no shake"
	var moved: bool = false
	var frames: int = int(ceil(wiring.hit_shake.decay_s / FRAME_S)) + 2
	for _i: int in frames:
		wiring.advance(preset, FRAME_S)
		if wiring.offset != Transform3D.IDENTITY:
			moved = true
	if not moved:
		return "preset 3 never moved the view after a hit"
	if wiring.hit_shake.strength() != 0.0:
		return "shake strength %f after the decay time, expected 0" % wiring.hit_shake.strength()
	if wiring.offset != Transform3D.IDENTITY:
		return "the view offset did not return to the identity after the decay time"
	return ""


func test_a_hit_on_another_ship_is_ignored() -> String:
	var wiring: HitShakeWiring = HitShakeWiring.new()
	wiring.set_preset(ComfortPresetFiles.load_number(3))
	wiring.feed(_hit(), 1, Basis.IDENTITY)
	if wiring.hit_shake.strength() != 0.0:
		return "ship 1's impact shook ship 0's view"
	return ""


func test_preset_1_strength_is_the_preset_file_s() -> String:
	var wiring: HitShakeWiring = HitShakeWiring.new()
	var file_preset: ComfortPreset = ComfortPresetFiles.load_number(1)
	wiring.set_preset(file_preset)
	if wiring.hit_shake.preset != file_preset:
		return "the shake does not follow the preset it was handed"
	if wiring.hit_shake.preset.hit_shake != file_preset.hit_shake:
		return "preset 1 shake strength %f, file says %f" % [
			wiring.hit_shake.preset.hit_shake, file_preset.hit_shake]
	wiring.feed(_hit(), 0, Basis.IDENTITY)
	wiring.advance(file_preset, FRAME_S)
	if file_preset.hit_shake == 0.0 and wiring.offset != Transform3D.IDENTITY:
		return "preset 1's file has no shake, but a hit moved the view"
	return ""


func test_a_rejected_file_gives_no_shake() -> String:
	if HitShakeWiring.load_hit_shake("res://xr/no_such_file.json") != null:
		return "a missing hit-shake file still gave a shake"
	var wiring: HitShakeWiring = HitShakeWiring.new()
	wiring.hit_shake = null
	wiring.feed(_hit(), 0, Basis.IDENTITY)
	wiring.advance(ComfortPresetFiles.load_number(3), FRAME_S)
	if wiring.offset != Transform3D.IDENTITY:
		return "no shake file, yet the view moved"
	return ""


func test_interpolated_pose_blends_and_snaps() -> String:
	var previous: ShipState = ShipState.new()
	var current: ShipState = ShipState.new()
	current.position = Vector3(2.0, 0.0, 0.0)
	current.orientation = Basis(Vector3.UP, PI / 2.0)
	var halfway: Transform3D = HitShakeWiring.interpolated_pose(previous, current, 0.5)
	if not halfway.origin.is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		return "halfway position %s" % halfway.origin
	var angle: float = halfway.basis.get_rotation_quaternion().get_angle()
	if absf(angle - PI / 4.0) > 0.001:
		return "halfway turn %f rad, expected %f" % [angle, PI / 4.0]
	var snapped: Transform3D = HitShakeWiring.interpolated_pose(previous, current, 0.5, true)
	if absf(snapped.basis.get_rotation_quaternion().get_angle() - PI / 2.0) > 0.001:
		return "a snapped tick was blended instead of shown at once"
	if previous.position != Vector3.ZERO or current.position != Vector3(2.0, 0.0, 0.0):
		return "interpolated_pose wrote the ship states it reads"
	return ""


func test_comfort_wiring_keeps_its_hit_shake_names() -> String:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	if comfort.hit_shake != comfort.shaking.hit_shake or comfort.drift != comfort.shaking.drift:
		return "ComfortWiring's hit_shake or drift is not the moved wiring's"
	comfort.set_preset(3)
	if comfort.hit_shake.preset != comfort.preset:
		return "set_preset did not reach the moved shake"
	comfort.feed_hit_shake(_hit(), 0, Basis.IDENTITY)
	comfort.advance_hit_shake(FRAME_S)
	if comfort.shake_offset != comfort.shaking.offset:
		return "shake_offset does not read the moved wiring's offset"
	return ""
