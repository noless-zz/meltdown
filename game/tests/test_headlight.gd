extends RefCounted

## The ship's headlight (#609, CMB-5, GFX-4, ARC-4): the look file needs every
## key and names a bad one, the light is the only one that casts shadows, and
## the rig carries it at the ship's centre shining along the nose.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"


func _valid() -> Dictionary:
	return {"color": [1.0, 0.9, 0.8], "energy": 3.0, "range_m": 40.0, "angle_deg": 30.0,
		"attenuation": 1.0, "offset_m": [0.0, -0.2, -0.3]}


func _rig() -> Node3D:
	var rig: Node3D = (load(RIG_SCENE) as PackedScene).instantiate() as Node3D
	rig.call("build")
	return rig


func test_the_shipped_look_parses_and_is_applied() -> String:
	var lamp: Headlight = Headlight.new()
	var result: String = ""
	if lamp.look_error != "":
		result = "shipped look rejected: %s" % lamp.look_error
	elif not lamp.shadow_enabled or not lamp.visible:
		result = "the headlight is off or casts no shadow"
	elif not is_equal_approx(lamp.spot_range, float(lamp.look()["range_m"])) \
			or not is_equal_approx(lamp.spot_angle, float(lamp.look()["angle_deg"])) \
			or not is_equal_approx(lamp.light_energy, float(lamp.look()["energy"])):
		result = "range, angle or energy is not the look's"
	lamp.free()
	return result


func test_every_key_is_required_and_bad_ones_are_named() -> String:
	if Headlight.parse_look(JSON.stringify(_valid())).has("error"):
		return "a valid look was rejected: %s" % Headlight.parse_look(JSON.stringify(_valid()))["error"]
	for key: String in Headlight.KEYS:
		var data: Dictionary = _valid()
		data.erase(key)
		var error: String = String(Headlight.parse_look(JSON.stringify(data)).get("error", ""))
		if not error.contains(key):
			return "missing %s gave \"%s\"" % [key, error]
	var cases: Dictionary[String, Variant] = {
		"energy": 20.0, "range_m": 1.0, "angle_deg": 90.0, "attenuation": true,
		"color": [1.0, 1.0], "offset_m": [0.0, 0.0, -0.8],
	}
	for key: String in cases:
		var data: Dictionary = _valid()
		data[key] = cases[key]
		var error: String = String(Headlight.parse_look(JSON.stringify(data)).get("error", ""))
		if not error.contains(key):
			return "bad %s gave \"%s\"" % [key, error]
	var lamp: Headlight = Headlight.new()
	var error: String = lamp.load_look("res://view/no_such_headlight.json")
	var fell_back: bool = lamp.look() == Headlight.FALLBACK and lamp.shadow_enabled
	lamp.free()
	if error == "" or not fell_back:
		return "a missing file did not fall back with a lit lamp (\"%s\")" % error
	return ""


func test_the_rig_carries_one_headlight_along_the_nose() -> String:
	var rig: Node3D = _rig()
	var result: String = ""
	var lamps: Array[Node] = rig.find_children("*", "Headlight", true, false)
	if lamps.size() != 1:
		result = "the rig has %d headlights" % lamps.size()
	rig.call("build")
	if result == "" and rig.find_children("*", "Headlight", true, false).size() != 1:
		result = "building the rig twice added a second headlight"
	if result == "":
		var lamp: Headlight = lamps[0] as Headlight
		var frame: Transform3D = rig.call("ship_frame")
		var nose: Vector3 = -frame.basis.z
		var shines: Vector3 = -lamp.transform.basis.z
		if not shines.is_equal_approx(nose):
			result = "the headlight shines along %s, the nose is %s" % [shines, nose]
		var expected: Vector3 = frame * (lamp.look()["offset_m"] as Vector3)
		if result == "" and not lamp.position.is_equal_approx(expected):
			result = "the headlight sits at %s, expected %s" % [lamp.position, expected]
	rig.free()
	return result


func test_the_headlight_follows_the_cockpit_frame_not_the_head() -> String:
	var rig: Node3D = _rig()
	var frame: CockpitFrame = CockpitFrame.new()
	rig.add_child(frame)
	# A recentre done with the head turned left and 1.2 m up puts the ship's
	# centre there in the rig's space.
	frame.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(0.3, 1.2, -0.1))
	var camera: Node3D = rig.get_node("Camera") as Node3D
	camera.transform = Transform3D(Basis(Vector3.UP, -1.0), Vector3(0.0, 1.7, 0.0))
	rig.call("place_headlight")
	var lamp: Headlight = rig.call("headlight")
	var result: String = ""
	var nose: Vector3 = -frame.transform.basis.z
	if not (-lamp.transform.basis.z).is_equal_approx(nose):
		result = "the headlight turned with the head instead of the ship"
	elif not lamp.position.is_equal_approx(frame.transform * (lamp.look()["offset_m"] as Vector3)):
		result = "the headlight is not at the ship's centre plus its offset"
	rig.free()
	return result


func test_no_other_light_casts_shadows() -> String:
	var tunnel: TestTunnel = TestTunnel.new()
	tunnel.build()
	var result: String = ""
	for light: Node in tunnel.find_children("*", "Light3D", true, false):
		if (light as Light3D).shadow_enabled:
			result = "tunnel light %s casts shadows; only the headlight may (GFX-4)" % light.name
	tunnel.free()
	return result
