class_name HubWindow
extends RefCounted

## Which rows a station screen shows (#1300, CMF-8): at most a fixed number at
## once, scrolled only as far as the selection needs, so the rows stay put while
## the selection moves inside the window. A header (a row that cannot be
## selected) directly above the window comes into view with the row under it.


## The first row shown, given the previous first row `top`, the `selected` row
## (-1 for none), which rows can be selected, and the rows `shown` at once.
static func scrolled(top: int, selected: int, selectable: Array[bool], shown: int) -> int:
	var count: int = selectable.size()
	if count <= shown:
		return 0
	var first: int = clampi(top, 0, count - shown)
	if selected < 0:
		return first
	if selected < first:
		first = selected
		while first > 0 and not selectable[first - 1] and selected - (first - 1) < shown:
			first -= 1
	elif selected >= first + shown:
		first = selected - shown + 1
	return clampi(first, 0, count - shown)
