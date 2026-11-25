class_name RobotVoiceMix
extends RefCounted

## One robot voice chosen to sound this tick (#1363, AUD-2): where it is, how
## loud and how bright it is heard, and at what pitch. Made by
## `RobotVoicePicker` from session copies; plain data, so tests and the
## acceptance check read the same numbers the player sets.

## The robot's index in the robot list it was picked from.
var robot_index: int = -1
## The robot type id, the key of its `RobotVoiceRow`.
var type_id: String = ""
var sound: String = ""
var position: Vector3 = Vector3.ZERO
## Metres from the listener.
var distance: float = 0.0
## True when no level box holds both robot and listener: a wall may stand between.
var muffled: bool = false
## The volume the player is set to: the row's, plus its `muffle_db` when muffled.
var player_db: float = 0.0
## The level heard at the listener: `player_db` less the inverse-distance
## fall-off past the table's `reference_m`, the law the 3D player applies.
var heard_db: float = 0.0
var pitch: float = 1.0
