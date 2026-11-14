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
| `gate` | A milestone gate checklist; only the owner closes it |

## Steps

1. Read `CLAUDE.md`, `docs/requirements.md`, `docs/decisions/` and every devlog entry
   since the last Planner entry.
2. Find the earliest open milestone. Count its open `ready` issues.
3. Shape `triage` and `playtest` issues first: add requirement IDs and acceptance criteria
   an automated test can check, then label `ready`; or label `needs-human` with a clear
   question for the owner.
4. If the current milestone has fewer than five `ready` issues and work remains, write new
   ones from the milestone's scope in `docs/requirements.md`. Each must fit one Builder
   run: one behaviour, a handful of files, a few hundred lines at most.
5. If every issue in the milestone is closed except the `gate` issue, comment on the gate
   issue with the automated criteria and their current status, label it `needs-human`,
   and prepare the first five issues of the next milestone without labelling them `ready`.
6. Never create issues more than one milestone ahead.
7. Update the pinned issue "Status" with: current milestone, issues closed since the last
   update, open pull requests, everything labelled `needs-human` with the question being
   asked, and CI health.
8. On Sundays, add a usage note to the status issue: Builder runs in the past week, how
   many produced a merged pull request, and whether the pace should change (DEV-9).

## Never

Change `docs/requirements.md`, close a gate, or relabel a `needs-human` issue as `ready`
without the owner's answer in the issue thread.
