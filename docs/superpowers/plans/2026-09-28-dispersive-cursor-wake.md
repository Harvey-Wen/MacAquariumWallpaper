# Dispersive Cursor Wake Implementation Plan

> Execute inline in the current feature branch; the user approved the photographed reference and requested continued implementation.

**Goal:** Connected curved crests that collectively widen behind the pointer, remain on the historical path when turning, and propagate after stopping.

**Architecture:** Integrate radial dispersive impulses continuously along short timed pointer segments. Gravity-wave phase and group speeds differ; signed superposition forms curved interference crests without drawing triangular borders. Use the same field for Metal water normals and floating-leaf forces.

**Tech Stack:** Swift, Metal, existing executable simulation/render tests.

## Constraints and assumptions
- A bounded real-time approximation of small surface disturbances; not a full fluid solver.
- Preserve click/rain behavior, fish avoidance, weather fixes and the removed menu help rows.
- Preserve the 24 interaction / 72 rain disturbance budget and the 30 FPS target.
- A long pause or a pointer gap must not fabricate a bridge. Released segments remain fixed when the pointer turns.

## 1. Field and sampling
- [x] Numerically compare old nondispersive packets with phase/group-separated packets and gravity-wave stationary-phase impulses. Inspect curved, connected crests before selecting the smallest viable model.
- [x] Add segment travel/duration to `Ripple` and matching `EffectUniforms`. Integrate each segment with bounded midpoint samples, with source position `end - travel*f` and age `age + duration*f`.
- [x] Update `trackPointer`, resizing and `motionWaveForce`; record duration only for actual movement. No repeated emission during stillness.
- [x] In `Tests/SimulationTests.swift`, verify historical path, rotation symmetry, propagation, finite values, expiry, independent rain budget and equivalent fields when a segment is split into equal halves.

## 2. Rendering and visual verification
- [x] Replace only the motion branch of `waveFragment`, and conservatively bound each segment's quad in `OceanRenderer`.
- [x] Replace circular-stamp-specific renderer assertions with connected-wave checks, signed relief, widening in four directions, and propagation after stopping. Retain fish refraction, backing-size mapping, expiry and weather assertions.
- [x] Produce enlarged actual Metal previews for straight travel, turns and stopping. Inspect against the approved duck/boat reference. Run `bash scripts/test-simulation.sh` and `zsh scripts/test-renderer.sh --preview`; commit the verified implementation.

## 3. Launch
- [x] Build and verify app signature, gracefully terminate the running exact app bundle, launch the replacement and read fresh diagnostics.
- [x] Update planning/evidence files and commit validation. Show the result to the user.
