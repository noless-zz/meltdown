class_name HubScreenMeasure
extends RefCounted

## The arithmetic behind "can the home base screens be read" (#1359, CRW-2):
## the contrast ratio between two colours, the capital height of a `Label3D`,
## the angle a height subtends at a distance and the pixels it covers on the
## Quest 3's eye buffer. Shared by the screens' unit tests and the
## `hub_screens` acceptance check, so both hold the screens to one formula.

## The WCAG 2 relative luminance of `color` (sRGB, alpha ignored).
static func luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


## The WCAG 2 contrast ratio between two colours, 1 (equal) to 21 (black on white).
static func contrast(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The height of a capital letter, in metres, of a label of `font_size` and
## `pixel_size` under a uniform `scale`.
static func cap_height_m(font_size: float, pixel_size: float, cap_ratio: float, scale: float = 1.0) -> float:
	return font_size * pixel_size * cap_ratio * scale


## The angle, in degrees, a height of `height_m` subtends at `distance_m`.
static func angle_deg(height_m: float, distance_m: float) -> float:
	if distance_m <= 0.0:
		return 180.0
	return rad_to_deg(2.0 * atan(height_m * 0.5 / distance_m))


## The height needed at `distance_m` to subtend `degrees`.
static func height_for_deg(degrees: float, distance_m: float) -> float:
	return 2.0 * distance_m * tan(deg_to_rad(degrees) * 0.5)


## The pixels a height of `height_m` at `distance_m`, straight ahead, covers on
## an eye buffer `rows` pixels tall over `fov_deg` degrees.
static func pixels(height_m: float, distance_m: float, fov_deg: float, rows: float) -> float:
	if distance_m <= 0.0:
		return rows
	return height_m / (2.0 * distance_m * tan(deg_to_rad(fov_deg) * 0.5)) * rows


## The transform of `node` in `ancestor`'s space, read from the local
## transforms, so it works out of the scene tree too. Identity when `ancestor`
## is not above `node`.
static func in_space_of(node: Node3D, ancestor: Node) -> Transform3D:
	var at: Transform3D = Transform3D.IDENTITY
	var each: Node = node
	while each != null and each != ancestor:
		if each is Node3D:
			at = (each as Node3D).transform * at
		each = each.get_parent()
	return at if each == ancestor else Transform3D.IDENTITY


## Each visible `Label3D` under `root` with how it reads from `ancestor`'s
## origin (the seated eye): {"text", "node", "cap_m", "distance_m", "deg", "px"}.
static func label_sizes(root: Node, ancestor: Node, cap_ratio: float, fov_deg: float, rows: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for child: Node in root.find_children("*", "Label3D", true, false):
		var label: Label3D = child as Label3D
		if not shown_under(label, ancestor) or label.text.strip_edges() == "":
			continue
		var at: Transform3D = in_space_of(label, ancestor)
		var scale: float = at.basis.get_scale().y
		var cap: float = cap_height_m(label.font_size, label.pixel_size, cap_ratio, scale)
		var distance: float = at.origin.length()
		found.append({"text": label.text, "node": label, "cap_m": cap, "distance_m": distance,
			"deg": angle_deg(cap, distance), "px": pixels(cap, distance, fov_deg, rows)})
	return found


## True when `node` and every node up to `ancestor` are visible; read from the
## nodes, so it works out of the scene tree too.
static func shown_under(node: Node, ancestor: Node) -> bool:
	var each: Node = node
	while each != null and each != ancestor:
		if each is Node3D and not (each as Node3D).visible:
			return false
		each = each.get_parent()
	return true


static func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)
