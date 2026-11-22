class_name SimRules
extends RefCounted

## What a run fixes before its first tick: the walls, the rule sets and the
## part catalogue, which `Sim` holds and its setters fill (#1154). None changes
## afterwards, so a replay can set the same ones from its header alone (ARC-2).
## Each setter takes `locked`, true once the run has started or while a tick is
## being stepped, and then refuses and changes nothing.
##
## No nodes, files or randomness (ARC-1): the caller resolves every data file.

## Walls everything flies inside, or null for open space (GEN-5). Not hashed:
## fixed for the run, like the rule sets below.
var walls: BoxUnion = null
## The first box of `walls`, or null, for older single-box callers.
var bounds: BoxBounds = null
## How parts are picked up, pulled and dropped (#600). Not part of the hash:
## fixed for the run and recorded in the replay's header, like the walls; what
## they do to the parts shows in the parts' own state.
var salvage_rules: SalvageRules = SalvageRules.new()
## How far and how fast ships' guns follow their aim (CMB-6). Not part of the
## hash, like the salvage rules: what it does shows in each ship's gun direction.
var look_aim: LookAim = LookAim.new()
## How shots of ships with the aim assist module bend (CMB-7, #1096). Not part
## of the hash, like `look_aim`.
var aim_assist: AimAssist = AimAssist.new()
## Part id to the weapon that part is (SLV-1, ARC-4). Read through `part` and
## `part_ids`; part of the sim's hash while non-empty.
var _parts: Dictionary[String, WeaponDef] = {}


## Sets the walls to `p_walls`, a union of one or more boxes, or null for open
## space. Returns false, changing nothing, when locked or for a union with no
## boxes (no space to fly in at all).
func set_walls(p_walls: BoxUnion, locked: bool) -> bool:
	if locked:
		return false
	if p_walls != null and p_walls.boxes.is_empty():
		return false
	walls = p_walls
	bounds = null if p_walls == null else p_walls.boxes[0]
	return true


## Sets the part catalogue from `parts`, a Dictionary from part id to its
## resolved `WeaponDef`. Returns "" on success, or a problem naming the part;
## on any problem the catalogue is left unchanged.
func set_parts(parts: Dictionary, locked: bool) -> String:
	if locked:
		return "the part catalogue is set before the first tick"
	var checked: Dictionary[String, WeaponDef] = {}
	for id: Variant in parts:
		if typeof(id) != TYPE_STRING:
			return "part id %s is not a string" % str(id)
		var id_problem: String = ShipLoadout.check_id("part id", id)
		if id_problem != "":
			return id_problem
		var weapon: Variant = parts[id]
		if not weapon is WeaponDef or (weapon as WeaponDef).error != "":
			return "part \"%s\" is not a resolved weapon" % id
		checked[id] = weapon
	_parts = checked
	return ""


## Sets the salvage rules. Returns "" on success, or the problem, changing nothing.
func set_salvage_rules(rules: SalvageRules, locked: bool) -> String:
	if locked:
		return "the salvage rules are set before the first tick"
	if rules == null or rules.error != "":
		return "the salvage rules are not resolved"
	salvage_rules = rules
	return ""


## Sets the look-aim cone and gimbal rate. Returns "" or the problem, changing nothing.
func set_look_aim(aim: LookAim, locked: bool) -> String:
	if locked:
		return "look-aim is set before the first tick"
	if aim == null or aim.error != "":
		return "look-aim is not resolved"
	look_aim = aim
	return ""


## Sets the aim assist cone and range. Returns "" or the problem, changing nothing.
func set_aim_assist(assist: AimAssist, locked: bool) -> String:
	if locked:
		return "aim assist is set before the first tick"
	if assist == null or assist.error != "":
		return "aim assist is not resolved"
	aim_assist = assist
	return ""


## The weapon part `id` is, or null if the catalogue has no such part.
func part(id: String) -> WeaponDef:
	return _parts.get(id, null)


## Every part id in the catalogue, sorted, so callers and the hash see one order.
func part_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_parts.keys())
	ids.sort()
	return ids
