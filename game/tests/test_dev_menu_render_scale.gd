extends RefCounted

## The dev menu's Render scale row (#1417, GFX-7, DEV-6, ARC-3): it sits in
## the Display section of the shipped file, shows the scale in use as a
## percentage, follows it every frame while open, and is read-only: left and
## right change nothing, and confirming returns the shown value, which its
## helper takes and ignores, leaving the menu open. Without a scaler (the flat
## build) it reads 100%.


static func _wiring() -> DevMenuWiring:
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), null, null, null, null)
	wiring.attach(null, null, null, Callable(), null, null)
	return wiring


func test_the_row_is_in_the_display_section() -> String:
	var shipped: DevMenuSpec = DevMenuSpec.load_file()
	var section: int = DevMenuWalk.section_of_kind(shipped, DevMenuSpec.KIND_RENDER_SCALE)
	if shipped.error != "" or section == -1 or str(shipped.sections[section]["label"]) != "Display":
		return "the shipped file puts render_scale in section %d (%s)" % [section, shipped.error]
	var fallback: DevMenuSpec = DevMenuSpec.fallback()
	for entry: Dictionary in fallback.entries:
		if entry["kind"] == DevMenuSpec.KIND_RENDER_SCALE:
			return ""
	return "the built-in menu has no render scale row"


func test_it_shows_and_follows_the_scale_and_changes_nothing() -> String:
	var wiring: DevMenuWiring = _wiring()
	var model: DevMenuModel = wiring.menu.model
	var entry: DevMenuRenderScale = wiring.entry_for(DevMenuSpec.KIND_RENDER_SCALE) as DevMenuRenderScale
	if entry == null:
		wiring.menu.free()
		return "the wiring has no Render scale helper"
	var shown: Array[float] = [0.85]
	entry.read_scale = func() -> float: return shown[0]
	entry.show_on(model)
	model.open("centre", "")
	var problem: String = ""
	if not DevMenuWalk.select(model, DevMenuSpec.KIND_RENDER_SCALE):
		problem = "the row cannot be highlighted"
	elif DevMenuWalk.entry_line(model, DevMenuSpec.KIND_RENDER_SCALE) != "Render scale: < 85% >":
		problem = "the row reads \"%s\"" % DevMenuWalk.entry_line(model, DevMenuSpec.KIND_RENDER_SCALE)
	else:
		var results: Array[String] = [DevMenuWalk.tap(model, DevMenuModel.LEFT),
			DevMenuWalk.tap(model, DevMenuModel.RIGHT), DevMenuWalk.tap(model, DevMenuModel.CONFIRM)]
		shown[0] = 0.7
		entry.follow(model)
		wiring.menu.visible = true  # As the tap shows it; applying must not close it.
		wiring.apply(results[2])
		var expected: Array[String] = ["", "", "render_scale:85"]
		if results != expected or not wiring.menu.visible:
			problem = "pressing the row returned %s, menu shown %s" % [results, wiring.menu.visible]
		elif DevMenuWalk.entry_line(model, DevMenuSpec.KIND_RENDER_SCALE) != "Render scale: < 70% >":
			problem = "after the scale fell the row reads \"%s\"" % DevMenuWalk.entry_line(model, DevMenuSpec.KIND_RENDER_SCALE)
	wiring.menu.free()
	return problem


func test_without_a_scaler_it_reads_full() -> String:
	var wiring: DevMenuWiring = _wiring()
	var model: DevMenuModel = wiring.menu.model
	RenderScaler.in_use = 1.0
	wiring.entry_for(DevMenuSpec.KIND_RENDER_SCALE).show_on(model)
	var text: String = model.value_text(DevMenuSpec.KIND_RENDER_SCALE)
	wiring.menu.free()
	return "" if text == "100%" else "the flat row reads \"%s\"" % text
