class_name SoundVoices
extends RefCounted

## The cap on cues sounding at once (#1290, AUD-1, PRF-1): `max_voices` from
## the cue table. A new cue past the cap takes the place of the oldest quiet
## voice (at or below `quiet_db`), so a shower of shots cuts other shots before
## it cuts an explosion; with none quiet, the oldest voice goes.
##
## Voices are counted by a number each start hands out; the player frees a
## voice by its number when its sound ends.

var max_voices: int = 16
var quiet_db: float = -6.0
## The sounding voices, oldest first: [number, volume_db].
var _voices: Array[Array] = []
var _next: int = 0


func _init(p_max_voices: int = 16, p_quiet_db: float = -6.0) -> void:
	max_voices = maxi(p_max_voices, 1)
	quiet_db = p_quiet_db


## Starts a voice at `volume_db`. Returns [its number, the number of the voice
## it replaced or -1].
func start(volume_db: float) -> Array[int]:
	var dropped: int = -1
	if _voices.size() >= max_voices:
		var index: int = 0
		for candidate: int in _voices.size():
			if float(_voices[candidate][1]) <= quiet_db:
				index = candidate
				break
		dropped = _voices[index][0]
		_voices.remove_at(index)
	var number: int = _next
	_next += 1
	_voices.append([number, volume_db])
	return [number, dropped]


## Frees the voice `number`, whose sound ended. Unknown numbers are ignored.
func finish(number: int) -> void:
	for index: int in _voices.size():
		if int(_voices[index][0]) == number:
			_voices.remove_at(index)
			return


## How many voices are sounding.
func count() -> int:
	return _voices.size()


## The sounding voices' numbers, oldest first.
func numbers() -> Array[int]:
	var listed: Array[int] = []
	for voice: Array in _voices:
		listed.append(int(voice[0]))
	return listed
