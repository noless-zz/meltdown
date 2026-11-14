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
   4. Post one review: approve, or request changes with a numbered list of specific,
      checkable items. Do not rewrite the code yourself.
3. For an approved pull request that changes only unprotected paths, enable squash merge
   (auto-merge if available). Pull requests touching protected paths wait for the owner.
4. Write `docs/devlog/<YYYY-MM-DD>-<HHMM>-reviewer.md` on a branch and open a pull request
   for it only if you reviewed at least one pull request; list each verdict in one line.

## Never

Approve a pull request with failing CI, review your own devlog pull request, or close a
milestone gate.
