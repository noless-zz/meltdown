# 0005 Milestone acceptance and regression

Date: 2026-11-16. Decided by the owner in issue #155 (DEV-6, DEV-7, DEV-1). Written by a
Builder run; the policy is the owner's, this record only writes it down.

## When this applies

The policy below takes effect once the pieces that carry it out have merged. Until then
every gate issue keeps its current wording and nothing about how gates are closed changes.

| Piece | Issue | State on 2026-11-16 |
| --- | --- | --- |
| Suite format and report (`AcceptanceSuite`, `AcceptanceReport`, `m0` and `m1` suites in `game/acceptance/suites/`) | #163 | `ready`, lane-a, not started |
| Launch switch `--acceptance=<suite>` and the intent extra on the headset | #165 | `ready`, lane-b, waits for #163 |
| Frame-time statistics against the refresh-rate budget (PRF-1 to PRF-3) | #164 | `ready`, lane-a, after #163 |
| Device acceptance workflow on the owner's `quest-pc` runner | #154 | open, not shaped; only the owner merges it |

The umbrella issue for the first three is #153. The suites live in
`game/acceptance/suites/`, not `game/tests/acceptance/` as first asked, because every
export preset excludes `tests/*` and the suites must reach the APK (#163).

## The policy

1. **Every milestone has an acceptance suite.** A feature is not done until the step that
   exercises it is in its milestone's suite. `all` runs every suite in name order.
2. **Release candidate.** At the end of a milestone the build is tagged `m<N>-rc`. The
   device acceptance workflow (#154) runs that milestone's suite and the suites of every
   earlier milestone on the Quest 3, and the report is attached to the gate issue.
3. **Automated half of a gate.** Unit tests, the Monado smoke test (decision record 0002)
   and the device suites are all green on the tagged build. This half can be ticked as an
   automated result on the gate issue; it does not close the gate.
4. **Human half of a gate.** Unchanged: the owner's headset session judges feel, comfort
   and fun (DEV-6). Only the owner closes a gate, whatever the automated half shows.
5. **Regression.** A nightly device run executes `all` on `main`. A failure opens one issue
   labelled `playtest` naming the failing suite and step, or updates that issue if it is
   already open. Like every `playtest` issue it outranks new features (DEV-7).
6. **What automation cannot judge is listed on each gate**, so the owner sees exactly what
   is left for him.

## What stays human at every gate

Automation measures what can be measured: that a session starts with two views, that a
replay ends on the recorded state hash, frame times against the budget, comfort limits as
numbers. It cannot judge:

- **Feel:** whether flight, shooting and being hit read clearly and respond well.
- **Comfort:** whether a person, including a VR-sensitive tester, stays comfortable for
  the gate's stated time at each preset. Passing the measured comfort limits (CMF-3,
  CMF-8) is necessary, not sufficient.
- **Fun:** whether the milestone's play is worth playing.

These are the human exit criteria in requirements section 8 and stay on every gate issue.

## Consequences

- Each gate issue names its suite and splits its checklist into the automated half (with
  the `m<N>-rc` report linked) and the human half. The Planner updates the gate issues to
  match once the pieces above have merged; this record does not edit them.
- A milestone's issues are shaped with an acceptance criterion that adds or updates a step
  in that milestone's suite, wherever the behaviour can be driven by a replay or scripted
  input. Behaviour a suite cannot drive yet is named on the gate as human-checked.
- A nightly failure becomes `playtest` work before any new feature in its lane, so a
  regression on the headset is fixed before more is built on top of it.
- The device workflow runs on the owner's PC. It never runs on pull requests, and the
  owner alone merges changes to it (#154, decision record 0003).
- Steps that cannot run in a given place (for example `xr_session` without a runtime) are
  reported as skipped, not passed (#165); a gate's automated half needs them run on the
  headset.

## Open

Proposals for the owner. None of these is made by this record; each would be its own pull
request that the owner approves, because `docs/routines/` is protected.

- **Builder routine:** add to step 6 "if the issue adds behaviour a suite can drive, add or
  update its step in the milestone's suite", so policy point 1 is carried out by the run
  that builds the feature.
- **Planner routine, step 3:** shape every new feature issue with the suite step it adds,
  and treat a nightly `playtest` regression issue as already shaped once it names the
  failing step.
- **Planner routine, step 6:** before labelling a gate `needs-human`, check that the
  `m<N>-rc` tag exists and its device report is attached and green; list the human half
  separately.
- **Reviewer routine:** check that a feature pull request adds its suite step, or says why
  a suite cannot drive it yet.
- **Not covered by any issue yet:** creating the `m<N>-rc` tag, running the device suites
  on that tag rather than on `main-latest` (#154 installs from `main-latest`), and the
  nightly run opening or updating the `playtest` issue (#154 comments on the gate issue
  instead). The Planner should file these once #154 is shaped.
