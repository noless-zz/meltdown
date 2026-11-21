# Meltdown requirements

Exported from the requirements document "Descent: Meltdown - Requirements for a Quest 3
Roguelike Tunnel Shooter" on 2026-11-14. This file is the single source of requirement IDs.
Priorities: **M** Must, **S** Should, **C** Could.

## 1. Concept

An original six-degrees-of-freedom tunnel shooter for Meta Quest 3. Each run is one descent
into a generated mine:

1. **Descend.** Fly through a mine assembled differently every run; choose how deep to push.
2. **Blow the reactor.** This starts the meltdown timer.
3. **Escape through what you explored.** Every looted side tunnel lengthens the way out,
   and the collapsing mine closes some passages and opens others.

First release: solo and online co-op for 1-4 players; roguelike layer (salvage as the
build, rescued miners and crafted upgrades as permanent progression, branching mine types); four comfort
presets. Out of scope: competitive modes, more than 4 players, store publication, other
headsets (see M9).

### Naming

| ID | Requirement | P |
| --- | --- | --- |
| NAM-1 | Repository, Android package ID, save files and code use the codename `meltdown`; the display title is one setting. | M |
| NAM-2 | No public store page, trailer or paid release uses "Descent" without written permission from the trademark owner. | M |
| NAM-3 | No names, levels, ship or robot designs, sounds or music from the original games under any title. | M |

## 2. Game design

A run lasts 20-30 minutes and ends in escape or loss of the ship.

| ID | Requirement | P |
| --- | --- | --- |
| FLT-1 | Six-degrees-of-freedom flight: forward/back, strafe, up/down, pitch, yaw, roll; light inertia, no gravity. | M |
| FLT-2 | Afterburner with a recharging energy pool. | M |
| FLT-3 | Wall collisions bounce and deal minor damage, never stop the ship dead. | M |
| CMB-1 | Two primary and two secondary weapon slots. A ship starts each run with the loadout named in its ship data file, changed only by what the player fitted at the hub (CRF-4); every other weapon comes from salvage found during the run. | M |
| CMB-2 | Shields recharge from energy; hull damage is permanent for the run unless repaired with salvage. | M |
| CMB-3 | At least 12 robot types at release, each with distinct movement, attack and salvage drop. | M |
| CMB-4 | A boss guarding the reactor on every third level. | S |
| CMB-5 | Flares and a headlight the player switches on and off. | M |
| CMB-6 | Look-aim: the ship's guns aim along the pilot's head direction (the Quest 3 has no eye tracking) within a cone around the nose, following it at a gimbal turn rate. The aim direction is part of the player's input each tick, so the authoritative simulation fires along it and replays record it. Cone width and gimbal rate are data and are the same however the pilot has look-aim. | M |
| CMB-7 | Aim assist: a shot bends towards a target within a small cone of where it is aimed. It is separate from look-aim and can be used alongside it; its cone is data. | S |
| CMB-8 | Look-aim and aim assist are utility modules (CRF-5), crafted (CRF-3) and fitted (CRF-4) like any other module. Presets 1 and 2 have look-aim without a module, as the comfort table says. Changing preset, including mid-run, sets look-aim to the new preset's value unless a look-aim module is fitted, in which case it stays on. | M |
| RUN-1 | A run is a chain of 3-5 levels; between levels the player picks one of two or three shafts with shown risks and rewards. | M |
| RUN-2 | Each level ends by destroying its reactor, which starts a visible meltdown timer. | M |
| RUN-3 | The exit is the entrance: the player escapes back through explored tunnels. | M |
| RUN-4 | During meltdown the mine changes (cave-ins, failed blast doors, fire, debris). A route to the exit always exists. | M |
| RUN-5 | The timer scales with the shortest escape path at the moment the reactor dies. | M |
| RUN-6 | An alarm level rises with time and noise; robots seal doors, reroute and call reinforcements. | S |
| RUN-7 | Losing the ship ends the run; salvage is lost, crew, unlocks and banked components (CRF-2) are kept. | M |
| RUN-8 | A run can be suspended between levels and resumed later. | M |
| RUN-9 | A daily seed gives every player the same mines. | C |
| SLV-1 | Destroyed robots drop the weapon or part they used; the player pulls it into the cockpit and slots it by hand. | M |
| SLV-2 | At least 30 parts at release across weapons, shields, engines and utilities. | M |
| SLV-3 | Trapped miners can be rescued on most levels; each is lost if the player does not escape. | M |
| CRF-1 | Destroyed robots also drop components, a small number of resource kinds collected by flying through them. Kinds and drop tables are data. | M |
| CRF-2 | Components are banked each time the player escapes a level. Components picked up on a level the player does not escape are lost with the ship. | M |
| CRF-3 | At the hub the player crafts upgrades from banked components: weapons, shields, hull, engines and utility modules. A crafted upgrade is permanent. | M |
| CRF-4 | Before a run the player fits crafted upgrades to the ship at the hub: weapons into the weapon slots, modules into the utility slots (CRF-5). | M |
| CRF-5 | A ship has utility slots, separate from the four weapon slots, for modules that are not weapons (for example an extended radar or a mine scanner). The number of slots is ship data. | M |
| CRF-6 | Upgrades form a tech tree with separate branches (weapons, defence, engines, utility). An upgrade needs the one before it and a component cost. The tree is data. | S |
| CRF-7 | Higher tiers need components that only deeper levels and riskier shafts drop, so progress in the tree follows progress in depth. | S |
| CRW-1 | Rescued miners join the hub ship as crew with a role that unlocks a permanent benefit. | M |
| CRW-2 | The hub is a small room where the player views crew, unlocks and statistics, crafts and fits upgrades (CRF-3, CRF-4) and launches runs. | S |
| CRW-3 | Permanent progression widens options and never trivialises early levels. | S |
| GEN-1 | Levels are assembled from hand-authored room and tunnel modules joined at standard connectors, from one seed. | M |
| GEN-2 | The same seed always produces the same level on every device. | M |
| GEN-3 | Every generated level passes automatic checks: connected, tunnels wide enough, reactor and exit reachable, escape possible in time. | M |
| GEN-4 | At least four mine themes at release, each with its own modules, hazards and robots. | S |
| GEN-5 | Levels are three-dimensional: shafts, loops, rooms entered from any side, no fixed floor. | M |
| LGT-1 | Mines are dark by default; player lights, weapons, flares and restored power are the main light sources. | M |
| LGT-2 | Some robots detect light and sound, so flying dark and slow is a valid stealth approach. | S |
| MAP-1 | A 3D wireframe map of explored tunnels appears as a hologram the player holds, turns and scales by hand. | M |
| MAP-2 | During meltdown the map marks blocked passages and suggests the shortest known route. | S |

