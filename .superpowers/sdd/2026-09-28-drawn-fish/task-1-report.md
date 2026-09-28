# Task 1 report — drawing data, persistence, simulation

## Result

Implemented normalized drawing data, an independent JSON record store, a cached koi body mask derived from `FishMesh`, raster painting on a white body with transparent exterior, and incremental custom fish insertion. No existing fish is rebuilt or repositioned when a drawing is added.

## Public interfaces

- `FishPoint(x:y:)`: both values are normalized 0...1; y grows downward. Local koi coordinates map as `x = (localX + 0.6) / 1.2`, `y = (0.3 - localY) / 0.6`.
- `FishColor(red:green:blue:)`: components 0...1.
- `FishStroke(points:color:width:erasing:)`: width is a fraction of canvas height. An erasing stroke paints white.
- `FishDrawing(id:strokes:)`, `FishDrawing.bodyPath(width:height:) -> CGPath`, and `drawing.rasterizedImage(width:height:) -> CGImage?` (default 512x256). The body path is in CoreGraphics bottom-up pixel coordinates; use `(point.x * width, (1 - point.y) * height)` to draw a normalized point in that space.
- `FishDrawingStore(directory:).save(_:) throws` and `.load() -> (drawings: [FishDrawing], errors: [String])`. Each drawing is saved atomically as `<UUID>.json`. Malformed files produce warnings and remain on disk; other valid records still load.
- `FishState.customAppearanceID: UUID?` defaults to nil; `OceanSimulation.addCustomFish(appearanceID:)` appends once per UUID.

## Verification

- RED: `bash scripts/test-drawing.sh` initially failed because `Sources/FishDrawing.swift` was absent.
- GREEN: drawing tests pass for independent round trips, corrupt and invalid record preservation, write failures, red paint, white erasure, transparent exterior, unique insertion, unchanged existing positions, water spawn, movement, and click response.
- `bash scripts/test-simulation.sh`: 18 passed.

## Self-review

The body outline is read from the existing mesh once and shared by the editor path and rasterizer. Store saves and loads validate normalized finite data. Drawing textures are generated on demand; the renderer should cache each texture by drawing UUID and refresh it after editing. The mask covers the koi body, while fins and tail remain rendered by their existing mesh materials.
