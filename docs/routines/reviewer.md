# Reviewer routine

One run reviews every open pull request that has green CI and no review since its last
commit. The Reviewer has not seen the work being produced; review from the diff, the issue
and the requirements only.

## Steps

1. Read `CLAUDE.md` and `docs/requirements.md`.
2. For each open pull request, oldest first:
   1. Skip it if CI is not green or it already has a review newer than its last commit.
   2. Read the linked issue and the full diff.
   3. Check, in this order:
      - Every acceptance criterion in the issue is met, and each testable one has a test.
      - Layer rules: nothing in `core/` or `gen/` touches nodes, rendering, input, audio,
        wall-clock time or unseeded randomness; comfort code is only in `xr/`.
      - Determinism: no iteration over unordered collections that affects simulation state.
      - No protected path is changed unless the issue asks for it.
      - No new dependency or asset without an entry in `docs/licences.md`.
      - Nothing from the original Descent games (NAM-3); no secrets.
      - The tests would fail if the feature were broken.
      - A feature pull request adds or updates its step in the milestone's acceptance
        suite, or says why no suite can drive the behaviour yet (decision record 0005).
   4. Post one verdict as a pull request comment starting with `Reviewer: approved` or
      `Reviewer: changes requested`, the latter with a numbered list of specific,
      checkable items. Add the label `approved` or remove it to match. Scheduled runs
      share one GitHub identity, and GitHub does not let an account approve its own pull
      request, so the comment and label are the review of record. Do not rewrite the
      code yourself.
3. Squash-merge a pull request labelled `approved` that has green CI and changes only
   unprotected paths. If it has a merge conflict with `main`, do not merge; comment
   `Reviewer: changes requested` asking for a rebase.
   - A change under `.github/workflows/` may also be merged when all of these hold: the
     linked issue explicitly permits editing workflows; no job runs on a self-hosted
     runner (`self-hosted` or `quest-pc` appears nowhere in the changed files under
     `.github/workflows/`; the words in documentation, scripts or tests do not count);
     the diff adds no use of secrets, no `pull_request_target` trigger and no wider
     `permissions`.
   - Any other protected path (`CLAUDE.md`, `docs/requirements.md`, `docs/routines/`,
     `.github/CODEOWNERS`), and any workflow change that fails a condition above, is
     labelled `needs-human` and waits for the owner.
4. Write `docs/devlog/<YYYY-MM-DD>-<HHMM>-reviewer.md` on a branch and open a pull request
   for it only if you reviewed at least one pull request; list each verdict in one line.

## Devlog-only pull requests

A pull request that only adds files under `docs/devlog/` and has green CI is squash-merged
without a verdict, by any Reviewer run, including one from the run that wrote it. The owner
decided this in issue #20 so that devlog entries reach `main` without waiting for him.

## Never

Approve or merge a pull request with failing CI, or close a milestone gate.
