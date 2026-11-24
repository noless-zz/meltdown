class_name RoomReverb
extends Node

## Room reverb (#1291, AUD-1): an `AudioEffectReverb` on the effects bus, set
## from the room the ship is in by `RoomReverbTable` and blended by
## `RoomReverbBlend` when it passes into another. The sound cues play on that
## bus, so a shot's echo opens up in a big room and closes in a tunnel.
##
## Pure view: it reads the walls and the ship's position, copies the session
## hands it, and writes nothing back (ARC-1, MP-2). The bus is made here, at
## run time, so the project needs no bus layout resource.

const BUS: StringName = &"Effects"
const SEND_TO: StringName = &"Master"

var table: RoomReverbTable = null
var blend: RoomReverbBlend = null
## The reverb on the effects bus, once `ensure_bus` has run.
var effect: AudioEffectReverb = null
var _last_tick: int = -1


## A reverb for `reverb_table`, null meaning the shipped table; a rejected
## table is printed once and leaves the bus dry.
func _init(reverb_table: RoomReverbTable = null) -> void:
	name = "RoomReverb"
	table = reverb_table if reverb_table != null else RoomReverbTable.load_file()
	if table.error != "":
		print("Meltdown: room reverb off: %s" % table.error)
	blend = RoomReverbBlend.new(table.blend_seconds)


## The effects bus's index, adding the bus (sending to Master) and its reverb
## when they are missing. Calling it again adds nothing.
func ensure_bus() -> int:
	var index: int = AudioServer.get_bus_index(BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, SEND_TO)
	for slot: int in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, slot) is AudioEffectReverb:
			effect = AudioServer.get_bus_effect(index, slot) as AudioEffectReverb
			return index
	effect = AudioEffectReverb.new()
	effect.wet = 0.0  # Dry until the first room is known.
	AudioServer.add_bus_effect(index, effect)
	return index


## Sets the reverb for a ship at `position` in `walls` at simulation `tick`,
## blending by the ticks since the last call. Returns what is heard, null
## before the ship was first in a box.
func follow(walls: BoxUnion, position: Vector3, tick: int) -> ReverbSetting:
	var seconds: float = 0.0
	if _last_tick >= 0 and tick > _last_tick:
		seconds = float(tick - _last_tick) / ShipState.TICK_RATE
	_last_tick = tick
	var heard: ReverbSetting = blend.advance(table.setting_at(walls, position), seconds)
	if heard != null and effect != null:
		heard.apply_to(effect)
	return heard


## Forgets the room, for a new level: its first room is heard at once.
func reset() -> void:
	blend.reset()
	_last_tick = -1