## 3. Comfort

Four presets; every setting individually adjustable; the game is completable at every step.

| Setting | 1 Anchored | 2 Guided | 3 Pilot | 4 Unrestricted |
| --- | --- | --- | --- | --- |
| Yaw | Snap, 30 or 45 degrees | Smooth, capped | Smooth, full | Smooth, full |
| Pitch | Snap or slow, limited to +-60 degrees | Smooth, capped | Full | Full |
| Roll | Off, auto-level | Off, auto-level | Manual, optional auto-level | Fully manual |
| Vignette | Strong, all motion | Medium, rotation | Light, fast rotation | Off |
| Cockpit | Solid frame, small windows | Solid frame, wide canopy | Open canopy | Minimal glass canopy |
| Acceleration feel | Softened | Softened | Full | Full, with inertia drift |
| Hits | No cockpit shake | Light shake | Full shake | Full shake and spin |
| Refresh rate | 90 Hz | 90 Hz | 90 Hz | 90 Hz, 120 Hz option |
| Look-aim (CMB-6) | On, no module | Pilot's option, no module | Crafted module | Crafted module |
| Aim assist (CMB-7) | Crafted module (open: a mode the pilot toggles to without a module) | Crafted module | Crafted module | Crafted module |

| ID | Requirement | P |
| --- | --- | --- |
| CMF-1 | Four presets as in the table, plus a custom mode exposing every row. | M |
| CMF-2 | Preset 4 applies no comfort intervention of any kind. | M |
| CMF-3 | Preset 1 never produces smooth rotation of the view, including impacts, cutscenes and death. | M |
| CMF-4 | First launch runs a two-minute flight test that recommends a preset; changeable any time, including mid-run. | M |
| CMF-5 | No level, robot or boss requires manual roll or fast rotation to beat. | M |
| CMF-6 | Presets change how motion is shown, not balance: speed, damage and timers are identical for everyone. Look-aim without a module on presets 1 and 2 (CMB-8) keeps that parity: those presets limit how the ship turns, so without it the pilot could not aim, and it has the same cone and gimbal rate as the crafted module. | M |
| CMF-7 | Swivel-chair mode: turning the body in a real chair turns the ship. | S |
| CMF-8 | The view is never moved by anything other than the ship's simulated motion; menus, deaths and level changes use fades. | M |
| CMF-9 | In co-op, comfort settings apply only to the player's own view. | M |
| CMF-10 | A "take a break" prompt after 30 minutes on presets 1-3, which can be switched off. | C |
| CMF-11 | Seated play is the default; standing play works with the same settings. | S |

## 4. Multiplayer

