class_name HitFlash
extends RefCounted

## Makes every shot that hits the local ship readable on every comfort preset
## without moving the view (#618; CMB-2, CMF-1, CMF-8, PLT-6): it picks the
## side the shot came from, times a brief edge flash on that side, and says
## which status bar flashes, the shield's if the shield took the shot, the
## hull's if the hull did. Shake stays as each preset sets it (`HitShake`);
## nothing here touches the camera.
##
## It only reads `SimEvent`s and plain shield and hull values, never `Sim`
## (ARC-3, MP-2). Durations and colours live in `res://xr/hit_flash.json`.

const DEFAULT_FILE: String = "res://xr/hit_flash.json"

const LEFT: String = "left"
const RIGHT: String = "right"
const TOP: String = "top"
const BOTTOM: String = "bottom"
## Straight ahead, or straight behind, where no edge points the way: all four
## edges flash at once and both hands pulse.
const FRONT: String = "front"
const SIDES: Array[String] = [LEFT, RIGHT, TOP, BOTTOM, FRONT]
const SHIELD: String = "shield"
const HULL: String = "hull"
## A shot from behind whose sideways part is smaller than this fraction of its
## direction (about 11 degrees off straight behind) has no side worth
## pointing at, so it reads as `FRONT`, the ring around the view.
const BEHIND_SIDE_MIN: float = 0.2

## How long an edge flash lasts, seconds, 0.05..1. It fades out linearly.
var edge_seconds: float = 0.25
var edge_color: Color = Color(1.0, 0.25, 0.15)
## Opacity of the edge at the start of the flash, 0..1.
var edge_alpha: float = 0.55
## From the view's centre to the inner edge of a strip, metres at the
## overlay's distance, 0.02..0.2; and the strip's width, 0.01..0.2.
var edge_inset_m: float = 0.055
var edge_width_m: float = 0.07
## How long a status bar flashes, seconds, 0.05..1.
var bar_seconds: float = 0.35
var bar_color: Color = Color(1.0, 1.0, 1.0)

const NUMBER_KEYS: Array[String] = [
	"edge_seconds", "edge_alpha", "edge_inset_m", "edge_width_m", "bar_seconds",
]
const COLOR_KEYS: Array[String] = ["edge_color", "bar_color"]
## Allowed range of each number key, inclusive: [minimum, maximum].
const RANGES: Dictionary[String, Array] = {
	"edge_seconds": [0.05, 1.0],
	"edge_alpha": [0.0, 1.0],
	"edge_inset_m": [0.02, 0.2],
	"edge_width_m": [0.01, 0.2],
	"bar_seconds": [0.05, 1.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""

## The side of the latest hit, "" before the first.
var side: String = ""
var _edge_left_s: float = 0.0
var _shield_left_s: float = 0.0
var _hull_left_s: float = 0.0
## The shield and hull last fed, so a hit can tell which one it took; -1
## before the first feed.
var _last_shield: float = -1.0
var _last_hull: float = -1.0


## Parses the text of a hit-flash data file: one JSON object holding every
## key in `NUMBER_KEYS` as a number in its range and every key in
## `COLOR_KEYS` as three numbers 0..1, and nothing else. On failure the
## returned flash has `error` set, naming the field, and default values.
static func parse_json(text: String) -> HitFlash:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (NUMBER_KEYS.has(key) or COLOR_KEYS.has(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	var flash: HitFlash = HitFlash.new()
	for key: String in NUMBER_KEYS + COLOR_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	for key: String in NUMBER_KEYS:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(value) < low or float(value) > high:
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, value, low, high])
		flash.set(key, float(value))
	for key: String in COLOR_KEYS:
		var value: Variant = data[key]
		if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
			return _rejected("key \"%s\" must be three numbers 0..1" % key)
		for part: Variant in value:
			if (typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT) or float(part) < 0.0 or float(part) > 1.0:
				return _rejected("key \"%s\" must be three numbers 0..1" % key)
		flash.set(key, Color(float(value[0]), float(value[1]), float(value[2])))
	return flash


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> HitFlash:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var flash: HitFlash = parse_json(FileAccess.get_file_as_string(path))
	if flash.error != "":
		flash.error = "%s: %s" % [path, flash.error]
	return flash


## The side a shot flying along `flight` (world space, as `SimEvent.vector`
## gives it) came from, on a ship turned by `ship_basis`. The shot came from
## the opposite way it flies; that way is read in the ship's own frame, where
## forward is -Z, right +X and up +Y.
static func side_for(flight: Vector3, ship_basis: Basis) -> String:
	var basis: Basis = ship_basis.orthonormalized() if ship_basis.determinant() != 0.0 else Basis.IDENTITY
	var from: Vector3 = basis.inverse() * -flight
	if from.length_squared() == 0.0 or not from.is_finite():
		return FRONT
	from = from.normalized()
	var across: float = maxf(absf(from.x), absf(from.y))
	if -from.z >= across:
		return FRONT
	if from.z > 0.0 and across < BEHIND_SIDE_MIN:
		return FRONT
	if absf(from.x) >= absf(from.y):
		return RIGHT if from.x > 0.0 else LEFT
	return TOP if from.y > 0.0 else BOTTOM


## Takes in the events of one session advance and the local ship's shield and
## hull after it. Every `SHIP_HIT` on ship `ship` starts the edge flash on its
## side (a later hit replaces an earlier one still fading) and is returned, one
## side per hit, in event order. The shield bar flashes if the shield fell over
## the advance, the hull bar if the hull did; with neither known to have
## fallen, the shield's if it is up, else the hull's.
func feed(events: Array[SimEvent], ship: int, ship_basis: Basis, shield: float, hull: float) -> Array[String]:
	var sides: Array[String] = []
	for event: SimEvent in events:
		if event != null and event.ship == ship and event.kind == SimEvent.Kind.SHIP_HIT:
			sides.append(side_for(event.vector, ship_basis))
	if not sides.is_empty():
		side = sides[-1]
		_edge_left_s = edge_seconds
		var shield_fell: bool = _last_shield >= 0.0 and shield < _last_shield
		var hull_fell: bool = _last_hull >= 0.0 and hull < _last_hull
		if shield_fell or (not hull_fell and shield > 0.0):
			_shield_left_s = bar_seconds
		if hull_fell or (not shield_fell and shield <= 0.0):
			_hull_left_s = bar_seconds
	_last_shield = shield
	_last_hull = hull
	return sides


## Runs the flashes by `delta` seconds.
func advance(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	_edge_left_s = maxf(_edge_left_s - step, 0.0)
	_shield_left_s = maxf(_shield_left_s - step, 0.0)
	_hull_left_s = maxf(_hull_left_s - step, 0.0)


## Opacity of the edge flash now, `edge_alpha` at the hit falling to 0.
func edge_opacity() -> float:
	return edge_alpha * _edge_left_s / edge_seconds


## How much of `bar_color` to mix over the shield (`SHIELD`) or hull (`HULL`)
## bar now: 1 at the hit falling to 0.
func bar_amount(bar: String) -> float:
	var left: float = _hull_left_s if bar == HULL else _shield_left_s
	return left / bar_seconds


static func _rejected(message: String) -> HitFlash:
	var flash: HitFlash = HitFlash.new()
	flash.error = message
	return flash
