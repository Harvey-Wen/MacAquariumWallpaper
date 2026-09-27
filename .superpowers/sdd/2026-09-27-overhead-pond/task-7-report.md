# Task 7 — Passive pointer-water response

## Implemented

- `DesktopController.tick()` samples the existing filtered `DesktopInput.hover()` after the simulation step. No new monitor, permissions, or input geometry path was added.
- `OceanSimulation.trackPointer(_:)` creates `.motion` ripples after at least 11 screen points of travel and 0.12 seconds of simulation time. Initial entry and re-entry set a quiet baseline. Invalid positions, explicit lifecycle reset, and jumps above 140 points break the trail. Each accepted sample creates one local ripple without interpolating across skipped or blocked regions.
- Motion ripple strength is 0.34 versus click strengths 1 and 0.48. Nearby fish receive at most 0.18 panic and a 12-point local impulse, with `max` preserving stronger click panic. Existing ripple aging, 24-ripple cap, fish speed cap, and leaf wave path apply unchanged. Diagnostics expose active `motionRipples`.
- The menu hint describes sliding and clicking. No renderer or shader code changed.

## Verification

All commands ran from `/Users/harvey/.codex/worktrees/overhead-pond/MacAquariumWallpaper` on 2026-09-28.

| Command | Result |
| --- | --- |
| `./scripts/test-simulation.sh` | `SimulationTests: 16 passed`. Four added regressions cover no-button motion, stillness, distance/time throttling, nil/foliage/re-entry/large jumps, mild local fish avoidance, click precedence, dense input bounds, and floating-leaf response. |
| `bash scripts/test-input.sh` | `PASS: 25 input geometry and gesture checks`. The script is not executable directly in this checkout, so it was invoked with `bash`. |
| `bash scripts/test-desktop.sh` | `PASS: 64 native desktop and lifecycle checks` when run alone. The added check verifies pause clears the pointer trail. The suite restores the original wallpaper and options at completion. |
| `bash scripts/build.sh` | Application built and signed successfully after final source changes. |
| `git diff --check` | Passed. |

An initial native run failed at the pre-existing “disable restores original image” check while an older app from the primary checkout was running and using the same `DesktopBackdrop` journal. The parent task stopped that process; the isolated rerun passed all 64 checks. No code change was made in response to that environmental collision.

For the focused visual check, a temporary `.build/motion-preview.swift` drove a 0.6-second pointer path through `OceanSimulation`, then wrote the actual renderer output to `.build/render-validation/pond-motion.png` at 1600×1000. The frame held four `.motion` ripples; comparing its rendered pixels with the same frame minus ripples found 9,755 changed pixels. The PNG was visually inspected. The temporary preview source, executable, and PNG remain local under ignored `.build/` and are not part of the commit.

## Limits

The renderer is unchanged; the prior full renderer/GPU suite from Task 6 remains the relevant coverage for shader behavior. This task performed one focused actual-motion render, not a full GIF regeneration or a new GPU benchmark. Automated native tests validate lifecycle resets and wallpaper restoration; physical mouse use across every system UI, Space, display setup, and sleep state remains an end-user observation boundary.
