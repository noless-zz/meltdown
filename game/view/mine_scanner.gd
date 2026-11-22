class_name MineScanner
extends RefCounted

## The mine scanner module's data, `res://data/utility/mine_scanner.json`
## (#1072, CRF-5, SLV-3, ARC-4): how far from the ship the hologram map shows
## trapped miners, through walls, while the module is in a utility slot.
##
##     {"scan_radius_m": 60.0}
##
## The view reads it; core only knows the module's id (`ShipLoadout`), so the
## scanner never changes simulation state (MP-2). `UtilityRadius` checks the
## file, as it does the wide radar's.

const PATH: String = "res://data/utility/mine_scanner.json"
const RADIUS_KEY: String = "scan_radius_m"

## Metres from the ship within which trapped miners are shown; 0 when rejected.
var scan_radius_m: float = 0.0
## Set when the file was rejected, naming the file and the key; empty otherwise.
var error: String = ""


## Reads and checks the file at `path`.
static func load_file(path: String = PATH) -> MineScanner:
	return _from(UtilityRadius.load_file(path, RADIUS_KEY))


## Checks `text`, the contents of the file at `path` (used in messages only).
static func parse(text: String, path: String = PATH) -> MineScanner:
	return _from(UtilityRadius.parse(text, path, RADIUS_KEY))


## The positions in metres of the miners in `trapped` (millimetres, as
## `MinerRescue.trapped` holds them) within `scan_radius_m` of `ship_at`, in
## the order given. Walls are ignored: the scanner sees through rock. A miner
## exactly at the radius counts. A rejected file finds nothing.
func in_range(trapped: Array[Vector3i], ship_at: Vector3) -> PackedVector3Array:
	var found: PackedVector3Array = PackedVector3Array()
	if error != "":
		return found
	for miner: Vector3i in trapped:
		var at: Vector3 = MinerRescue.position_of(miner)
		if at.distance_to(ship_at) <= scan_radius_m:
			found.append(at)
	return found


static func _from(read: Dictionary) -> MineScanner:
	var scanner: MineScanner = MineScanner.new()
	scanner.scan_radius_m = float(read["value"])
	scanner.error = read["error"]
	return scanner
