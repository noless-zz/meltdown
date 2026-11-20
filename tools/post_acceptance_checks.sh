#!/usr/bin/env bash
# Checks tools/post_acceptance.ps1, the report job of the device acceptance
# workflow (#154, #669), in dry-run mode. Called by test_device_acceptance.sh
# with two results folders it built: one with a failing headset step and one
# where everything passed. Needs pwsh.
# Not named test_*.sh: CI runs those without arguments.
# Usage: tools/post_acceptance_checks.sh <failing-results> <passing-results>
set -euo pipefail

tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
results="$1"
passing="$2"
failures=0
output=""
status=0

pass() {
	echo "ok   $1"
}

fail() {
	echo "FAIL $1" >&2
	echo "$output" >&2
	failures=$((failures + 1))
}

# The report job: one table with both columns; issues only on the nightly run.
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$tools/post_acceptance.ps1" -ResultsDir "$results" \
	-Suite m1 -EventName workflow_dispatch -Repository owner/repo -DryRun 2>&1)" || status=$?
if [ "$status" -eq 0 ] && grep -q "| Suite | Step | Headset | Simulator |" <<< "$output" \
	&& grep -q "| m1 | basic_flight | fail: final_hash: final hash 861662111 | not run |" <<< "$output" \
	&& ! grep -q "DRY RUN" <<< "$output"; then
	pass "report, manual run: both columns, no issue calls"
else
	fail "report, manual run: both columns, no issue calls"
fi
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$tools/post_acceptance.ps1" -ResultsDir "$results" \
	-Suite m1 -EventName schedule -Repository owner/repo -DryRun 2>&1)" || status=$?
if [ "$status" -eq 0 ] && grep -q "DRY RUN GET issues?state=open&labels=gate" <<< "$output" \
	&& grep -q "DRY RUN POST issues$" <<< "$output" \
	&& grep -q "Nightly device acceptance fails: headset m1/basic_flight" <<< "$output" \
	&& grep -q '"playtest"' <<< "$output"; then
	pass "report, nightly failure: opens a playtest issue naming suite and step"
else
	fail "report, nightly failure: opens a playtest issue naming suite and step"
fi

# The nightly report against canned GitHub answers (#669): two gates in
# different milestones and one without, so the lowest milestone must win; an
# open regression issue is reused, never duplicated.
post_fixtures="$tools/fixtures/post_acceptance"
run_post() {
	status=0
	output="$(pwsh -NoProfile -NonInteractive -File "$tools/post_acceptance.ps1" -ResultsDir "$1" \
		-Suite m1 -EventName schedule -Repository owner/repo -DryRun -DryRunFixture "$2" 2>&1)" || status=$?
}

run_post "$results" "$post_fixtures/with_regression.json"
if [ "$status" -eq 0 ] && grep -q "DRY RUN GET issues/900/comments" <<< "$output" \
	&& grep -q "DRY RUN PATCH issues/comments/5001$" <<< "$output" \
	&& grep -q "Replaced the result comment on gate #900" <<< "$output" \
	&& ! grep -q "issues/901/\|issues/comments/6001\|issues/902" <<< "$output"; then
	pass "report, nightly with gates: replaces its comment on the lowest milestone's gate only"
else
	fail "report, nightly with gates: replaces its comment on the lowest milestone's gate only"
fi
if [ "$status" -eq 0 ] && grep -q "DRY RUN POST issues/950/comments$" <<< "$output" \
	&& grep -q "Commented on the open regression issue #950" <<< "$output" \
	&& ! grep -q "DRY RUN POST issues$" <<< "$output" \
	&& ! grep -q "issues/94[05]/" <<< "$output"; then
	pass "report, nightly failure with an open regression issue: comments on it, opens none"
else
	fail "report, nightly failure with an open regression issue: comments on it, opens none"
fi

run_post "$results" "$post_fixtures/no_regression.json"
if [ "$status" -eq 0 ] && grep -q "DRY RUN POST issues/900/comments$" <<< "$output" \
	&& grep -q "DRY RUN POST issues$" <<< "$output" \
	&& grep -q "Nightly device acceptance fails: headset m1/basic_flight" <<< "$output" \
	&& ! grep -q "issues/940/" <<< "$output"; then
	pass "report, nightly failure without a regression issue: comments on the gate, opens one"
else
	fail "report, nightly failure without a regression issue: comments on the gate, opens one"
fi

# A passing run with gates comments on the gate and stops there.
run_post "$passing" "$post_fixtures/with_regression.json"
if [ "$status" -eq 0 ] && grep -q "DRY RUN PATCH issues/comments/5001$" <<< "$output" \
	&& ! grep -q "labels=playtest" <<< "$output"; then
	pass "report, nightly pass: gate comment only, no regression lookup"
else
	fail "report, nightly pass: gate comment only, no regression lookup"
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures report check(s) failed" >&2
	exit 1
fi
