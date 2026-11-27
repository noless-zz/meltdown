extends RefCounted

## The "Update available" sign at the home base (#1450, DEV-8, ARC-4): its
## place and words are data, checked when read; it names the waiting build and
## says to open the menu, shows nothing when no build waits, faces the seat's
## eye point and draws on the room's layer.


func test_the_shipped_file_is_read_and_names_the_build() -> String:
	var look: UpdateSignLook = UpdateSignLook.load_file()
	if look.error != "":
		return "the shipped sign file was refused: %s" % look.error
	var lines: Array[String] = look.lines("1a2b3c4")
	if lines.size() != 2 or not lines[0].contains("1a2b3c4") or lines[1] != "Update: open the menu":
		return "the sign says %s" % [lines]
	return "" if look.lines("").is_empty() else "the sign says something with no build waiting"


func test_a_bad_field_is_refused_by_name_and_the_built_in_look_kept() -> String:
	var cases: Dictionary = {
		'{"position_m": [1, 2]}': "position_m",
		'{"position_m": [0, 0, 0]}': "position_m",
		'{"title_text": ""}': "title_text",
		'{"font_size": 0}': "font_size",
		'{"colour": "red"}': "colour",
		'[1]': "JSON object",
	}
	for text: String in cases:
		var look: UpdateSignLook = UpdateSignLook.parse(text)
		if not look.error.contains(cases[text]):
			return "%s gave \"%s\"" % [text, look.error]
		if look.hint_text != "Update: open the menu" or look.position_m != Vector3(0.4, -0.4, -0.35):
			return "%s did not keep the built-in look" % text
	var read: UpdateSignLook = UpdateSignLook.parse('{"position_m": [0.5, -0.2, -0.5], "hint_text": "Menu: {version}"}')
	if read.error != "" or read.position_m != Vector3(0.5, -0.2, -0.5) or read.lines("x")[1] != "Menu: x":
		return "a good file was not read: %s" % read.error
	return ""


func test_the_sign_faces_the_eye_point_on_the_room_layer() -> String:
	var sign: UpdateSign = UpdateSign.new()
	var toward_eye: Vector3 = -sign.transform.origin.normalized()
	var face: Vector3 = sign.transform.basis.z
	var flat: Vector3 = Vector3(toward_eye.x, 0.0, toward_eye.z).normalized()
	var problem: String = ""
	if face.dot(flat) < 0.99 or absf(sign.transform.basis.y.dot(Vector3.UP) - 1.0) > 0.001:
		problem = "the sign faces %s, not the eye point %s, or is not upright" % [face, flat]
	for child: Node in sign.get_children():
		if problem == "" and ((child as VisualInstance3D).layers & HubRoom.LAYER_BIT) == 0:
			problem = "%s is not on the room's layer" % child.name
	sign.show_version("abc")
	if problem == "" and (not sign.visible or sign.texts().size() != 2):
		problem = "a waiting build showed %s" % [sign.texts()]
	sign.show_version("")
	if problem == "" and sign.visible:
		problem = "the sign stayed up with no build waiting"
	sign.free()
	return problem
