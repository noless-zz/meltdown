extends RefCounted

## The ship summary at the home base (#1357, CRF-4, CRW-1, CRW-2, ARC-4): its
## rows on the Fitting Bay and Crew Quarters, before and after under a fit,
## the one-press strip to stock, and no id in any of their words.

const Workbench: GDScript = preload("res://tests/test_hub_workbench.gd")
const Model: GDScript = preload("res://tests/test_hub_model.gd")


static func _engine_model() -> HubModel:
	var profile: Profile = Profile.new()
	profile.crafted = ["tuned_thrusters", "needle_gun", "wide_radar", "layered_plating"] as Array[String]
	profile.crew.append({Profile.CREW_ID: "crew-1", Profile.CREW_ROLE: "shield_tech"})
	return Workbench._model(profile)


## Selects the first row of `hub` whose action is `want`; false when none is.
static func _select(hub: HubText, want: Dictionary) -> bool:
	hub.move(-1000)
	for i: int in 200:
		if hub.selected() == want:
			return true
		var line: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == line:
			return false
	return false


## Every line `hub` shows on its current page or station with each row selected in turn.
static func _every_line(hub: HubText) -> Array[String]:
	var out: Array[String] = []
	hub.move(-1000)
	for i: int in 300:
		out.append_array(hub.lines())
		if hub.note() != "":
			out.append(hub.note())
		var line: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == line:
			break
	return out


func test_the_fitting_bay_and_crew_quarters_show_the_summary() -> String:
	var model: HubModel = _engine_model()
	var hub: HubText = HubText.new(model)
	var words: HubWords = model.config.words
	var speed: String = words.effect("max_speed", "20 / 20")
	var shield: String = words.effect("max_shield", "55 / 50")
	for station: String in ["fit", "crew"]:
		hub.choose_station(station)
		var lines: Array[String] = hub.lines()
		for want: String in [words.row("summary_header"), speed, shield]:
			if not lines.has(want):
				return "the %s station does not show \"%s\": %s" % [station, want, lines]
	hub.choose_station("crew")
	if not _every_line(hub).has(words.row("summary_crew", {"role": "Shield Technician", "count": 1, "change": "+5"})):
		return "the shield row does not name its crew source: %s" % [_every_line(hub)]
	return ""


func test_a_fit_shows_before_and_after_under_it_and_changes_nothing() -> String:
	var model: HubModel = _engine_model()
	model.config.fit_bars = HubFitBars.new()  # As words; the bars are `test_hub_fit_board.gd`'s (#1385).
	var hub: HubText = HubText.new(model)
	hub.choose_station("fit")
	var mount: Dictionary = {"action": HubText.ACTION_FIT, "slot": "engine", "id": "tuned_thrusters"}
	if not _select(hub, {"action": HubFitBay.ACTION_SLOT, "slot": "engine"}) or hub.press() != "" or not _select(hub, mount):
		return "no row mounts the thrusters: %s" % [hub.lines()]
	var words: HubWords = model.config.words
	var shown: Array[String] = []
	shown.assign(hub.lines().slice(1 + hub.first_shown(), 1 + hub.first_shown() + hub.rows_shown()))
	for change: Array in [["max_speed", "20 to 22"], ["acceleration", "40 to 46"]]:
		if not shown.has(words.effect(change[0], change[1])):
			return "the screen does not show \"%s\" with the mount: %s" % [words.effect(change[0], change[1]), shown]
	if model.fitting.parts["engine"] != "" or model.preview({"action": HubText.ACTION_FIT, "slot": "primary[0]", "id": "needle_gun"}) != []:
		return "a preview changed the fitting, or a weapon changed an attribute"
	if hub.press() != "" or not hub.lines().has(words.effect("max_speed", "22 / 20")):
		return "after the mount the summary reads %s" % [hub.lines()]
	return ""


func test_strip_to_stock_unmounts_everything_and_loses_nothing() -> String:
	var model: HubModel = _engine_model()
	var hub: HubText = HubText.new(model)
	hub.choose_station("fit")
	if _select(hub, {"action": HubText.ACTION_STRIP}):
		return "an empty fitting offers the strip row"
	for fit: Array in [["engine", "tuned_thrusters"], ["hull", "layered_plating"], ["primary[1]", "needle_gun"], ["utility[0]", "wide_radar"]]:
		var reason: String = model.fit(fit[0], fit[1])
		if reason != "":
			return "fit %s: %s" % [fit, reason]
	var crafted: Array[String] = model.profile.crafted.duplicate()
	if not _select(hub, {"action": HubText.ACTION_STRIP}) or hub.press() != "":
		return "no strip row, or it was refused"
	if not model.fitting.is_empty() or model.profile.crafted != crafted or model.profile.crew.size() != 1:
		return "after the strip: fitting %s, crafted %s, crew %s" % [model.fitting.to_json(), model.profile.crafted, model.profile.crew]
	if model.launch() != Model.ship_data()[ShipTuning.LOADOUT_KEY]:
		return "the launch after the strip gives %s" % model.launch()
	return "" if model.summary()[0]["current"] == model.summary()[0]["stock"] else "the summary is not stock: %s" % model.summary()[0]


func test_no_id_in_the_summary_rows() -> String:
	var ids: Array[String] = Workbench._shipped_ids()
	for model: HubModel in Workbench._states():
		var hub: HubText = HubText.new(model)
		for station: String in ["fit", "crew"]:
			hub.choose_station(station)
			for line: String in _every_line(hub):
				var found: String = Workbench._id_in(line, ids)
				if found != "":
					return "\"%s\" on the %s station shows the id \"%s\"" % [line, station, found]
	return ""


func test_numbers_read_short() -> String:
	var shown: Array[String] = [HubSummaryRows.number(20.0), HubSummaryRows.number(57.5), HubSummaryRows.number(0.426),
		HubSummaryRows.signed(2.0), HubSummaryRows.signed(-0.08)]
	return "" if shown == (["20", "57.5", "0.43", "+2", "-0.08"] as Array[String]) else "numbers read %s" % [shown]
