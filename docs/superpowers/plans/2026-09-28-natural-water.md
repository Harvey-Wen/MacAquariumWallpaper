# Natural rainfall and pointer wakes

> **For agentic workers:** Use superpowers:subagent-driven-development for the bounded implementation and review below.

**Goal:** Correct the user's three visual defects: parallel line rain, outlined-circle impacts, and circle-stamped mouse trails. Deliver and launch the changed application, not just previews.

**Architecture:** Keep the environment, fish, canopy mask, input filtering and desktop lifecycle. Render the underwater scene into a cached color texture; accumulate signed wave gradients into a smaller floating-point texture; composite the scene through those gradients for refraction and directional crest/trough lighting. Render leaves over the resulting water and varied short airborne droplets last. This is an analytic wave approximation, not a full fluid solver.

**Constraints:** Work in `/Users/harvey/.codex/worktrees/overhead-pond/MacAquariumWallpaper`, source base eb11d2d. Running application is in the primary checkout; do not overwrite it or run wallpaper-changing tests while it is active. Use existing Swift/Metal and local assets, no new dependencies or permissions. Keep 30 FPS, deterministic frame rendering, .empty transparency, weather controls, bounded disturbances, interactions and canopy exclusion. Current accepted environment is unchanged. Baseline was verified last turn: simulation16/input25/desktop64/render/build/signature, so do not repeat unchanged checks without cause.

**User steering after first preview:** Rain remained too faint; use the sustained, dense rain atmosphere of The Garden of Words. Increase the visible density across depth layers by approximately 3–4 times and impact rate from 7.5 to about 40 per second, judging at actual full-screen size. Replace the old shared 24-disturbance cap with separate finite rain/interaction budgets (72 rain + 24 interactions, at most96), so rain cannot evict clicks or wakes. Verify the new worst-case budget at native backing resolution. Rain remains varied short droplets and signed fine waves, not uniform long lines or white ring outlines. Also align floating-leaf motion forces with the visible travel-axis wake and its finite taper; add an ahead-versus-behind regression.

### Task 1: Refracting water and varied rainfall

**Files:** `Resources/Ocean.metal`, `Sources/OceanRenderer.swift`, `Sources/OceanTypes.swift`, `Sources/OceanSimulation.swift`, `Tests/RenderTests.swift`, `Tests/SimulationTests.swift`. A small renderer-specific helper file is allowed only if it keeps the render-pass implementation readable; no unrelated changes.

**Interfaces/data:** Preserve public `OceanRenderer` initializer, `renderRGBA`, `writePNG`, `lastGPUSeconds` and existing frame semantics. Add a defaulted travel vector to Ripple so existing call sites compile:

```swift
struct Ripple {
    var position: SIMD2<Float>
    var age: Float
    var strength: Float
    var source: DisturbanceKind = .click
    var travel: SIMD2<Float> = .zero
}
```

`trackPointer` should record the accepted local motion segment/direction, bounded by existing jump/filter rules. Resize scales travel with the same existing position/length scale. First entry, stationary pointer, invalid regions and large jumps remain quiet. Do not interpolate long paths across windows; the trail already samples only permitted points.

- [x] Add focused regressions for nonzero directional motion data, resize consistency and unchanged reset/click precedence. Add render probes for signed bright/dark wave relief and refraction (not just positive-colored circles), different horizontal/vertical motion wake orientation, canopy exclusion, deterministic repeated frame and expiry.
- [x] Replace painted ring draw calls with a signed wave gradient accumulation pass and a water composite. Suggested Metal targets: scene RGBA8 + existing MSAA resolve, half-backing-resolution RGBA16Float additive gradient/foam map, final composite into existing output. Cache/reuse targets until output size changes, never allocate per frame. Accumulate normals for all disturbances before composing so overlapping waves interact. Texture sampling must preserve the bottom-left simulation/top-left texture mapping; verify at multiple output sizes including resize back to a previous size.
- [x] Wave profiles: rain is a small impact depression, a very brief irregular splash/droplet glint, then several damped fine wavelets; varying radius/phase/amplitude per location. Click remains a larger localized impulse. Use signed oscillatory height derivatives, e.g. an expanding `cos(k*(r-speed*age))*exp(-square((r-speed*age)/width))` packet with finite lifetime and gentle angular/spatial breakup. Rain speed can start around45 points/s rather than old95; keep leaf forces consistent with the wave profile if changed. Central splash ends within about0.2 seconds; no permanent white centers or thick uniform outlines.
- [x] Motion must form a directional elongated disturbed strip/wake behind travel with lateral wave propagation and tapered head/tail, not an elliptical ring or a chain of circular stamps. Carry direction/length from simulation, overlap signed wake gradients, and damp after movement ends. Keep footprint local and bounded; don't draw on foliage.
- [x] Composite underwater color (including fish) through the resulting normals. Use restrained displacement and light from a direction to produce alternating lit/dark slopes and reflection changes; never blanket tint the scene or add uniformly white circles. Leaves stay above the refracted underwater scene. Canopy pixels remain identical when only water disturbances change; reduce displacement near mask boundaries.
- [x] Replace repeating parallel streak sheet with a few sparse depth layers of independently phased droplets. Most distant drops are tiny soft points/very short glints; occasional nearer drops are slightly longer/blurrier, with varied length, speed, opacity and direction plus mild coherent wind. No regular rows or equal-angle uniform long lines. A periodic analytic particle pattern is acceptable: phases must wrap continuously using Double time before conversion, with fades at reset. Preserve sunny absence, pause identity and day-seven continuity. Update old two-second-only test if period changes, testing the new actual period.
- [x] Run `bash scripts/test-simulation.sh` and `zsh scripts/test-renderer.sh --preview` after implementation. Retain layer/mask/long-time/aspect tests; add relevant checks rather than weakening them. Benchmark native geometry correctly: frame.size1512×982 points, output3024×1964 backing pixels. Record completed GPU duration; p95 must remain below33.3ms. Generate natural-rain and cursor-wake stills and real animated previews, at least4 seconds and enough resolution to see water relief. Inspect several actual frames; fix visible repeated lines, obvious ring outlines or wake stamping before returning.
- [x] Build and strict-signature verify in the isolated checkout. Do NOT run DesktopTests, launch an app, change system wallpaper, or mutate primary checkout. Parent will handle the single-instance swap after review. Commit only owned source/tests; write report in ignored task workspace (do not git-add it). Report exact commands/results, output paths, timings, concerns and the limitations of analytic rather than full fluid simulation.

## Parent delivery

- [ ] Inspect actual animation frames and visual profiles against the three criticisms, independently review the implementation and fix findings.
- [ ] Sync to original clean checkout, replace the sole running application after build/signature success, confirm fresh process diagnostics and system backdrop. Never run wallpaper-mutating tests alongside it.
- [ ] Update verification, commit each verified module, show actual preview and concise delivery. Keep native-managed worktree.
