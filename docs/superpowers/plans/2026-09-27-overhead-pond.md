# 俯瞰池塘 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver the approved overhead pond as an interactive macOS desktop wallpaper, including the user-requested verdant rainy park revision and matching menu-bar backdrop.

**Architecture:** A fish-free environment texture supplies full-frame open water and overhanging foliage per the latest composition revision. Shared visible-water geometry governs simulation, mouse hits and the renderer mask. Native Metal draws independent koi, animated water/refraction, rainfall ripples and leaves; existing AppKit desktop window and input filtering remain.

**Tech Stack:** Swift 5, AppKit, Metal, macOS 14+, local resources; existing SDK selection in scripts.

## Global Constraints

- Detailed natural scenery with the latest verdant rainy park palette, fixed overhead camera, full-frame open pond with peripheral tree branches, around 30 koi.
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

- [x] Write meaningful tests for 30 deterministic koi, water/land click distinction, local click falloff and bounded repeated clicks, rain start/stop and local mild response, actual leaf landing/floating/expiry/wave motion, boundary containment under repeated disturbances, resize/aspect mapping and 30/5 FPS equivalence.
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
- [x] Run `bash scripts/test-simulation.sh`, record the initial failing requirement, implement and rerun.
- [x] Local rain events have weaker/smaller fish influence than clicks. Floating leaf approach is weak and limited to nearby fish; leaf water motion derives from nearby waves. Spawn leaves near visible overhanging trees and cap/expire all effects. Use continuous phase integration and seeded randomness.
- [x] Commit only owned files and write task report with test evidence. Other render/controller files may be temporarily incompatible until subsequent tasks.

### Task 2: Realistic Metal scene

**Files:** Modify `Sources/FishMesh.swift`, `Sources/OceanRenderer.swift`, `Resources/Ocean.metal`, `Tests/RenderTests.swift`, `scripts/test-renderer.sh`, `scripts/build.sh`; consume new `Resources/PondEnvironment.png` supplied by parent.

**Interfaces:** Consume Task 1 types and shared geometry. Preserve `OceanRenderer.init(view:shaderURL:)`, `renderRGBA`, `writePNG`. Expose the completed command buffer's GPU duration for benchmark evidence. Load environment relative to shaderURL. Generate a water distance texture from shared geometry, sampled by every water-related layer. Resource errors must be readable and fail initialization rather than silently dropping the environment.

- [x] Replace ocean-specific fish mesh with tapered top-down koi body, paired fins, forked tail, eyes, appropriate dorsal detail. Keep independent tail/fin animation and rotate in the screen plane, without side-view yaw.
- [x] Draw opaque environment, submerged fish/shadows, restrained animated surface/refraction, local rain/click/leaf ripples, then leaves. Water mask bounds all aquatic effects. No baked static fish, rain rings or floating leaves in the environment.
```swift
let sunny = simulation.frame(waterStrength: 0.45)
let pixels = try renderer.renderRGBA(frame: sunny, width: 1600, height: 1000)
precondition(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
```
- [x] Build render tests covering full opacity, `.empty`, no-fish vs fish image difference, land unchanged by ripples, underwater vs overwater layers, time continuity including day 7, dry/rain difference and multiple output aspect ratios. Export inspectable sunny/rain/click PNGs and an optional short video/animation preview from genuine frames. Run `zsh scripts/test-renderer.sh`.
- [x] Measure GPU at actual display resolution, optimize if needed to meet 30 FPS. Inspect exported images against approved visual reference and revise obvious appearance faults before committing. Commit owned files and report paths/results.

### Task 3: Desktop controls and delivery

**Files:** Modify `Sources/App.swift`, `Sources/DesktopController.swift`, `Resources/Info.plist`, `Tests/DesktopTests.swift`, `scripts/test-desktop.sh`, `README.md`, `docs/verification.md`.

**Interfaces:** Use simulation.weather for sunny/rainy switching, remove controller hover/drag simulation hooks; keep low-level desktop input filters. Rain amount transitions via simulation updates. Status text uses live fish count. Keep app executable/bundle identity to avoid competing application identities.

- [x] Replace user-facing ocean text with pond text, provide weather selection, show/pause/interaction/quit controls, no obsolete water-intensity submenu. Route only valid desktop clicks into simulation.
```swift
controller.weather = .rainy
check(controller.simulation.weather == .rainy, "weather control reaches simulation")
controller.paused = true
let pausedTime = controller.simulation.time
advance()
check(controller.simulation.time == pausedTime, "pause freezes weather, leaves and fish")
```
- [x] Update native tests for 30 fish and weather/lifecycle behavior; run `bash scripts/test-input.sh`, `bash scripts/test-desktop.sh`, `bash scripts/build.sh`, strict signature verification.
- [x] Document full-scene desktop behavior, weather controls, local image asset origin, primary-screen limit and measured validation. Commit owned files with verification evidence.

## Final verification and local handoff

- [x] Independent whole-branch review; fix actionable defects and rerun affected checks. Subsequent user revisions also independently reviewed.
- [ ] Fast-forward the original clean project to the finished branch, build and start the new app after stopping only the old wallpaper process. Inspect actual running wallpaper and weather controls; record runtime stats and remaining manual coverage.
- [ ] Return concise delivery summary, actual rendered preview and application path. While enabled, use the reversible pond system backdrop required by Task 4; restore the original image on disable/quit.

### Task 4: Match the menu-bar backdrop (user addition)

**Files:** Create `Sources/DesktopBackdrop.swift`; modify `Sources/DesktopController.swift`, `Sources/App.swift` only if status reporting needs it, `Tests/DesktopTests.swift`, `scripts/test-desktop.sh`, `README.md`, `docs/verification.md`.

