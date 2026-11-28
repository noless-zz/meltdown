class_name MinerPod
extends RefCounted

## The escape pod a trapped miner sits in (#1308, GFX-2, SLV-3): a small cabin
## of primitives with a lit window under the rescue beacon, so a miner reads
## as someone to rescue and not as another glowing marker. Kept apart from
## `MinerView` so the node stays small. In `miner_look.json`, optional:
##
##     "pod": {"glow_color": [r, g, b], "glow_energy": n, "model": <PickupModel>}
##
## The model's pieces are in metres about the miner's position; its glow
## pieces (the window) take `glow_color`. Without a `pod` the miner is the
## beacon and ring alone, as before. The window is never orange: an orange
## glow near the exit was taken for the reactor (#1208).

const KEY: String = "pod"
const KEYS: Array[String] = ["glow_color", "glow_energy", "model"]
const ENERGY_RANGE: Array[float] = [0.0, 10.0]

var _pod: Dictionary = {}
var _models: PickupModel = PickupModel.new()
var _glow: StandardMaterial3D = null


## `pod` is a parsed entry from `parse`, or empty for no pod.
func _init(pod: Dictionary = {}) -> void:
	_pod = pod
	if not pod.is_empty():
		_glow = MinerView._glow(pod["glow_color"], pod["glow_energy"])


## `{"glow_color": Color, "glow_energy": float, "model": {...}}`, or
## `{"error": ...}` naming the field.
static func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "key \"pod\" must be an object"}
	var data: Dictionary = value
	var problem: String = PickupModel._keys(KEY, data, KEYS, [])
	if problem != "":
		return {"error": problem}
	var color: Variant = MinerLook.parse_color("pod.glow_color", data["glow_color"])
	if typeof(color) == TYPE_STRING:
		return {"error": color}
	problem = MinerLook.check_number("pod.glow_energy", data["glow_energy"], ENERGY_RANGE)
	if problem != "":
		return {"error": problem}
	var model: Dictionary = PickupModel.parse("pod.model", data["model"])
	if model.has("error"):
		return model
	return {"glow_color": color, "glow_energy": float(data["glow_energy"]), "model": model}


## Hangs the pod under `marker`; nothing without a pod.
func dress(marker: Node3D) -> void:
	_models.dress(marker, KEY, _pod.get("model", {}), _glow)


func has_pod() -> bool:
	return not _pod.is_empty()
