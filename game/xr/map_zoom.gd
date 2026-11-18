class_name MapZoom
extends RefCounted

## How far the map hologram is zoomed in (MAP-1, #549): a factor starting at
## 1.0 that a held control moves exponentially, so each second of holding
## multiplies or divides the map's size by the same amount whatever the zoom
## already is. That keeps zooming feeling even at both ends, where a linear
## rate would crawl at the top and race at the bottom.
##
## Pure view state: it holds a number and touches no node, session or comfort
## setting (ARC-3, CMF-6, MP-2). Which control drives `change` is the owner's
## question (#314); the later wiring binds it through the layout file.
##
## The limits and rate come from `min_zoom`, `max_zoom` and `zoom_per_second`
## in `res://xr/map_look.json` (ARC-4), as `MapLook` parses them.

## The zoom of a freshly shown map: the fitted cube of `size_m`.
const START: float = 1.0

## The current zoom factor, within `[min_zoom, max_zoom]`.
var factor: float = START
var min_zoom: float = MapLook.FALLBACK["min_zoom"]
var max_zoom: float = MapLook.FALLBACK["max_zoom"]
## Factor gained per second at full `direction`: 1.5 means 1.5x bigger after
## one second of zooming in, 1.5x smaller after one second zooming out.
var zoom_per_second: float = MapLook.FALLBACK["zoom_per_second"]


## Takes the limits and rate from a parsed `look` and re-clamps the factor.
func use_look(look: Dictionary) -> void:
	min_zoom = float(look["min_zoom"])
	max_zoom = float(look["max_zoom"])
	zoom_per_second = float(look["zoom_per_second"])
	factor = clampf(factor, min_zoom, max_zoom)


## Zooms in for a positive `direction`, out for a negative one, for `delta_s`
## seconds; `direction` is clamped to -1..1 so a stick's full tilt is full rate.
## Returns the new factor.
func change(direction: float, delta_s: float) -> float:
	var step: float = clampf(direction, -1.0, 1.0) * maxf(delta_s, 0.0)
	factor = clampf(factor * pow(zoom_per_second, step), min_zoom, max_zoom)
	return factor


## Back to the fitted size.
func reset() -> void:
	factor = clampf(START, min_zoom, max_zoom)


## `fit` (level -> hologram space) scaled by `zoom` about the hologram's
## origin, which is the hand anchor, so the point held there stays in the hand.
static func scaled(fit: Transform3D, zoom: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * zoom), Vector3.ZERO) * fit
