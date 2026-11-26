class_name ChecklistMarkdown
extends RefCounted

## The `docs/checklists/` copy of a checklist file (#1325): the same steps as
## the headset shows, so a reader at the PC and the pilot work from one text.
## `tests/checklist_docs.gd` writes it and `test_checklist_docs.gd` fails when
## a shipped checklist and its copy differ, so the two cannot drift.

const DOCS_DIR: String = "docs/checklists"


## The copy's file name for `checklist`.
static func file_name(checklist: Checklist) -> String:
	return "%s.md" % checklist.id


## Where the copy of `checklist` lives in the repository, beside `game/`.
static func docs_path(checklist: Checklist) -> String:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return root.path_join(DOCS_DIR).path_join(file_name(checklist))


static func render(checklist: Checklist, source_path: String) -> String:
	var lines: Array[String] = ["# %s" % checklist.title, ""]
	lines.append("Generated from `%s` by `tools/checklist_docs.sh`; edit that file, not this one." % source_path)
	lines.append("In a development build: dev menu, Test checklist. Results are saved on the headset in")
	lines.append("`meltdown_checklist_%s.json` under the app's `user://` folder." % checklist.id)
	if checklist.issue > 0:
		lines.append("Results belong on issue #%d." % checklist.issue)
	if not checklist.remarks.is_empty():
		lines.append("")
		lines.append("Remarks offered: %s." % ", ".join(checklist.remarks))
	var part: int = -1
	var number: int = 0
	for step: ChecklistStep in checklist.steps:
		if step.part != part:
			part = step.part
			lines.append("")
			lines.append("## %s" % checklist.parts[part])
			lines.append("")
		number += 1
		lines.append("%d. **%s** (`%s`)" % [number, step.do_text, step.id])
		lines.append("   - Look for: %s" % step.look_for)
		if step.action_text() != "":
			lines.append("   - The game can: %s" % step.action_text())
		if step.remarks != checklist.remarks and not step.remarks.is_empty():
			lines.append("   - Remarks: %s" % ", ".join(step.remarks))
	lines.append("")
	return "\n".join(lines)
