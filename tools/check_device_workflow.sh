#!/usr/bin/env bash
# Checks the device acceptance workflow without the owner's runner (#154):
# the YAML parses, it has only the manual and nightly triggers (never pull
# requests or pushes: it runs on the owner's PC), every job on the PC is
# limited to main, and every PowerShell script in tools/ parses.
# Usage: tools/check_device_workflow.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$root/.github/workflows/device-acceptance.yml"

python3 - "$workflow" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    workflow = yaml.safe_load(handle)

problems = []
# PyYAML reads the bare key `on` as the boolean True.
triggers = workflow.get("on", workflow.get(True))
if not isinstance(triggers, dict):
    problems.append("the triggers are not a mapping")
    triggers = {}
if set(triggers) != {"workflow_dispatch", "schedule"}:
    problems.append("triggers must be exactly workflow_dispatch and schedule, found %s" % sorted(triggers))
suite = triggers.get("workflow_dispatch", {}) or {}
if (suite.get("inputs", {}).get("suite", {}) or {}).get("default") != "all":
    problems.append("the manual dispatch needs a suite input that defaults to all")
for name, job in workflow.get("jobs", {}).items():
    runs_on = job.get("runs-on")
    labels = runs_on if isinstance(runs_on, list) else [runs_on]
    if "self-hosted" in labels:
        if labels != ["self-hosted", "quest-pc"]:
            problems.append("job %s must run on [self-hosted, quest-pc]" % name)
        if "refs/heads/main" not in str(job.get("if", "")):
            problems.append("job %s runs on the owner's PC but is not limited to main" % name)
        if "permissions" in job:
            problems.append("job %s on the owner's PC must not widen the token's permissions" % name)
if workflow.get("permissions") != {"contents": "read"}:
    problems.append("the workflow's default permissions must be contents: read")

for problem in problems:
    print("FAIL %s" % problem, file=sys.stderr)
if problems:
    sys.exit(1)
print("ok   %s: triggers, runners and permissions" % path)
PY

# Windows PowerShell 5.1 runs these on the PC; PowerShell 7 parses the same
# grammar, so a syntax error shows up here first.
# The single-quoted text is PowerShell, not bash.
# shellcheck disable=SC2016
TOOLS_DIR="$root/tools" pwsh -NoProfile -NonInteractive -Command '
	$failed = 0
	foreach ($file in Get-ChildItem -Path $env:TOOLS_DIR -Filter *.ps1) {
		$tokens = $null
		$errors = $null
		[System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
		if ($errors.Count -gt 0) {
			$failed += 1
			foreach ($e in $errors) { Write-Host "FAIL $($file.Name):$($e.Extent.StartLineNumber): $($e.Message)" }
		} else {
			Write-Host "ok   $($file.Name) parses"
		}
	}
	exit $failed
'
