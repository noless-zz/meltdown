extends RefCounted

## Stands in for `OpenXRInterface` in the refresh-rate tests (#598): the same
## members `RefreshRate` uses, with the rates it offers and every rate asked
## for recorded. Not a test file, so the runner does not load it.

signal refresh_rate_changed(refresh_rate: float)

var rates: Array = []
var requests: Array[float] = []
var display_refresh_rate: float = 90.0:
	set(value):
		requests.append(value)
		display_refresh_rate = value


func _init(p_rates: Array, p_rate: float) -> void:
	rates = p_rates
	display_refresh_rate = p_rate
	requests.clear()


func get_available_display_refresh_rates() -> Array:
	return rates
