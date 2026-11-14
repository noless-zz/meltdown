# Meltdown

Working title: **Descent: Meltdown**. A roguelike six-degrees-of-freedom tunnel shooter for
Meta Quest 3, in the spirit of the classic 90s tunnel shooters.

Fly a small ship down into a mine that is assembled differently every run, destroy the
reactor, then escape back through the tunnels you explored before the meltdown. The further
you explored for salvage, the longer the way out. Solo or co-op for up to 4 players.

## Status

Milestone M0 (pipeline). Nothing playable yet.

## How this project is built

The code is written mostly by scheduled Claude runs, one GitHub issue at a time, with
automated checks on every pull request and a human playtest gate at each milestone.

| Read this | For |
| --- | --- |
| [`docs/requirements.md`](docs/requirements.md) | What the game must do |
| [`CLAUDE.md`](CLAUDE.md) | Rules every run follows |
| [`docs/routines/`](docs/routines) | The Builder, Reviewer and Planner procedures |
| [`docs/decisions/`](docs/decisions) | Decisions made so far |
| [`docs/devlog/`](docs/devlog) | What each run did |

## Running the tests

Install Godot 4.7, then:

```sh
godot --headless --path game --import
godot --headless --path game -s res://tests/run_tests.gd
```

## Name and licence

"Descent" is a trademark of Interplay Entertainment Corp. This project is not affiliated
with or endorsed by Interplay and uses no names, levels, art, sound or code from the
original games. The title is a working title; a public release will use a licensed or
different name.

No open-source licence has been chosen yet. Until one is added, all rights are reserved by
the author.
