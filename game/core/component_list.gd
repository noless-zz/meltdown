class_name ComponentList
extends RefCounted

## Every component kind the game knows, read from the files in
## `COMPONENTS_DIR` (CRF-1, ARC-4). The caller reads the files and hands their
## texts over by file name, because core never opens files. A new kind is a new
## file; nothing here names one.

const COMPONENTS_DIR: String = "res://data/components"
## The pickup rules (`ComponentPickup`) share the folder but are not a kind, so
## `parse` skips a text of this name.
const RULES_FILE: String = "pickup.json"

## Every kind, sorted by id so the order never depends on how the caller
## collected the files.
var kinds: Array[ComponentDef] = []
## Set by `parse` when a text was rejected; empty otherwise.
var error: String = ""
var _by_id: Dictionary[String, ComponentDef] = {}


## Parses `texts`, file text by file name. Each error starts with the file name
## and names the key. Two files giving the same `id` are an error. On failure
## `error` is set and the list is empty, so no caller works with part of it.
static func parse(texts: Dictionary) -> ComponentList:
	var list: ComponentList = ComponentList.new()
	var files: Array = texts.keys()
	files.sort()
	var first_file: Dictionary[String, String] = {}
	for file: Variant in files:
		var name: String = str(file)
		if name == RULES_FILE:
			continue
		if typeof(texts[file]) != TYPE_STRING:
			return _failed("%s: text must be a string" % name)
		var kind: ComponentDef = ComponentDef.parse_json(texts[file])
		if kind.error != "":
			return _failed("%s: %s" % [name, kind.error])
		if first_file.has(kind.id):
			return _failed("%s: key \"id\" is \"%s\", already used by %s" % [name, kind.id, first_file[kind.id]])
		first_file[kind.id] = name
		list._by_id[kind.id] = kind
	var ids: Array[String] = []
	ids.assign(list._by_id.keys())
	ids.sort()
	for id: String in ids:
		list.kinds.append(list._by_id[id])
	return list


## True when a kind with this id exists.
func has_kind(id: String) -> bool:
	return _by_id.has(id)


## The kind with this id, or null.
func get_kind(id: String) -> ComponentDef:
	return _by_id.get(id, null)


## Ids of every kind, sorted.
func ids() -> Array[String]:
	var found: Array[String] = []
	for kind: ComponentDef in kinds:
		found.append(kind.id)
	return found


static func _failed(message: String) -> ComponentList:
	var list: ComponentList = ComponentList.new()
	list.error = message
	return list
