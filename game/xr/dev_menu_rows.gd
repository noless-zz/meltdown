class_name DevMenuRows
extends RefCounted

## Which list the development menu shows and where its highlight is (#1301):
## the top list (a row per section, then the entries in no section) or one
## section (a Back row, then its entries), with at most `max_rows_visible`
## rows on screen, scrolled so the highlight stays on it. Split from
## `DevMenuModel`, which keeps what each press does. No nodes, and nothing
## here reads or writes the simulation (MP-2, ARC-3).
##
## A row is an int: an entry's index in `spec.entries` (0 or more), `BACK`,
## or a section row (`section_row`). With no sections in the file the top
## list is every entry, as before #1301.

const BACK: int = -1
const TOP: int = -1

var spec: DevMenuSpec
## The section shown, by index in `spec.sections`, or `TOP` for the top list.
var section: int = TOP
## The highlighted row.
var selected: int = 0
## The list's row shown first on screen.
var first: int = 0

## Whether entry index `index` shows now; the model hides the update and
## Return to base rows while they have nothing to do.
var _is_shown: Callable


func _init(p_spec: DevMenuSpec, is_shown: Callable) -> void:
	spec = p_spec
	_is_shown = is_shown


## The row that opens section `index`.
static func section_row(index: int) -> int:
	return -2 - index


## The section a row opens, or -1 for an entry or Back row.
static func section_of(row: int) -> int:
	return -2 - row if row <= -2 else -1


## Back to the top list, its first row highlighted.
func to_top() -> void:
	section = TOP
	first = 0
	var shown: Array[int] = rows()
	selected = shown[0] if not shown.is_empty() else 0


## Shows section `index`, its first entry highlighted (the Back row when it has none shown).
func open_section(index: int) -> void:
	section = index
	first = 0
	var shown: Array[int] = rows()
	selected = shown[1] if shown.size() > 1 else BACK
	keep_in_view()


## Leaves a section for the top list, highlighting the row that opened it.
func back() -> void:
	var from: int = section
	to_top()
	if from != TOP:
		selected = section_row(from)
	keep_in_view()


## The rows of the list shown, top to bottom, hidden entries left out.
func rows() -> Array[int]:
	return _rows(false)


## The rows on screen: at most `spec.max_rows_visible` from `first`.
func visible_rows() -> Array[int]:
	var shown: Array[int] = rows()
	return shown.slice(first, mini(first + spec.max_rows_visible, shown.size()))


## Moves the highlight one shown row in `direction`, wrapping.
func step(direction: int) -> void:
	var shown: Array[int] = rows()
	if shown.is_empty():
		return
	var at: int = shown.find(selected)
	selected = shown[posmod(at + direction, shown.size())] if at != -1 else shown[0]
	keep_in_view()


## A highlighted row that has just been hidden passes the highlight on to the
## next shown row below it, wrapping.
func leave_hidden() -> void:
	if rows().has(selected):
		return
	var every: Array[int] = _rows(true)
	var at: int = every.find(selected)
	for offset: int in range(1, every.size() + 1):
		var row: int = every[posmod(at + offset, every.size())]
		if _shown(row):
			selected = row
			break
	keep_in_view()


## Scrolls the list just enough that the highlighted row is on screen.
func keep_in_view() -> void:
	var shown: Array[int] = rows()
	var at: int = maxi(shown.find(selected), 0)
	var count: int = spec.max_rows_visible
	if at < first:
		first = at
	elif at >= first + count:
		first = at - count + 1
	first = clampi(first, 0, maxi(shown.size() - count, 0))


func _rows(with_hidden: bool) -> Array[int]:
	var list: Array[int] = []
	if section == TOP:
		for index: int in spec.sections.size():
			list.append(section_row(index))
		var sectioned: Array[String] = spec.sectioned_kinds()
		for index: int in spec.entries.size():
			if not sectioned.has(str(spec.entries[index]["kind"])):
				list.append(index)
	else:
		list.append(BACK)
		for kind: String in spec.sections[section]["kinds"]:
			list.append(_entry_index(kind))
	if with_hidden:
		return list
	var shown: Array[int] = []
	for row: int in list:
		if _shown(row):
			shown.append(row)
	return shown


## A section row shows while one of its entries does, so a section with
## nothing for this place is left out (#1450); Back always shows.
func _shown(row: int) -> bool:
	var opens: int = section_of(row)
	if opens != -1:
		for kind: String in spec.sections[opens]["kinds"]:
			if _shown(_entry_index(kind)):
				return true
		return false
	return row < 0 or bool(_is_shown.call(row))


func _entry_index(kind: String) -> int:
	for index: int in spec.entries.size():
		if str(spec.entries[index]["kind"]) == kind:
			return index
	return BACK
