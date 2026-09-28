# Hand-painted Fish Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, task by task. User approved the design and implementation on 2026-09-28; no additional execution-choice approval is needed.

**Goal:** Paint a koi, add it to the pond, preserve its appearance after restart.

**Architecture:** Codable strokes persist independently per fish. AppKit draws the editor and rasterizes the same model coordinates into a cached Metal texture. The existing simulation and renderer accept an optional appearance UUID, retaining default koi behavior.

**Tech Stack:** Swift, AppKit, CoreGraphics, Metal, existing shell test scripts.

## Global Constraints

- macOS 14+, local only, no dependencies or permissions added.
- Retain the current koi shape and all existing movement, interaction, lighting, and water effects.
- Paint body only; color palette, custom color, width, eraser, undo, clear, cancel, add.
- One fish per successful add; persisted fish restore once; write failure retains draft.
- Hidden pond becomes visible on add; pause stays unchanged.
- Protect concurrent main-checkout work. Run wallpaper-changing tests only with the live app stopped.

## Task 1: Drawing data, persistence and simulation

**Files:** Create Sources/FishDrawing.swift, Tests/DrawingTests.swift, scripts/test-drawing.sh. Modify Sources/OceanTypes.swift and Sources/OceanSimulation.swift.

**Interfaces:** FishDrawing (Codable, Equatable) contains id: UUID and strokes: [FishStroke]. FishStroke contains normalized points, color components, width and erasing flag. FishDrawingStore(directory: URL), load() -> (drawings, errors), save(_:). OceanSimulation.addCustomFish(appearanceID: UUID) appends only if absent. FishState.customAppearanceID: UUID? defaults to nil.

- [x] Add temporary-directory tests for round trip, independent records, corrupt file preservation, write failure, unique fish count, unchanged existing positions, water spawn, movement and click response.
```swift
let before = simulation.fish
simulation.addCustomFish(appearanceID: drawing.id)
simulation.addCustomFish(appearanceID: drawing.id)
precondition(simulation.fish.count == before.count + 1)
precondition(Array(simulation.fish.dropLast()).map(\.position) == before.map(\.position))
```
- [x] Run `bash scripts/test-drawing.sh`; initially fails for missing definitions.
- [x] Implement Codable data, per-UUID atomic JSON records, independently decoded loads, body projection and rasterization. Use `OceanSimulation.randomWaterPoint` and existing speed/length ranges to append without rebuilding.
```swift
var customAppearanceID: UUID? = nil
// Store writes one validated drawing to <UUID>.json atomically.
try JSONEncoder().encode(drawing).write(to: url, options: .atomic)
```
- [x] Run drawing and simulation checks, then commit this module.

## Task 2: Render custom appearances

**Files:** Modify Sources/OceanRenderer.swift and Resources/Ocean.metal; create Tests/CustomFishRenderTests.swift and scripts/test-custom-fish-renderer.sh.

**Interfaces:** OceanRenderer.registerDrawing(_ drawing: FishDrawing) throws and removeDrawing(id: UUID). FishDrawing.makeImage() -> CGImage uses the same top-down coordinates as the editor. New fish uniforms carry an enabled flag; texture binds at index 4.

- [x] Render two different asymmetrical drawings and assert colors stay attached through heading/phase changes, the original fish retain identical pixels, and missing appearances fall back safely.
```swift
try renderer.registerDrawing(redDrawing)
let painted = try renderer.renderRGBA(frame: frame, width: 800, height: 500)
precondition(painted != unpainted)
```
- [x] Create cached RGBA textures on registration only, with a 1-pixel fallback bound for default fish; add matching CPU/Metal uniform member.
```metal
if (u.appearance.x > 0.5 && in.detail.x == 0)
    color = paint.sample(linearSampler, float2((in.local.x + 0.6) / 1.2, 0.5 - in.local.y / 0.6)).rgb;
```
- [x] Keep existing normal, scale, fin, shadow and water stages. Extend existing renderer test build inputs to include the drawing file.
- [x] Run custom-fish render tests and the existing renderer suite, inspect actual frame output, commit.

## Task 3: Editor and app integration

**Files:** Create Sources/FishDrawingWindow.swift. Modify Sources/App.swift, Sources/DesktopController.swift, affected test compile scripts, README.md, docs/verification.md.

**Interfaces:** FishDrawingWindowController(onAdd: @escaping (FishDrawing) throws -> Void), showWindow(_:) displays the draft; callback success closes, failure presents a sheet and preserves strokes. DesktopController.addCustomFish(_:) registers texture, atomically saves, appends, displays and renders. Store injection supports temporary directories for tests.

- [x] Implement native NSView canvas using shared body projection, mouseDown/Dragged/Up strokes, clipping, selected palette state, brush slider, erase, undo, clear, cancel and primary add button. Keep one editor window; close resets the next draft.
```swift
do { try onAdd(drawing); close() }
catch { NSAlert(error: error).beginSheetModal(for: window!) }
```
- [x] Load drawings before the first desktop frame; failed records produce a menu-visible warning; successful add updates static backdrop cache identity and diagnostics.
- [x] Verify via native UI: menu entry, drawing, undo, eraser, add, pond appearance, pause retention, cancel and restart persistence. Use an isolated editor fixture for repeatable automated coverage without polluting user fish storage.
- [x] Run drawing, simulation, input, custom render and full render checks; build and validate signature. Update README and actual validation evidence, commit.
- [x] Integrate with latest completed main-checkout changes without overwriting uncommitted work, stop the prior app normally, build and launch a single final instance, verify diagnostics.

## Review

All approved spec behaviors map to a task. No independent subsystem or speculative UI feature is added. The implementation proceeds inline in the existing isolated worktree.

## Completion evidence

Completed and merged into the original checkout on 2026-09-28. See docs/verification.md for exact native/automated evidence and CUA coordinate-drag limitation. Final runtime PID51128 reports30 default fish, zero custom-load errors, working input, no backdrop error and709 frames after about25 seconds; no test fish were added to user storage.
