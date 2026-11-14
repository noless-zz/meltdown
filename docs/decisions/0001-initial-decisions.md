# 0001 Initial decisions

Date: 2026-11-14. Decided by the owner (noless-zz) through the setup form.

| Topic | Decision | Consequence |
| --- | --- | --- |
| Engine | Godot 4 (4.7 line), GDScript | Text scenes and scripts; headless CI, bots and dedicated server from one binary |
| Scheduled coding | Claude scheduled runs on the owner's Max plan | The Builder, Reviewer and Planner roles in `docs/routines/` |
| Fallbacks | An Anthropic API key on the same account; GitHub Pro with Copilot | The API key can drive `anthropics/claude-code-action` in GitHub Actions if scheduled runs are unavailable. Copilot's coding agent may be asked for a second-opinion review on a different model; it is optional and never replaces the Reviewer role |
| Builder pace | Every 3 hours | Revisit after gate G0 using the weekly usage report (DEV-9) |
| Home PC | Windows PC that can stay on with a Quest 3 attached | Will become a self-hosted runner for Meta XR Simulator sessions and the on-device benchmark (issue in M0) |
| Repository | `noless-zz/meltdown`, public | Free CI minutes. No open-source licence chosen yet: all rights reserved until the owner decides |
| Remote player's headset | Quest 3 | Quest 3 is the single performance baseline; Quest 3S support stays a Should (PLT-3) |
| Co-op hosting | Decide at M5 | The core is written to run as headset host or headless server either way (MP-3) |
| Art and audio budget | Free assets, plus AI-generated or AI-modified assets | Every asset's source, licence and generator is recorded in `docs/licences.md` |
| Publishing | Yes, aim to publish | M9 is in scope after M8. The title must be resolved first (NAM-2); the fallback title is "Meltdown" |
| Unit tests | A small built-in runner (`game/tests/run_tests.gd`), no addon | Zero dependencies for M0. Adopting a fuller framework later needs a new decision record |

## Still open

- Comfort testers for gate G1, including one person sensitive to VR motion.
- Licence for the public repository.
- Whether to ask Interplay for a licence to the title or ship as "Meltdown".
