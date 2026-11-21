class_name LayoutMapping
extends RefCounted

## Builds the game's one thumbstick mapping from the layout file, so an edit
## to the file's bindings or `stick_dead_zone` reaches flight after a rebuild
## (#875, PLT-5, ARC-4). Before this the main scene used the built-in layout
## and the file was only checked against it.
##
## A missing or rejected file must not leave the ship unflyable, so it falls
## back to the built-in layout with one warning naming the file. A rejected
## dead zone alone is `ThumbstickMapping.from_json`'s case: the file's
## bindings load with the default dead zone and its own warning.


## The file the game flies when `load_file` is given no path. A test points it
## at a scratch layout to prove the main scene reads the file rather than the
## built-in layout, which the shipped file equals (#901), and puts it back.
static var path: String = ThumbstickMapping.DEFAULT_LAYOUT_FILE


## The mapping for `file_path`, or for `path` when none is given, falling back
## to the built-in layout when the file is missing or rejected. Hands and pitch
## are applied by the caller.
static func load_file(file_path: String = "") -> ThumbstickMapping:
	var used: String = file_path if file_path != "" else path
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(used)
	if mapping.error != "":
		push_warning(fallback_warning(used, mapping.error))
	return mapping


## The one warning logged when `file_path` could not be used.
static func fallback_warning(file_path: String, error: String) -> String:
	return "Meltdown: thumbstick layout %s not used, flying the built-in layout: %s" % [file_path, error]
