extends RefCounted

## The build targets are data in export_presets.cfg (ARC-6). CI and
## tools/build.sh look presets up by name, so a renamed or missing preset
## would only show up as a failed export much later; these checks catch it
## in the unit test job.

const PRESETS_PATH: String = "res://export_presets.cfg"


## Returns the section name ("preset.N") of the preset called `preset_name`,
## or "" when there is none.
func _find_preset(config: ConfigFile, preset_name: String) -> String:
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		if str(config.get_value(section, "name", "")) == preset_name:
			return section
	return ""


func _load() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return null
	return config


func test_linux_server_preset_is_dedicated_server() -> String:
	var config: ConfigFile = _load()
	if config == null:
		return "could not read %s" % PRESETS_PATH
	var section: String = _find_preset(config, "Linux Server")
	if section == "":
		return "no preset named Linux Server"
	if str(config.get_value(section, "platform", "")) != "Linux":
		return "Linux Server preset is not a Linux export"
	if config.get_value(section, "dedicated_server", false) != true:
		return "Linux Server preset is not in dedicated server export mode"
	return ""


func test_linux_desktop_preset_is_a_client() -> String:
	var config: ConfigFile = _load()
	if config == null:
		return "could not read %s" % PRESETS_PATH
	var section: String = _find_preset(config, "Linux Desktop")
	if section == "":
		return "no preset named Linux Desktop"
	if str(config.get_value(section, "platform", "")) != "Linux":
		return "Linux Desktop preset is not a Linux export"
	if config.get_value(section, "dedicated_server", false) != false:
		return "Linux Desktop preset must not strip visuals as a dedicated server"
	return ""


func test_no_preset_ships_the_tests() -> String:
	var config: ConfigFile = _load()
	if config == null:
		return "could not read %s" % PRESETS_PATH
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		if not str(config.get_value(section, "exclude_filter", "")).contains("tests/*"):
			return "preset %s does not exclude tests/*" % str(config.get_value(section, "name", section))
	return ""


## Returns the name of the first preset whose include_filter does not match
## `data_file`, or "" when every preset includes it.
func _preset_missing(config: ConfigFile, data_file: String) -> String:
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		var included: bool = false
		for pattern: String in str(config.get_value(section, "include_filter", "")).split(",", false):
			if data_file.match(pattern.strip_edges()):
				included = true
		if not included:
			return str(config.get_value(section, "name", section))
	return ""


## The ship tuning file is plain JSON, not a resource, so `all_resources`
## alone would leave it out of every build and the ship would fly the
## built-in defaults on the headset (ARC-5).
func test_every_preset_ships_the_tuning_file() -> String:
	var config: ConfigFile = _load()
	if config == null:
		return "could not read %s" % PRESETS_PATH
	var data_file: String = "data/ships/default_ship.json"
	var missing: String = _preset_missing(config, data_file)
	if missing != "":
		return "preset %s does not include %s" % [missing, data_file]
	return ""


## The acceptance suites run on the headset too (#154), and a suite step that
## flies a replay needs the `.replay` text file in the build; without it the
## m1 `final_hash` step cannot open its replay on the Quest (#184).
func test_every_preset_ships_the_acceptance_files() -> String:
	var config: ConfigFile = _load()
	if config == null:
		return "could not read %s" % PRESETS_PATH
	for data_file: String in ["acceptance/replays/basic_flight.replay", "acceptance/suites/m1.json",
			"acceptance/replays/bot_test_tunnel.replay", "acceptance/suites/m2.json"]:
		var missing: String = _preset_missing(config, data_file)
		if missing != "":
			return "preset %s does not include %s" % [missing, data_file]
	return ""


## The in-app update spike (#130) needs the installer permission on the Quest
## build only: a desktop or server build has no reason to ask for it.
func test_only_the_quest_preset_requests_install_packages() -> String:
	var config: ConfigFile = _load()
	if config == null:
		return "could not read %s" % PRESETS_PATH
	var permission: String = "android.permission.REQUEST_INSTALL_PACKAGES"
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		var preset_name: String = str(config.get_value(section, "name", section))
		var options: String = section + ".options"
		var custom: Variant = config.get_value(options, "permissions/custom_permissions", PackedStringArray())
		var requests: bool = custom is PackedStringArray and (custom as PackedStringArray).has(permission)
		if preset_name == "Android Quest" and not requests:
			return "Android Quest preset does not request %s" % permission
		if preset_name != "Android Quest" and requests:
			return "preset %s requests %s" % [preset_name, permission]
	if _find_preset(config, "Android Quest") == "":
		return "no preset named Android Quest"
	return ""
