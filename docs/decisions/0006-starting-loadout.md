# 0006 A ship starts with a loadout from its data file

Date: 2026-11-19. Decided by the owner (recorded on issue #1 on 2026-11-17, requested as a
requirements change in issue #592).

## Decision

CMB-1 used to say weapon slots are "filled only by salvage found during the run". The
ship now starts each run with the loadout named in its ship data file (today a pulse
cannon in primary slot 1, `game/data/ships/default_ship.json`, from #223). Every other
weapon still comes from salvage.

## Why

An unarmed start in a mine of armed robots is not playable, and M2 and M3 were built and
tested with the starting cannon. The owner accepted it "for now".

## What this does not decide

- Which weapon the release game starts with, or how strong it is. That is tuning, in data.
- Starting classes with their own loadout and perk, including a close-combat or nearly
  unarmed "brawler" (the owner's idea, issue #471). CMB-1 as reworded already allows a
  different loadout per ship data file, so classes need no further change to it; they are
  planned with the roguelike layer (M4).

## Consequences

- The loadout stays data, never a code branch (ARC-4), and is part of the replay.
- Salvage (SLV-1) is how a run's build grows; the starting loadout is only the floor.