**Interfaces:** Main-actor `DesktopBackdrop` owns temporary NSWorkspace desktop-image changes on the current main screen, with apply/restore methods invoked by DesktopController. Use an application-support record (original URL and display options, target display ID and owned applied URL) and generated PNG frames in a dedicated app-owned directory. Preserve original image/options BEFORE setting any backdrop. Current view renderer.writePNG can capture a static pond frame at display backing resolution; render using target weatherAmount (0/1) for switching weather without waiting for transition. Use unique file URL per replacement so wallpaper caches refresh. Keep image aspect matched to screen. Never capture user screen pixels.

- [x] Apply on enable/start, update on weather or display geometry changes, restore on disable/stop. Pause retains backdrop, sleep/lock hide animation without restoring backdrop. Avoid per-frame disk writes or desktop-image changes.
- [x] Restore only when the screen currently uses this app's owned backdrop; preserve any newer user-selected wallpaper. Persist restoration record for restart after crash; clear records/old generated files only after successful replacement or restoration. Restore and keep prior screen record when changing main screen as possible; don't modify other monitors.
- [x] Handle apply/restore errors visibly in diagnostics/menu status; do not lose recovery records or overwrite original wallpaper if backup persistence fails. Prefer small focused helper, no global preference changes/private APIs.
- [x] Native tests check runtime scene URL is installed, weather replaces backing image URL, pause does not churn it, disable/stop restores original URL/options, and application/test lifecycle does not leave a background behind. Add focused fake-provider tests only if needed for failure/recovery/user-override state transitions; don't add generic frameworks.
- [x] Update docs: earlier no-system-wallpaper-change statement is superseded by the user's menu-bar requirement; describe reversible temporary background and any unverified dynamic-HEIC/Spaces behavior accurately. Run build, desktop/input checks and signature validation; commit independently.

### Task 5: Verdant rainy park art direction (user revision)

**Files:** `Resources/PondEnvironment.png` supplied by parent; modify `Resources/Ocean.metal`, `Sources/OceanRenderer.swift`, `Tests/RenderTests.swift`; documentation in `docs/concepts/README.md` and `docs/verification.md`.

**Intent:** The user explicitly replaces the muted original palette with the rich green rainy park atmosphere of The Garden of Words. Retain the approved straight-down irregular pond and interactions. The supplied Douyin reference was inspected in the in-app browser: teal water, subtle koi, fine diagonal rain, light interaction; use these motion qualities without copying its layout or adding clocks/controls.

- [x] Integrate the parent's imagegen-restyled environment while preserving the shared shoreline; lush emerald/jade foliage, cool wet mossy stone, clear green water, detailed painted naturalism. No baked fish, rain, ripples or floating leaves.
- [x] Add restrained animated fine diagonal rain streaks in rainy weather. Rain falls over the whole scene (including foliage), whereas impact rings remain clipped to water. Dry mode has no streaks. Use existing frame time with stable periodic phase and no per-frame allocations or new dependencies. Preserve smooth day-seven motion and pause semantics.
- [x] Harmonize water glints and leaves with the green early-summer palette; leaves should be predominantly fresh green with restrained yellow-green variation. Avoid darkening the scene into muddy black. Keep fish readable and modestly sized, no new UI or features.
- [x] Extend existing meaningful renderer checks for rain-only motion, no dry streaks, and long-running continuity. Preserve ring-on-land exclusion and layer checks. Export sunny/rainy stills and real rendered GIF, visually inspect and measure rainy GPU performance at 3024×1964.
- [x] Commit code/tests as a verified module and record exact evidence. Parent handles generated asset and provenance documentation, final build/live verification and default weather demonstration.

### Task 6: Open the pond across the full screen (latest user revision)

**Files:** Parent supplies replacement `Resources/PondEnvironment.png`. Agent owns `Sources/PondGeometry.swift`, `Sources/OceanSimulation.swift`, `Sources/App.swift` for initial weather only, `Tests/SimulationTests.swift`, necessary `Tests/RenderTests.swift` sample-position updates, and `docs/verification.md` evidence.

- [x] Inspect the new image. Remove the original irregular enclosed-bank polygon. Shared visible-water mask must match the open water and conservatively exclude only overhanging edge foliage. Water extends through broad areas of all four screen edges; no physical bank is depicted. Keep exact centered aspect-fill mapping.
- [x] Expand fish initialization and rain sampling beyond the old small central pond. Keep 30 koi, body clearance, bounded effects and deterministic timing. Update leaf launch points to several actual overhanging branches, with falling velocity directed toward adjoining water. Leaves should be visibly attached to a plausible branch origin and enter nearby water; no old north-bank-only assumptions.
- [x] Adapt genuinely obsolete bank-specific tests to the new composition. Test open water where the old bottom peninsula was, conservative foliage rejection, source/screen mapping, fish containment under disturbances, local interactions, leaf landing/ripples and bounded steady state. Avoid assertions that pass only through empty loops; exercise both foliage and water samples for render exclusion. Keep day-seven/rain/pause/layer regressions.
- [x] Run simulation and renderer `--preview` after asset integration, inspect final sunny/rainy/GIF checkpoints at primary display aspect; verify no fish/rings drawn on foliage and no visible old bank outline. Record actual GPU benchmark and output paths.
- [x] Start the interactive application in rainy weather to demonstrate the requested rainy-park scene, retaining the existing sunny/rainy menu. Set this in application startup before start, not the simulation default used by deterministic tests.
- [x] Commit the verified module and write report. Do not change desktop helper/input, add features, or rework unrelated simulation algorithms. Parent handles final build, native integration check, original-checkout sync and launch.