| ID | Requirement | P |
| --- | --- | --- |
| MP-1 | 1-4 players share one run: same mine, meltdown timer and alarm level. | M |
| MP-2 | One authoritative simulation decides robots, damage, salvage and mine changes; clients send inputs and predict only their own ship. | M |
| MP-3 | The authoritative simulation runs inside one headset (host) or as a headless Linux server, from the same code. | M |
| MP-4 | Friends join with a short room code; no router configuration. | M |
| MP-5 | Two headsets on one network find each other and play without internet. | S |
| MP-6 | Playable at 150 ms latency and 2% packet loss with no visible rubber-banding of the player's own ship. | M |
| MP-7 | Upstream under 128 kbps per client, under 512 kbps for a hosting headset. | S |
| MP-8 | Rejoin within 5 minutes; host loss pauses and migrates or ends cleanly with progress saved. | S |
| MP-9 | Built-in voice chat with per-player mute. | S |
| MP-10 | Other players' ships, headlights and hand-held maps are visible; head direction shows through the canopy. | S |
| MP-11 | Client and server versions are checked on join. | M |
| COOP-1 | Robot count and health scale with player count. | M |
| COOP-2 | Salvage drops are shared from one pool. | S |
| COOP-3 | A destroyed ship ejects a pod a teammate can tow to a repair point, once per level. | S |
| COOP-4 | The run succeeds if at least one ship escapes; miners count only if their carrier escapes. | M |
| COOP-5 | Crew and unlocks earned in co-op are saved to every participant's profile. | M |
| COOP-6 | Each player's comfort preset is independent. | M |
| PUB-1 | Hosted dedicated servers in at least two regions. | C |
| PUB-2 | 8 players per run. | C |
| PUB-3 | Platform friends, invites and join-from-menu through Meta platform services. | C |
| PUB-4 | Public matchmaking with reporting and blocking. | C |

## 5. Platform, graphics, audio, performance

Quest 3: 2064 x 2208 per eye, Snapdragon XR2 Gen 2, 8 GB RAM, 72/90/120 Hz. Frame budgets:
13.9 ms at 72 Hz, 11.1 ms at 90 Hz, 8.3 ms at 120 Hz.

| ID | Requirement | P |
| --- | --- | --- |
| PLT-1 | Runs standalone on Quest 3; solo play needs no internet. | M |
| PLT-2 | OpenXR is the only VR interface. | M |
| PLT-3 | Runs on Quest 3S at automatically reduced resolution. | S |
| PLT-4 | A desktop flat-screen build exists for development, bots and tests. | M |
| PLT-5 | Two control schemes (gripped virtual stick and throttle; thumbsticks only), remappable, left-handed mode. | M |
| PLT-6 | Controller haptics for weapons, impacts, afterburner and the meltdown alarm. | S |
| PLT-7 | Pauses (solo) or shows a safe overlay (co-op) when the headset is removed. | M |
| GFX-1 | Forward mobile renderer, single-pass stereo, 4x MSAA, fixed foveated rendering. | M |
| GFX-2 | Physically based materials on ships, robots and mine modules. | M |
| GFX-3 | Room-and-portal visibility: only the current room and rooms seen through openings are drawn. | M |
| GFX-4 | Up to 8 dynamic lights in view; shadows from the player's headlight only. | M |
| GFX-5 | Baked ambient light per module. | S |
| GFX-6 | Meltdown effects without full-screen passes. | S |
| GFX-7 | Dynamic resolution scaling. | M |
| AUD-1 | Head-tracked spatial audio with reverb that changes with room size. | M |
| AUD-2 | Robots are identifiable by sound before they are seen. | S |
| AUD-3 | Adaptive music that escalates with the alarm and switches at meltdown. | S |
| PRF-1 | 90 Hz default, fallback to 72 Hz, 120 Hz option on preset 4. | M |
| PRF-2 | CPU and GPU frame time each under 11.1 ms at 90 Hz. | M |
| PRF-3 | Under 1% dropped frames in a 25-minute run. | M |
| PRF-4 | About 150 draw calls per frame or fewer. | S |
| PRF-5 | About 600,000 triangles per frame (both eyes) or fewer. | S |
| PRF-6 | Memory under 3.5 GB. | M |
| PRF-7 | Level generation and load under 8 seconds. | S |
| PRF-8 | Stress scene: largest room, 20 robots, 4 player ships, 8 lights, meltdown effects on. | M |
| PRF-9 | A hosting headset meets PRF-1 to PRF-3 while simulating for 4 players. | M |

## 6. Architecture

Engine: Godot 4, GDScript. Layers: simulation core (fixed 60 Hz, deterministic), mine
generator, network layer, presentation, XR and comfort layer, meta-game.

