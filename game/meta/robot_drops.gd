class_name RobotDrops
extends RefCounted

## Which robots drop each component (CRF-1, CRW-2, #1413), read from the
## `components` tables of the robot files, so the Parts Locker can say where a
## component comes from by the robots' shown names (`name`, never ids, #1317).
## A new robot file brings its own name and drops; nothing here is per robot
## (ARC-4). Read only: the simulation reads the same files itself (MP-2).

const ROBOTS_DIR: String = "res://data/robots"

## Component id to the shown names of the robots that may drop it, sorted.
var sources: Dictionary[String, Array] = {}
## The first robot file refused, with the file named; "" when all were read.
var error: String = ""


## Reads the shipped robot files.
static func load_shipped() -> RobotDrops:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(ROBOTS_DIR.path_join(file))
	return parse(texts)


## `texts` maps a file name to its text. Every file must parse and give its
## robot a shown name (`RobotDef.check_name`); the first that does not is
## `error`, and its drops are left out.
static func parse(texts: Dictionary) -> RobotDrops:
	var drops: RobotDrops = RobotDrops.new()
	var files: Array = texts.keys()
	files.sort()
	for file: Variant in files:
		var robot: RobotDef = RobotDef.parse_json(str(texts[file]))
		var problem: String = robot.error if robot.error != "" else robot.check_name()
		if problem != "":
			if drops.error == "":
				drops.error = "%s: %s" % [str(file), problem]
			continue
		for drop: ComponentDrop in robot.components:
			var names: Array = drops.sources.get(drop.id, [])
			if not names.has(robot.display_name):
				names.append(robot.display_name)
			names.sort()
			drops.sources[drop.id] = names
	return drops


## The shown names of the robots that may drop component `id`; empty for none.
func names(id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(sources.get(id, []))
	return out
