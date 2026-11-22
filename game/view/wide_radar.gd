class_name WideRadar
extends RefCounted

## The wide radar module's data, `res://data/utility/wide_radar.json` (#1059,
## CRF-5, ARC-4): how far from the ship the hologram map shows tunnels while
## the module is in a utility slot.
##
##     {"reveal_radius_m": 40.0}
##
## The view reads it; core only knows the module's id (`ShipLoadout`), so the
## radar never changes simulation state (MP-2). `UtilityRadius` checks the file.

const PATH: String = "res://data/utility/wide_radar.json"
const RADIUS_KEY: String = "reveal_radius_m"

## Metres from the ship within which tunnel boxes are shown; 0 when rejected.
var reveal_radius_m: float = 0.0
## Set when the file was rejected, naming the file and the key; empty otherwise.
var error: String = ""


## Reads and checks the file at `path`.
static func load_file(path: String = PATH) -> WideRadar:
	return _from(UtilityRadius.load_file(path, RADIUS_KEY))


## Checks `text`, the contents of the file at `path` (used in messages only).
static func parse(text: String, path: String = PATH) -> WideRadar:
	return _from(UtilityRadius.parse(text, path, RADIUS_KEY))


static func _from(read: Dictionary) -> WideRadar:
	var radar: WideRadar = WideRadar.new()
	radar.reveal_radius_m = float(read["value"])
	radar.error = read["error"]
	return radar