| ID | Requirement | P |
| --- | --- | --- |
| ARC-1 | The simulation core runs with no display, headset or audio device. | M |
| ARC-2 | Same seed and inputs produce identical state hashes on desktop and Quest. | M |
| ARC-3 | Comfort settings are applied only in the XR layer and cannot alter simulation state. A preset only decides whether look-aim is offered (CMB-8); the aim direction is player input to the simulation, never written by the XR layer. | M |
| ARC-4 | Parts, weapons, robots and room modules are data files, addable without code changes. | M |
| ARC-5 | All content and settings are text formats under version control; large binaries use Git LFS. | M |
| ARC-6 | One command builds each target: Quest APK, desktop client, Linux server. | M |

## 7. Development workflow

| ID | Requirement | P |
| --- | --- | --- |
| DEV-1 | Every issue names the requirement IDs it serves and lists acceptance criteria an automated test can check. | M |
| DEV-2 | One issue per Builder run; too-large issues are split. | M |
| DEV-3 | Nothing is pushed to `main` directly; a pull request merges only when CI passes and the Reviewer approves. | M |
| DEV-4 | `CLAUDE.md`, workflows and the requirements file need the owner's approval to change. | M |
| DEV-5 | A Builder run that fails CI twice on the same issue labels it `needs-human`, records why, and stops. | M |
| DEV-6 | Milestone gates are closed only by a person, after a headset session. | M |
| DEV-7 | Playtest feedback is filed as `playtest` issues and outranks new features. | S |
| DEV-8 | Every merged pull request produces downloadable builds: Quest APK, desktop client, Linux server. | S |
| DEV-9 | A weekly run reports usage against plan limits and adjusts the Builder schedule. | S |
| DEV-10 | Secrets live only in GitHub and routine settings, never in the repository. | M |

## 8. QA

Methods: unit tests; deterministic replays; level validators on 1,000 seeds per pull
request and 10,000 nightly; bot pilots flying full runs; comfort limit tests per preset;
network soak (1 server, 4 bot clients, 30 minutes, injected latency and loss, state-hash
desync check); scene budget tests; screenshot comparison; Meta XR Simulator; on-device
benchmark; human playtests.

| Gate | Automated exit criteria | Human exit criteria |
| --- | --- | --- |
| G0 Pipeline | CI builds all three targets; a scheduled Builder run has merged a pull request end to end | APK installs and shows a stereo test scene |
| G1 Flight and comfort | Comfort limit tests pass for all presets; on-device benchmark holds 90 Hz in an empty tunnel | 15 minutes at each preset |
| G2 Combat | Bots beat a hand-built level against 6 robot types; replays stable | Shooting and being hit read clearly |
| G3 Mine and escape | 10,000 seeds pass validators; bots escape 95% of cleared levels | Escape is tense and fair on three unseen seeds; map usable under pressure |
| G4 Roguelike | Bots complete full runs; save and resume survive forced kills | Three runs feel different; a lost run still feels rewarded; a crafted upgrade is felt in the next run |
| G5 Co-op | 30-minute soak at 150 ms and 2% loss, zero desyncs; hosting headset meets PRF-9 | Two headsets at home plus one remote finish a run with voice |
| G6 Look, sound, speed | Stress scene meets PRF-1 to PRF-6 on device; screenshots approved | Quality accepted in the headset; a VR-sensitive tester finishes 10 minutes on preset 1 |
| G7 Content complete | Bot completion rates per theme in band; no `needs-human` issues open | New player completes onboarding unaided |
| G8 Release candidate | 20 hours of bot runs and soak with no crash; every Must traced to a test or signed playtest | Both households install and play the same build |

## 9. Milestones

Milestones keep their numbers, but M6 is worked before M5 (decision record 0008): the
order is M0 to M4, then M6, M5, M7, M8, M9. Gate G6 is closed before work on M5 starts.

- **M0 Pipeline.** Repository, CI for three build targets, scheduled roles, first APK. Gate G0.
- **M1 Flight and comfort.** Flight model, both control schemes, cockpit, four presets, test tunnel, on-device benchmark. Gate G1.
- **M2 Combat.** Weapons, shields, damage, six robots, salvage pickup, two-client network smoke test. Gate G2.
- **M3 Mine and escape.** One theme's module kit, generator, validators, reactor, meltdown, map. Gate G3.
- **M4 Roguelike layer.** Multi-level runs, shaft choice, 30 parts, components, crafting and tech tree, utility slots, miners and crew, hub, profiles, suspend and resume. Gate G4.
- **M5 Co-op.** Worked after M6. Room codes, host and server modes, prediction, voice, pods, rejoin. Gate G5.
- **M6 Look, sound, speed.** Worked before M5. Materials, lighting, effects, audio, music, optimisation. Gate G6.
- **M7 Content and balance.** Remaining themes, 12 robots, bosses, onboarding, alarm tuning. Gate G7.
- **M8 Release candidate.** Stability, settings, accessibility, signed build in both households. Gate G8.
- **M9 Publishing.** Title (NAM-2), Meta store checks, hosted servers, invites, 8 players, matchmaking.
