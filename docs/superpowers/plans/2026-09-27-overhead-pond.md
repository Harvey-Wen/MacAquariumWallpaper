# 俯瞰池塘 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver the approved realistic overhead pond as an interactive macOS desktop wallpaper.

**Architecture:** A fish-free environment texture derived from the approved concept provides the natural bank and pond bed. A single shared shoreline geometry governs simulation, mouse hits and a renderer water mask. Native Metal draws independent koi, animated water/refraction, rainfall ripples and leaves; existing AppKit desktop window and input filtering remain.

**Tech Stack:** Swift 5, AppKit, Metal, macOS 14+, local resources; existing SDK selection in scripts.

## Global Constraints

- Natural realistic style, fixed overhead camera, irregular pond, around 30 koi.
- Click water creates ripples, briefly scatters nearby fish, then fish recover.
- Rain lightly affects nearby fish; falling leaves land, ripple, float, attract a few nearby fish and respond to waves.
- Main display, full desktop background below icons and applications, no focus/input interception, no network at runtime, no audio.
- Shared shoreline prevents fish crossing land and clips water effects to water.
- Bounded effects and wrapped animation phases; pause/sleep/lock/reduced-motion retain existing lifecycle semantics.
- Target 30 FPS; report measured performance and any unverified lifecycle cases honestly.
- Every verified module is committed separately. Implementation working directory: `/Users/harvey/.codex/worktrees/overhead-pond/MacAquariumWallpaper`.

## Shared interfaces

Scene source coordinates use 1600 × 1000, origin top-left. Simulation positions remain screen points, origin bottom-left. Use centered aspect-fill mapping consistently, with outer scenery potentially cropped at other aspect ratios.

```swift
enum FishSpecies: Int, CaseIterable { case koi }
enum PondWeather: String { case sunny, rainy }
enum DisturbanceKind: Int { case click, rain, leaf }
enum LeafStage: Int { case falling, floating, grounded }
// Preserve FishState's existing fields; id controls koi color/pattern variation.
struct Ripple { var position: SIMD2<Float>; var age: Float; var strength: Float; var source: DisturbanceKind = .click }
struct PondLeaf {
    var id: Int; var position: SIMD2<Float>; var velocity: SIMD2<Float>
    var age: Float; var rotation: Float; var length: Float
    var stage: LeafStage; var fallDuration: Float
    var opacity: Float // simulation updates, 0...1
}
// OceanFrame retains size/time/fish/ripples/waterStrength; replaces currents with
// leaves: [PondLeaf] = [], weatherAmount: Float = 0. Empty means no scene.
struct PondGeometry {
    static let imageSize = SIMD2<Float>(1600, 1000)
    static func uv(for point: SIMD2<Float>, size: SIMD2<Float>) -> SIMD2<Float>
    static func point(for uv: SIMD2<Float>, size: SIMD2<Float>) -> SIMD2<Float>
    static func signedDistance(at point: SIMD2<Float>, size: SIMD2<Float>) -> Float // positive in water
    static func inwardNormal(at point: SIMD2<Float>, size: SIMD2<Float>) -> SIMD2<Float>
    static func contains(_ point: SIMD2<Float>, size: SIMD2<Float>, margin: Float = 0) -> Bool
}
// OceanSimulation: init(size:seed:), update(deltaTime:), click(at:), resize(to:),
// frame(waterStrength:), private(set) fish/ripples/leaves/time/size;
// var weather: PondWeather = .sunny. Remove old hover/drag-only ocean behavior.
```

### Task 1: Pond geometry and living simulation

**Files:** Create `Sources/PondGeometry.swift`; modify `Sources/OceanTypes.swift`, `Sources/OceanSimulation.swift`, `Tests/SimulationTests.swift`, `scripts/test-simulation.sh`.

**Interfaces:** Consume shared definitions above, produce deterministic scene snapshots for renderer and controller. Shoreline traced to `docs/concepts/pond-approved.png`; parent will adjust its coordinates if environment edit changes edges. Use a polygon in normalized image space and signed point-to-segment distance, plus soft steering and final containment accounting for half fish length. Initial points must have adequate clearance.

