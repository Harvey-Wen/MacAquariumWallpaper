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

## Focused visual refinement after parent review

The first procedural fish had overly angular membranes and high-frequency markings. Replaced rigid fin fans with smooth Catmull-Rom outlines and subdivided membranes, added subtle radial fin rays and transparency toward fin tips, strengthened curved back/side shading without sharp specular shine, softened color patch boundaries and reduced mottled/scaly contrast. Broadened and faded the local underwater shadow, and added environment brightness-dependent reflection blending. Leaves now have asymmetric lobes, irregular margins, fine color variation, midrib/branch veins and curled blade lighting. Rain ring visibility was increased in the shader only; simulation behavior and panic strengths were untouched.

Regenerated `pond-sunny.png`, `pond-rainy.png`, `pond-click.png` and the full 60-frame GIF. Inspected sunny/rain/click images and five full-resolution checkpoints spanning the preview (`preview-frame-0.png`, `15`, `30`, `45`, `59`): fish change heading without flipping, tail/fin poses vary, leaves remain small and move across the surface, and rain produces local delicate concentric rings. These are rendered checkpoints, not a claim of human real-time playback verification. Parent independently inspected the revised sunny frame and accepted it as suitable for the first dynamic build.

Reran `zsh scripts/test-renderer.sh --preview`: all assertions PASS. Latest 3024×1964 M4 Max sample: median **2.983 ms**, p95 **3.865 ms**, max **6.269 ms** (30 timed frames after 5 warmups). No API, simulation, geometry, or application lifecycle changes in this refinement.

## Scoped review fixes

Removed the discrete falling/floating size switch in the shader. The renderer now applies a smoothstep descent from 1.35× to 1× using leaf age/fall duration before landing, with zero slope at both ends. A regression render compares the full descent with the last millisecond before landing and requires the landing discontinuity to be below 1% of the full descent difference.

Added a direct rain-impact regression using the genuine rainy simulation frame: keep weather, time, fish and leaves identical, remove only rain ripples, and compare outputs. PASS: **11 active rain impacts**, **12,593 changed water samples**, every checked land sample unchanged. This verifies ring rendering independently of ambient dimming. Adjusted only the rain fade exponent from 1.5 to 0.8 so older delicate rings remain readable; inspected the regenerated 1600×1000 rainy image, where several rings are now visible across left, central and right water. Fish behavior, ripple radius and lifetimes are unchanged.

`zsh scripts/test-renderer.sh --preview` PASS; all images, five preview checkpoints and GIF regenerated. Latest GPU result: median **2.983 ms**, p95 **4.262 ms**, max **4.286 ms** at 3024×1964. Scope: renderer leaf scale, rain fade, and regression tests only.
