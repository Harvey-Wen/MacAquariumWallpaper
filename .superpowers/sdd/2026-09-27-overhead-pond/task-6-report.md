# Task 6 report — full-frame pond

Implemented against the parent replacement asset and canonical 1600×1000 mapping. Changed only PondGeometry, OceanSimulation, App startup weather, simulation/render tests, and verification evidence. No renderer/shader/native input changes.

The water polygon now follows four conservative corner-foliage contours and opens broad sections of all four edges, including the former lower peninsula. Reflections remain water. Signed distance also limits fish to the viewport after aspect cropping. Fish/rain sample the visible screen with existing bounded retries. Four actual branch-tip paths release leaves over foliage and land in adjacent water; falling displacement clamps to remaining fall time, and cropped branches skip their turn without getting stuck on one ID. Existing counts, interaction radii, event cadence, lifetimes and caps remain. App startup selects rainy before controller.start; simulation default remains sunny.

## Verification

- `bash scripts/test-simulation.sh`: **12 passed**. Includes four branch origins and landings, 60-second bounded steady state, rain in all edge bands, whole-body containment under clicks, original local reaction/time/frame regressions. Replaced obsolete bank-grounding scenario with branch-path/expanded-rain checks; grounded implementation unchanged.
- `zsh scripts/test-renderer.sh --preview`: **passed**. 29,139 unchanged foliage samples; explicit fish foliage exclusion with nonempty visible fish on former peninsula; 11 rain impacts / 11,895 changed water samples; atmospheric rain 2,188 foliage + 11,726 water samples; dry/paused/day-seven/wrap/layers/aspects preserved.
- GPU Apple M4 Max, primary 3024×1964, 4× MSAA, 30 koi, rainy: median **3.491333 ms**, p95 **4.922125 ms**, max **4.944625 ms**, 30 measured after 5 warm-up frames.
- `git diff --check`: passed.

## Actual artifacts inspected

All under `/Users/harvey/.codex/worktrees/overhead-pond/MacAquariumWallpaper/.build/render-validation/`:

- `pond-primary-sunny.png`, `pond-primary-rainy.png`: actual 3024×1964 scene; full-frame water, no old bank outline, fish/rings remain outside opaque foliage.
- `preview-frame-0.png`, `preview-frame-30.png`, `preview-frame-59.png`: 1512×982 primary-aspect checkpoints.
- `pond-preview.gif`: actual simulation, 60 frames, 756×491, roughly four seconds. Decoded and viewed `gif-check-0.png`, `gif-check-30.png`, `gif-check-59.png`; rain/ring and fish positions change, composition remains stable.

## Limits / parent handoff

No native desktop/input rerun, final app build, launch, or wallpaper operation performed here. Parent owns those and README/plans/provenance. GPU is offscreen timing, not sustained desktop FPS/power. Mask conservatively outlines foliage clusters, not individual leaf alpha. Canonical logical aspect mapping remains exactly as before; parent directed retaining it despite physical replacement raster 1584×993. No further creative iteration needed.
