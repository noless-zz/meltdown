class_name ChecklistFixtures
extends RefCounted

## A small checklist for the checklist tests (#1325): three steps in one part,
## the first with a comfort action and the checklist's remarks.

const TEXT: String = '{"id": "t1", "title": "T", "issue": 7, "remarks": ["unclear", "broken"], "parts": [{"title": "P", "steps": [' \
	+ '{"id": "a", "do": "A", "look_for": "a", "action": {"comfort": 1}}, {"id": "b", "do": "B", "look_for": "b"}, ' \
	+ '{"id": "c", "do": "C", "look_for": "c", "action": {"seed": 31}}]}]}'


static func checklist() -> Checklist:
	return Checklist.parse(TEXT)


static func session() -> ChecklistSession:
	return ChecklistSession.new(checklist())
