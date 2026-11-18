extends RefCounted

## Decides which acceptance replays a recording run rewrites (DEV-6, ARC-2, #560).
##
## A record switch such as `MELTDOWN_RECORD_M3` holds either `1` (every step that
## switch covers, as before) or a comma-separated list of step ids, for example
##
##     MELTDOWN_RECORD_M3=bot_generated_escape
##     MELTDOWN_RECORD_M3=bot_g2_escape,bot_generated_door_escape
##
## Recorders fly the current bot, so a step recorded without being asked for can
## silently drift from its stored flight (#548 rewrote the G2 escape that way).
## Each recorder therefore records only when its own step id is asked for.

## The value that keeps meaning "every step this switch covers".
const ALL: String = "1"


## True when the environment variable `switch_name` asks for `step_id`.
static func asks_for(switch_name: String, step_id: String) -> bool:
	return lists(OS.get_environment(switch_name), step_id)


## True when the switch value `value` asks for `step_id`: it is `1`, or one of its
## comma-separated entries, spaces trimmed, is exactly `step_id`.
static func lists(value: String, step_id: String) -> bool:
	for entry: String in value.split(",", false):
		var trimmed: String = entry.strip_edges()
		if trimmed == ALL or (trimmed != "" and trimmed == step_id):
			return true
	return false
