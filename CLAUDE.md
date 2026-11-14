# Meltdown: rules for every run

Meltdown (display title "Descent: Meltdown", codename `meltdown`) is a roguelike
six-degrees-of-freedom tunnel shooter for Meta Quest 3, built in Godot 4 with GDScript.
Read `docs/requirements.md` before any work. Requirement IDs (FLT-1, CMF-3, ...) are the
contract; every change must trace to at least one.

## Each run starts cold

A scheduled run has no memory of earlier runs. Everything you need is in this repository:

- `docs/requirements.md`: what to build. Protected; do not edit.
- `docs/decisions/`: choices already made. Do not undo one without a new decision record.
- `docs/devlog/`: one entry per run. Read the latest three before starting.
- `docs/routines/`: the exact procedure for the Builder, Reviewer and Planner roles.
- GitHub issues: the backlog. Labels are explained in `docs/routines/planner.md`.

## Architecture (requirements section 6)

Code lives under `game/`, the Godot project root (`res://`).

| Folder | Layer | May depend on |
| --- | --- | --- |
| `game/core/` | Simulation: ships, robots, weapons, damage, alarm, meltdown | nothing else |
| `game/gen/` | Mine generator and validators | core |
| `game/net/` | Host, dedicated server, replication | core, gen |
| `game/view/` | Rendering, lighting, audio, effects | core, gen (read only) |
| `game/xr/` | Headset rig, controllers, cockpit, comfort presets | view, core (read only) |
| `game/meta/` | Profiles, crew, unlocks, hub, saves | core |
| `game/tests/` | Unit tests | anything |

Hard rules:

1. `core/` and `gen/` never touch nodes, rendering, input devices, audio, time of day or
   unseeded randomness. They extend `RefCounted`, advance on a fixed 60 Hz tick, and must
   give identical results for identical seed and inputs (ARC-1, ARC-2).
2. Comfort settings live only in `xr/` and never change simulation state (ARC-3, CMF-6).
3. The simulation is server-authoritative from the start: clients produce inputs, the core
   produces state. Never let view or xr code write simulation state (MP-2).
4. Parts, weapons, robots and room modules are data files, not code branches (ARC-4).
5. No names, levels, designs, sounds or music from the original Descent games (NAM-3).
   The codename `meltdown` is used for packages, save files and identifiers (NAM-1).

## Coding standards

- GDScript with static types on every variable, parameter and return value.
- Tabs for indentation, `snake_case` files and functions, `PascalCase` classes.
- One class per file. Keep files under about 300 lines; split before they grow past it.
- No editor-only binary resources where a text format exists (`.tscn`, `.tres`, `.gd`).
- Comments explain why, not what.

## Testing

- Every change to `core/`, `gen/`, `net/` or `meta/` ships with unit tests in `game/tests/`.
- A test file is `test_*.gd`, extends `RefCounted`, and each `test_*` method returns `""`
  on success or a failure message.
- Run locally exactly as CI does:

  ```sh
  godot --headless --path game --import
  godot --headless --path game -s res://tests/run_tests.gd
  ```

- A pull request is not ready until CI is green.

## Never do

- Push to `main`. All work goes through a pull request from a branch named
  `issue-<number>-<short-slug>`.
- Edit `CLAUDE.md`, `docs/requirements.md`, `docs/routines/` or `.github/` unless the
  issue you are working on says so explicitly. Those paths need the owner's approval.
- Commit secrets, signing keys or credentials.
- Add a dependency, addon or asset without recording its licence in `docs/licences.md`.
  Free and AI-generated assets only; note the source and generator for each.
- Mark a milestone gate as passed. Gates are closed by the owner after a headset session.
