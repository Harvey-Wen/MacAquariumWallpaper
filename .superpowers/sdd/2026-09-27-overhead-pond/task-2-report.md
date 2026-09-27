# Task 2 — Metal pond renderer

Implemented the approved top-down scene with the parent-supplied fish-free environment. The render order is opaque aspect-filled environment with masked refraction, submerged koi and local shadows, water surface glints, bounded impact rings, then falling/floating/grounded leaves. All underwater effects sample an 800×500 signed-distance texture generated from `PondGeometry`; floating leaves also sample it. Falling leaves intentionally may pass over land.

The koi mesh has a blunt head, tapered body, paired pectoral/pelvic fins, forked caudal fin, dorsal ridge and two eyes. Screen-plane rotation remains continuous at vertical headings. Tail bends and pectoral motion use the integrated fish phase. Individual ids select asymmetrical ivory/red/gold/black markings. Fins are translucent, body shading is restrained, and environment reflection plus depth absorption place fish below the surface. Visual inspection of the first sunny export led to brighter ivory, gold and red colors and a less dominant red patch distribution. Rain impacts were increased after inspecting the rainy export.

`OceanRenderer` preserves init/renderRGBA/writePNG and exposes `lastGPUSeconds` from completed command buffers. Missing or invalid environment texture fails init with a readable path/error. `scripts/build.sh` copies the environment into the application resources.

## Verification

Command: `zsh scripts/test-renderer.sh --preview` — PASS on Apple M4 Max.

- Empty frame remains zero RGBA; populated scene is fully opaque.
- Finite mesh attributes and triangle counts.
- Missing environment fails with readable resource name.
- Fish versus no-fish output differs.
- Ripples change water, while 94,889 sampled land pixels remain identical.
- Rain ambient appearance differs from dry appearance.
- Floating leaf center occludes a koi while surrounding underwater fish remains visible.
- Fish pose changes with integrated phase; wrap and near-vertical heading changes remain continuous.
- Twelve successive 30 FPS steps at day seven continue changing water; both independent phase wrap boundaries remain continuous.
- Opaque output at 1200×1200, 1800×900 and 900×1400 aspect ratios.

Measured completed GPU command duration at 3024×1964, 4× MSAA, 30 koi, after 5 warm-up renders and 30 timed frames: median **2.834 ms**, p95 **4.495 ms**, max **4.860 ms**. This is GPU work only, not application lifecycle or wall-clock display pacing. 30 FPS GPU budget passes comfortably.

Inspectable genuine rendered output in `.build/render-validation/`:

- `pond-sunny.png`, `pond-rainy.png`, `pond-click.png`
- `pond-no-fish.png`, `pond-layer-check.png`
- `pond-1200x1200.png`, `pond-1800x900.png`, `pond-900x1400.png`
- `pond-preview.gif`: 60 actual rainy simulation frames, 800×500, approximately four seconds.

Inspected approved concept and actual sunny, rainy and click PNGs. The scene composition matches the fixed overhead pond, fish remain in water, and rings remain local. Fish are procedural geometry and retain a somewhat cleaner appearance than the photographic environment; no external runtime textures or services are required beyond the bundled environment. Application build/lifecycle, desktop ordering, click monitoring and pause/sleep/lock are Task 3 and are not claimed verified here.