- [ ] Write meaningful tests for 30 deterministic koi, water/land click distinction, local click falloff and bounded repeated clicks, rain start/stop and local mild response, actual leaf landing/floating/expiry/wave motion, boundary containment under repeated disturbances, resize/aspect mapping and 30/5 FPS equivalence.
```swift
let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
sim.click(at: SIMD2(5, 5))
try expect(sim.ripples.isEmpty, "land click produces no water ripple")
let hit = sim.fish[0].position
sim.click(at: hit)
try expect(sim.fish[0].panic > 0, "near fish reacts")
sim.weather = .rainy
for _ in 0..<300 { sim.update(deltaTime: 1 / 30) }
try expect(sim.ripples.contains { $0.source == .rain }, "rain produces water impacts")
```
- [ ] Run `bash scripts/test-simulation.sh`, record the initial failing requirement, implement and rerun.
- [ ] Local rain events have weaker/smaller fish influence than clicks. Floating leaf approach is weak and limited to nearby fish; leaf water motion derives from nearby waves. Spawn leaves near visible overhanging trees and cap/expire all effects. Use continuous phase integration and seeded randomness.
- [ ] Commit only owned files and write task report with test evidence. Other render/controller files may be temporarily incompatible until subsequent tasks.

### Task 2: Realistic Metal scene

**Files:** Modify `Sources/FishMesh.swift`, `Sources/OceanRenderer.swift`, `Resources/Ocean.metal`, `Tests/RenderTests.swift`, `scripts/test-renderer.sh`, `scripts/build.sh`; consume new `Resources/PondEnvironment.png` supplied by parent.

**Interfaces:** Consume Task 1 types and shared geometry. Preserve `OceanRenderer.init(view:shaderURL:)`, `renderRGBA`, `writePNG`. Expose the completed command buffer's GPU duration for benchmark evidence. Load environment relative to shaderURL. Generate a water distance texture from shared geometry, sampled by every water-related layer. Resource errors must be readable and fail initialization rather than silently dropping the environment.

- [ ] Replace ocean-specific fish mesh with tapered top-down koi body, paired fins, forked tail, eyes, appropriate dorsal detail. Keep independent tail/fin animation and rotate in the screen plane, without side-view yaw.
- [ ] Draw opaque environment, submerged fish/shadows, restrained animated surface/refraction, local rain/click/leaf ripples, then leaves. Water mask bounds all aquatic effects. No baked static fish, rain rings or floating leaves in the environment.
```swift
let sunny = simulation.frame(waterStrength: 0.45)
let pixels = try renderer.renderRGBA(frame: sunny, width: 1600, height: 1000)
precondition(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
```
- [ ] Build render tests covering full opacity, `.empty`, no-fish vs fish image difference, land unchanged by ripples, underwater vs overwater layers, time continuity including day 7, dry/rain difference and multiple output aspect ratios. Export inspectable sunny/rain/click PNGs and an optional short video/animation preview from genuine frames. Run `zsh scripts/test-renderer.sh`.
- [ ] Measure GPU at actual display resolution, optimize if needed to meet 30 FPS. Inspect exported images against approved visual reference and revise obvious appearance faults before committing. Commit owned files and report paths/results.

### Task 3: Desktop controls and delivery

**Files:** Modify `Sources/App.swift`, `Sources/DesktopController.swift`, `Resources/Info.plist`, `Tests/DesktopTests.swift`, `scripts/test-desktop.sh`, `README.md`, `docs/verification.md`.

**Interfaces:** Use simulation.weather for sunny/rainy switching, remove controller hover/drag simulation hooks; keep low-level desktop input filters. Rain amount transitions via simulation updates. Status text uses live fish count. Keep app executable/bundle identity to avoid competing application identities.

- [ ] Replace user-facing ocean text with pond text, provide weather selection, show/pause/interaction/quit controls, no obsolete water-intensity submenu. Route only valid desktop clicks into simulation.
```swift
controller.weather = .rainy
check(controller.simulation.weather == .rainy, "weather control reaches simulation")
controller.paused = true
let pausedTime = controller.simulation.time
advance()
check(controller.simulation.time == pausedTime, "pause freezes weather, leaves and fish")
```
- [ ] Update native tests for 30 fish and weather/lifecycle behavior; run `bash scripts/test-input.sh`, `bash scripts/test-desktop.sh`, `bash scripts/build.sh`, strict signature verification.
- [ ] Document full-scene desktop behavior, weather controls, local image asset origin, primary-screen limit and measured validation. Commit owned files with verification evidence.

## Final verification and local handoff

- [ ] Independent whole-branch review; fix actionable defects and rerun affected checks.
- [ ] Fast-forward the original clean project to the finished branch, build and start the new app after stopping only the old wallpaper process. Inspect actual running wallpaper and weather controls; record runtime stats and remaining manual coverage.
- [ ] Return concise delivery summary, actual rendered preview and application path. Leave system wallpaper settings unchanged.
