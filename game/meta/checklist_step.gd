class_name ChecklistStep
extends RefCounted

## One step of an in-game test checklist (#1325, DEV-6): what to do, what to
## look for, the part it belongs to, the canned remarks it offers and the one
## action the game may take for it. Read by `Checklist`; no nodes.
##
## An action is data, never code (ARC-4): `ACTION_COMFORT` with a preset
## number, `ACTION_SEED` with a seed, `ACTION_LEVEL` with a level file path, or
## `ACTION_TUNNEL`. The wiring turns it into the dev menu's own choice, so it
## goes through the same code path as the menu (ARC-3).

const ACTION_NONE: String = ""
const ACTION_COMFORT: String = "comfort"
const ACTION_SEED: String = "seed"
const ACTION_LEVEL: String = "level"
const ACTION_TUNNEL: String = "tunnel"
const ACTIONS: Array[String] = [ACTION_COMFORT, ACTION_SEED, ACTION_LEVEL, ACTION_TUNNEL]

## Unique within its checklist; the results file names steps by it.
var id: String = ""
## Index into `Checklist.parts`.
var part: int = 0
var do_text: String = ""
var look_for: String = ""
## The remarks offered for this step: its own, else the checklist's.
var remarks: Array[String] = []
var action: String = ACTION_NONE
## The preset number, seed or level path the action uses; "" for none or the tunnel.
var action_value: String = ""


## The action in words for the page and the docs copy, or "" for none.
func action_text() -> String:
	match action:
		ACTION_COMFORT: return "set comfort preset %s" % action_value
		ACTION_SEED: return "fly seed #%s" % action_value
		ACTION_LEVEL: return "fly %s" % action_value.get_file().get_basename()
		ACTION_TUNNEL: return "fly the test tunnel"
	return ""
