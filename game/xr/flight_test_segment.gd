class_name FlightTestSegment
extends RefCounted

## One short segment of the first-launch flight test (CMF-4): what the ship
## does for how long, and which comfort preset that much motion stands for.
## Built by `FlightTestPlan` from its data file, never by hand in game code.

## Unique name of the segment within its plan, used by the question panel.
var id: String = ""
## Comfort preset this segment represents, 1..4.
var preset: int = 1
## How long the segment flies, seconds.
var duration_s: float = 0.0
## What the ship does, one of `FlightTestPlan.MANOEUVRES`.
var manoeuvre: String = ""


func _init(segment_id: String = "", segment_preset: int = 1, seconds: float = 0.0, move: String = "") -> void:
	id = segment_id
	preset = segment_preset
	duration_s = seconds
	manoeuvre = move
