class_name EndScreenLists
extends RefCounted

## What the end screens list (#1376, CRF-2, RUN-7, SLV-3, PLT-2; the owner's G4
## note #1356): an escape lists what this level banked, by kind, and the miners
## brought out; a lost ship lists what earlier escapes kept and what this level
## lost. Both name the base in their prompt when the press ends the run.
##
## It words plain copies of counts handed to it and never reads the session,
## so nothing here can write simulation state (MP-2). The component lists are
## worded by `StatusPanelTally.items_text`, the same "2 Cell Salts, 1 Core
## Glass" the cockpit's tally shows; the words come from `EndScreenListsLook`
## (ARC-4).

var look: Dictionary
var _tally: StatusPanelTally


## `p_look` is the lists' look; `names` maps a component id to the name shown.
func _init(p_look: Dictionary = EndScreenListsLook.FALLBACK, names: Dictionary[String, String] = {}) -> void:
	look = p_look
	# The tally words the items only through `tally_none_text`.
	_tally = StatusPanelTally.new({"tally_none_text": look["none_text"]}, names)


## The shipped look and component names.
static func load_shipped() -> EndScreenLists:
	return EndScreenLists.new(EndScreenListsLook.load_file(), StatusPanelTally.shipped_names())


## The escape screen's lines: this level's `collected` components, banked on
## the press, and its `rescued` miners.
func escape_text(collected: Dictionary, rescued: int) -> String:
	return "\n".join([
		(look["banked_text"] as String).replace(EndScreenListsLook.ITEMS_TAG, items(collected)),
		(look["brought_out_text"] as String).replace(EndScreenListsLook.MINERS_TAG, str(maxi(rescued, 0))),
	])


## The destroyed screen's lines: the run's `kept` banked components, and this
## level's `lost` components and `lost_miners`.
func destroyed_text(kept: Dictionary, lost: Dictionary, lost_miners: int) -> String:
	return "\n".join([
		(look["kept_text"] as String).replace(EndScreenListsLook.ITEMS_TAG, items(kept)),
		(look["lost_text"] as String).replace(EndScreenListsLook.ITEMS_TAG, items(lost))
			.replace(EndScreenListsLook.MINERS_TAG, str(maxi(lost_miners, 0))),
	])


## The prompt when the press ends the run and opens the base; `xr_running`
## picks the button it names.
func base_prompt(xr_running: bool) -> String:
	return look["base_prompt_xr"] if xr_running else look["base_prompt_flat"]


## `counts` worded by kind, or the look's `none_text`.
func items(counts: Dictionary) -> String:
	return _tally.items_text(StatusPanelTally.counts_of(counts))


## The lists' label for a screen, at `at` from the eye point, drawn over the
## fade like the screen's own lines.
func make_label(at: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Lists"
	label.position = at
	label.pixel_size = DestroyedScreen.PIXEL_SIZE
	label.font_size = roundi(float(look["font_size"]))
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.modulate = look["color"]
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = DestroyedScreen.RENDER_PRIORITY
	return label
