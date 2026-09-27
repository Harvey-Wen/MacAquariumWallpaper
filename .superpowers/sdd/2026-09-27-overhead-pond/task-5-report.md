# Task 5 — Verdant palette and fine atmospheric rain

Completed the bounded shader/renderer refinement against parent environment asset commit 23625b5. This evidence predates the newly requested Task 6 full-frame water geometry; no geometry, spawn, simulation, lifecycle, or UI changes are included.

## Implementation

- One additional full-screen effect draw after leaves, only while weatherAmount > 0. Existing weather interpolation smoothly controls opacity.
- Fine diagonal streaks use sheared screen coordinates, independent hashed horizontal/vertical placement, tapered ends and derivative antialiasing. Eight procedural rows tile every two seconds without a reset. The shader needs no particle buffers, textures, dependencies or per-frame allocations.
- Reduce existing frame Double time modulo two seconds before Float conversion. Pause retains the same frame time and exact pixels. Dry mode skips the pass.
- Impact-ring shader and shoreline mask unchanged. Atmospheric streaks intentionally cover land as well as water.
- Fresh green/yellow-green leaf palette, jade-tinted surface glints and wet ambient dimming reduced from 10% to 4% preserve a bright early-summer scene. Fish rendering untouched.

## Verification

Command: `zsh scripts/test-renderer.sh --preview` — PASS after final vertical-spacing refinement.

- Isolated atmospheric test holds all visible actors and water motion off: 7,452 sampled land pixels and 6,225 water pixels change over 1/30 second.
- Dry isolated frames are byte-identical at different times; paused wet frame is byte-identical on repeat.
- Twelve 30 FPS steps at day seven retain movement. A 0.2 ms interval across the two-second wrap differs by less than 10% of an ordinary frame change. Initial and day-seven same-phase images match byte-for-byte.
- 11 rain impact rings change 12,073 water samples; all sampled land remains unchanged with only the rings toggled.
- Existing 94,889 unchanged land ripple samples, water/surface leaf ordering, falling leaf landing convergence, fish phase/heading continuity, empty/opaque/missing resource and aspect-ratio assertions pass.
- Rainy benchmark now measures the rainy frame including streaks and rings, at 3024×1964, 4× MSAA, 30 koi on Apple M4 Max: median 2.064750 ms, p95 4.274167 ms, max 4.352750 ms (30 samples after 5 warm-ups). This is completed Metal command GPU duration only, not desktop pacing or power.
- `git diff --check` passed.

## Artifacts and inspection

All outputs under `/Users/harvey/.codex/worktrees/overhead-pond/MacAquariumWallpaper/.build/render-validation/`:

- `pond-sunny.png`, `pond-rainy.png`, `pond-click.png`, `pond-no-fish.png`, `pond-layer-check.png`.
- `pond-1200x1200.png`, `pond-1800x900.png`, `pond-900x1400.png`.
- `pond-preview.gif`: 60 real rainy simulation frames at 800×500, approximately four seconds, 3.9 MB.
- `preview-frame-0.png`, `preview-frame-15.png`, `preview-frame-30.png`, `preview-frame-45.png`, `preview-frame-59.png`: full-resolution checkpoints from that preview.

Viewed the parent source image, sunny/rainy exports and five checkpoints. Initial inspection found overly aligned rain rows; independently randomized their vertical centers and reran the suite/exports. Reinspected final rainy export and checkpoints 15/45: subtle rain is visible across plants/water without overpowering fish or rings. Parent also accepted rainy composition/palette. This is checkpoint inspection, not a claim of human real-time GIF playback. Full application build, launch, live pause/weather, and new Task 6 geometry are parent-owned follow-up checks. Existing simulation/desktop/input suites were not rerun for these bounded rendering changes.

## P2 review follow-up — rain-only frame

Review identified that the preexisting early-out ignored weatherAmount. Removed the opacity-zero test leaf and added direct assertions that the empty dry frame remains fully transparent and a rain-only frame produces pixels. Ran `zsh scripts/test-renderer.sh` before the fix: exited 133 at the new regression (optimized precondition trap). Added `frame.weatherAmount > 0` to the existing encode guard; no other rendering behavior changed.

Reran `zsh scripts/test-renderer.sh`: PASS, including real actor-free rain, dry transparency/static output, pause identity, day-seven and wrap continuity, all 94,889 unchanged land ring samples and all previous renderer assertions. Rain motion still changes 7,452 land/6,225 water samples; 11 impact rings change 12,073 water samples with no land impact. Latest rainy GPU median 2.170167 ms, p95 4.516083 ms, maximum 4.635417 ms. No GIF regeneration needed for guard-only behavior; existing full-scene visual output is unchanged. Tests still use the pre-Task6 environment. `git diff --check` passes.
