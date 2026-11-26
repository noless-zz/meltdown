class_name HubConfig
extends RefCounted

## The words and page order of the hub (CRW-2, ARC-4, #1033), read from
## `data/hub/hub.json` so titles, order and empty-page texts change without code.
## The page ids are fixed because each one names what `HubModel` lists on it;
## only their order and titles come from the file.

const CONFIG_PATH: String = "res://data/hub/hub.json"
const CREW: String = "crew"
## The Logbook: the profile's lifetime counters (#1095).
const STATS: String = "stats"
const STORE: String = "store"
const CRAFT: String = "craft"
const FIT: String = "fit"
## Every page the model knows; the file must list each exactly once.
const PAGE_IDS: Array[String] = [CREW, STATS, STORE, CRAFT, FIT]
const KEY_PAGES: String = "pages"
const KEY_EMPTY_CREW: String = "empty_crew"
const KEY_EMPTY_STORE: String = "empty_store"
## The row words, read by `HubWords` (#1058).
const KEY_TEXT: String = "text"
## Screen limits (#1300): rows on a station screen at once, and characters per
## row. Optional; a file without them gets the defaults.
const KEY_MAX_ROWS: String = "max_rows_visible"
const KEY_MAX_CHARS: String = "max_row_chars"
const DEFAULT_MAX_ROWS: int = 5
const DEFAULT_MAX_CHARS: int = 28
const KEYS: Array[String] = [KEY_PAGES, KEY_EMPTY_CREW, KEY_EMPTY_STORE, KEY_TEXT]
## The Fitting Bay's ship drawing (#1366, `HubFitLayout`). Optional; a file
## without it keeps the bay's rows only.
const KEY_FIT_SHIP: String = "fit_ship"
const KEY_CRAFT_TREE: String = "craft_tree"
## The Crew Quarters' and Logbook's boards (#1368, `HubBoardLayout`).
const KEY_BOARDS: String = "boards"
const OPTIONAL_KEYS: Array[String] = [KEY_MAX_ROWS, KEY_MAX_CHARS, KEY_FIT_SHIP, KEY_CRAFT_TREE, KEY_BOARDS]
const PAGE_KEYS: Array[String] = ["id", "title"]
const TEXT_MAX_LENGTH: int = 120

## Page ids in the order the file lists them.
var pages: Array[String] = []
var empty_crew: String = ""
var empty_store: String = ""
## Rows a station screen shows at once; the window scrolls with the selection.
var max_rows_visible: int = DEFAULT_MAX_ROWS
## Characters a filled row may have; a test holds every shipped text to it.
var max_row_chars: int = DEFAULT_MAX_CHARS
## The words of every row a hub panel shows (#1058).
var words: HubWords = HubWords.new()
## The ship the Fitting Bay draws; `has_ship()` is false when the file has none.
var fit_layout: HubFitLayout = HubFitLayout.new()
## How the Workbench draws its tech tree; `has_tree()` is false without one (#1367).
var craft_tree: HubTreeLayout = HubTreeLayout.new()
## How the Crew Quarters and Logbook draw; `has_boards()` is false without it (#1368).
var boards: HubBoardLayout = HubBoardLayout.new()
## Set by `parse_json` when the text was rejected; the config is then empty.
var error: String = ""
var _titles: Dictionary[String, String] = {}


## Reads the shipped file. A missing file is an error, like a bad one.
static func load_shipped() -> HubConfig:
	if not FileAccess.file_exists(CONFIG_PATH):
		return _failed("%s is missing" % CONFIG_PATH)
	var config: HubConfig = parse_json(FileAccess.get_file_as_string(CONFIG_PATH))
	if config.error != "":
		config.error = "%s: %s" % [CONFIG_PATH, config.error]
	return config


## Parses the text of `hub.json`. Every error names the key.
static func parse_json(text: String) -> HubConfig:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or OPTIONAL_KEYS.has(key)):
			return _failed("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _failed("missing key \"%s\"" % key)
	var config: HubConfig = HubConfig.new()
	var message: String = config._read_pages(data[KEY_PAGES])
	if message == "":
		message = _check_text(KEY_EMPTY_CREW, data[KEY_EMPTY_CREW])
	if message == "":
		message = _check_text(KEY_EMPTY_STORE, data[KEY_EMPTY_STORE])
	if message == "":
		message = config._read_limits(data)
	if message == "" and data.has(KEY_FIT_SHIP):
		config.fit_layout = HubFitLayout.parse(data[KEY_FIT_SHIP])
		message = config.fit_layout.error
	if message == "" and data.has(KEY_CRAFT_TREE):
		config.craft_tree = HubTreeLayout.parse(data[KEY_CRAFT_TREE])
		message = config.craft_tree.error
	if message == "" and data.has(KEY_BOARDS):
		config.boards = HubBoardLayout.parse(data[KEY_BOARDS])
		message = config.boards.error
	var words: HubWords = HubWords.parse(data[KEY_TEXT], TEXT_MAX_LENGTH) if message == "" else null
	if message == "" and words.error != "":
		message = words.error
	if message != "":
		return _failed(message)
	config.words = words
	config.empty_crew = data[KEY_EMPTY_CREW]
	config.empty_store = data[KEY_EMPTY_STORE]
	return config


## The optional screen limits, each a whole number of at least 1.
func _read_limits(data: Dictionary) -> String:
	for key: String in [KEY_MAX_ROWS, KEY_MAX_CHARS]:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		var number: bool = typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
		if not number or float(value) != floorf(float(value)) or float(value) < 1.0:
			return "key \"%s\" must be a whole number of at least 1" % key
	max_rows_visible = int(data.get(KEY_MAX_ROWS, DEFAULT_MAX_ROWS))
	max_row_chars = int(data.get(KEY_MAX_CHARS, DEFAULT_MAX_CHARS))
	return ""


## Title of page `id`, or "" for an unknown page.
func title(id: String) -> String:
	return _titles.get(id, "")


func _read_pages(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "key \"%s\" must be a list of pages" % KEY_PAGES
	var entries: Array = value
	for i: int in entries.size():
		var field: String = "%s[%d]" % [KEY_PAGES, i]
		if typeof(entries[i]) != TYPE_DICTIONARY:
			return "key \"%s\" must be an object with \"id\" and \"title\"" % field
		var entry: Dictionary = entries[i]
		for key: Variant in entry:
			if not PAGE_KEYS.has(str(key)):
				return "key \"%s\" has unknown key \"%s\"" % [field, str(key)]
		if not entry.has("id") or typeof(entry["id"]) != TYPE_STRING or not PAGE_IDS.has(entry["id"]):
			return "key \"%s.id\" must be one of %s" % [field, PAGE_IDS]
		var id: String = entry["id"]
		if pages.has(id):
			return "key \"%s.id\" repeats page \"%s\"" % [field, id]
		var message: String = _check_text("%s.title" % field, entry.get("title"))
		if message != "":
			return message
		pages.append(id)
		_titles[id] = entry["title"]
	for id: String in PAGE_IDS:
		if not pages.has(id):
			return "key \"%s\" is missing page \"%s\"" % [KEY_PAGES, id]
	return ""


static func _check_text(key: String, value: Variant) -> String:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		return "key \"%s\" must be a non-empty string" % key
	if String(value).length() > TEXT_MAX_LENGTH:
		return "key \"%s\" is longer than %d characters" % [key, TEXT_MAX_LENGTH]
	return ""


static func _failed(message: String) -> HubConfig:
	var config: HubConfig = HubConfig.new()
	config.error = message
	return config
