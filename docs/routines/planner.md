# Planner routine

One run keeps the backlog small, ordered and ready, and tells the owner where things stand.

## Labels

| Label | Meaning |
| --- | --- |
| `ready` | Has requirement IDs and testable acceptance criteria; the Builder may take it |
| `triage` | New or unclear; the Planner must shape it before it is `ready` |
| `in-progress` | A Builder run is working on it right now |
| `needs-human` | Blocked on the owner: a decision, a headset session, a secret, or a protected path |
| `playtest` | Feedback from a headset session; outranks new features (DEV-7) |
| `approved` | The Reviewer's verdict on a pull request; set and cleared only by the Reviewer |
| `lane-a`, `lane-b`, `lane-c` | Which Builder lane takes the issue; exactly one per `ready` issue |
| `gate` | A milestone gate checklist; only the owner closes it |

## Steps

1. Read `CLAUDE.md`, `docs/requirements.md`, `docs/decisions/` and every devlog entry
   since the last Planner entry.
2. Find the earliest open milestone. Count its open `ready` issues.
3. Shape `triage` and `playtest` issues first: add requirement IDs and acceptance criteria
   an automated test can check, then label `ready`; or label `needs-human` with a clear
   question for the owner. A feature issue also names the acceptance-suite step it adds
   or updates, wherever a replay or scripted input can drive the behaviour (decision
   record 0005). A `playtest` issue opened by the nightly device run counts as shaped
   once it names the failing suite and step: give it a lane and label it `ready`.
4. Keep at least three `ready` issues in every lane while work remains. Write new ones
   from the milestone scope in `docs/requirements.md`. Each must fit one Builder run: one
   behaviour, a handful of files, a few hundred lines at most.
5. Give every `ready` issue exactly one lane label. Issues that edit the same files, or
   where one builds on the other, go in the same lane, in the order they must be done.
   Different lanes must not edit the same files. Changes to `.github/workflows/` all go
   in one lane. Balance the lanes so none runs dry.
6. If every issue in a milestone is closed except the `gate` issue, comment on the gate
   issue with the automated criteria and their status, list everything the owner must
   check in a headset (collected from the merged pull requests' "Needs a headset check"
   sections), and label it `needs-human`. Keep the two halves apart on the gate
   (decision record 0005): the automated half says whether unit tests, the Monado smoke
   test and the device suites are green, on the `m<N>-rc` build if that tag exists and
   otherwise on `main`, with the report linked, or says plainly which of these has not
   run yet; the human half lists what only the owner can judge.
   - Normally: prepare the first five issues of the next milestone without labelling
     them `ready`, and never create issues more than one milestone ahead.
   - While away mode is on (decision record 0003): an open gate does not stop planning.
     Open the next milestone and label its issues `ready`, up to two milestones past the
     oldest gate that is still open. Prefer work that can be checked by automated tests,
     and keep anything that depends on the owner's judgement of feel or comfort
     adjustable through data files.
7. Update the pinned issue "Status" with: current milestone, issues closed since the last
   update, open pull requests, everything labelled `needs-human` with the question being
   asked, and CI health.
8. On Sundays, add a usage note to the status issue: Builder runs in the past week, how
   many produced a merged pull request, and whether the pace should change (DEV-9).

## Never

Change `docs/requirements.md`, close a gate or a milestone whose gate is open, or relabel a `needs-human` issue as `ready`
without the owner's answer in the issue thread.
