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


## The mapping for `path`, falling back to the built-in layout when the file
## is missing or rejected. Hands and pitch are applied by the caller.
static func load_file(path: String = ThumbstickMapping.DEFAULT_LAYOUT_FILE) -> ThumbstickMapping:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
	if mapping.error != "":
		push_warning(fallback_warning(path, mapping.error))
	return mapping


## The one warning logged when `path` could not be used.
static func fallback_warning(path: String, error: String) -> String:
	return "Meltdown: thumbstick layout %s not used, flying the built-in layout: %s" % [path, error]
