extends RefCounted

## Which points lie in a drawn box (#1382, GFX-3, PRF-2): a point in a shown
## box is drawn, one only in hidden boxes is not, one in no box is, a thing whose
## reach crosses into a shown box is, and culling off or no cull shows all. The
## level view hands the item views the boxes of its last cull.

const EPSILON: float = 1e-4


## A shown room A, a corridor B overlapping it (an opening), and a room C off
## on its own, beside A with a solid wall between.
func _union() -> BoxUnion:
	var boxes: Array[BoxBounds] = [
		BoxBounds.new(Vector3(0, 0, 0), Vector3(10, 4, 4)),
		BoxBounds.new(Vector3(9, 1, 1), Vector3(21, 3, 3)),
		BoxBounds.new(Vector3(0, 0, 6), Vector3(10, 4, 10)),
	]
	return BoxUnion.new(boxes)


func _flags(a: bool, b: bool, c: bool) -> Array[bool]:
	return [a, b, c] as Array[bool]


func test_points_follow_the_flags_of_their_boxes() -> String:
	var boxes: VisibleBoxes = VisibleBoxes.new(_union())
	boxes.set_flags(_flags(true, false, false))
	if not boxes.shows(Vector3(5, 2, 2)):
		return "a point in shown room A is hidden"
	if boxes.shows(Vector3(15, 2, 2)):
		return "a point only in hidden corridor B is drawn"
	if boxes.shows(Vector3(5, 2, 8)):
		return "a point in hidden room C is drawn"
	if not boxes.shows(Vector3(9.5, 2, 2)):
		return "a point in the opening, held by shown A and hidden B, is hidden"
	if not boxes.shows(Vector3(50, 2, 2)):
		return "a point in no box is hidden"
	if boxes.hidden != 2:
		return "%d hidden answers counted, expected 2" % boxes.hidden
	boxes.set_flags(_flags(true, false, false))
	if boxes.hidden != 0:
		return "a new cull kept %d hidden answers" % boxes.hidden
	return ""


func test_a_thing_reaching_into_a_shown_box_is_drawn() -> String:
	var boxes: VisibleBoxes = VisibleBoxes.new(_union())
	boxes.set_flags(_flags(false, true, false))
	# Room A only, 1.5 m from corridor B's end face at x = 9.
	var at: Vector3 = Vector3(7.5, 2, 2)
	if boxes.shows(at, 1.0):
		return "a 1 m thing 1.5 m from the shown corridor is drawn"
	if not boxes.shows(at, 2.0):
		return "a 2 m thing reaching into the shown corridor is hidden"
	return ""


func test_no_cull_all_shown_or_culling_off_draws_everything() -> String:
	var union: BoxUnion = _union()
	var boxes: VisibleBoxes = VisibleBoxes.new(union)
	if not boxes.shows(Vector3(15, 2, 2)):
		return "before any cull a point is hidden"
	boxes.set_flags(_flags(true, true, true))
	if not boxes.shows(Vector3(5, 2, 8)):
		return "with every box shown a point is hidden"
	boxes.set_flags(_flags(false, false, false))
	boxes.show_all()
	if not boxes.shows(Vector3(5, 2, 8)):
		return "after show_all a point is hidden"
	if not VisibleBoxes.allows(null, Vector3(5, 2, 8)):
		return "no boxes given hides a point"
	if VisibleBoxes.new().box_count() != 0 or not VisibleBoxes.new().shows(Vector3.ZERO):
		return "an empty VisibleBoxes hides a point"
	return ""


func test_the_level_view_hands_out_the_boxes_of_its_last_cull() -> String:
	var view: LevelView = LevelView.new()
	view.build(_union())
	var problem: String = ""
	var shown: VisibleBoxes = view.shown_boxes()
	if shown == null or shown.box_count() != 3:
		problem = "the view's boxes do not cover its level"
	# In room A looking along +x down the corridor: room C, behind the wall, is hidden.
	view.cull(Vector3(2, 2, 2), Basis.looking_at(Vector3.RIGHT, Vector3.UP))
	shown = view.shown_boxes()
	if problem == "" and view.box_node(2).visible:
		problem = "the test eye sees room C; the setup is wrong"
	if problem == "" and (not shown.shows(Vector3(2, 2, 2)) or not shown.shows(Vector3(15, 2, 2))):
		problem = "a point in a drawn box is hidden"
	if problem == "" and shown.shows(Vector3(5, 2, 8)):
		problem = "a point in hidden room C is drawn"
	view.set_culling(false)
	if problem == "" and not view.shown_boxes().shows(Vector3(5, 2, 8)):
		problem = "with culling off a point in room C is hidden"
	view.free()
	return problem


func test_a_frame_that_culls_early_is_not_culled_again() -> String:
	var view: LevelView = LevelView.new()
	view.build(_union())
	view.cull_camera()  # Not in a tree: no camera, so nothing is culled.
	var problem: String = ""
	if view.culled_frames != 0:
		problem = "culled %d times with no camera" % view.culled_frames
	if problem == "" and VisibleBoxes.of_world(null) != null:
		problem = "no world gave boxes"
	var world: Node3D = Node3D.new()
	if problem == "" and VisibleBoxes.of_world(world) != null:
		problem = "a world with no level view gave boxes"
	world.add_child(view)
	if problem == "" and VisibleBoxes.of_world(world) != view.shown_boxes():
		problem = "the world's boxes are not its level view's"
	world.free()
	return problem


func test_reads_no_layer_above_view() -> String:
	var code: String = FileAccess.get_file_as_string("res://view/visible_boxes.gd")
	for word: String in ["XR", "Sim.", "LocalSession", "Profile"]:
		if word in code:
			return "visible_boxes.gd mentions %s" % word
	return ""
