# KnotStudio 0.8 verification

This release pivots the app to photo-referenced authored presets. The four-in-hand is the first appearance milestone. Preset studio is the primary tab; Cloth Lab is retained and labeled “research paused.” The permanent project location is unchanged.

## Visual evidence

The two requested photographic references were inspected before remodeling. See `PREMADE-REFERENCES.md`. No reference image is included in the app or package.

`Previews/four-in-hand-material-review-0.8.png` compares front and oblique views in gray, dots and stripes. `Previews/four-in-hand-before-after-0.8.png` compares the preserved 0.7 route with the new preset. The comparison now has three columns: legacy 0.7, the initial 0.8 preset, and the focused 0.8 correction. Every column uses the same front/oblique camera transform, orthographic scale 4.7, gray material, lights, and ambient occlusion intensity 0.85 (radius 1.4, bias 0.035). The image itself states these matching conditions. Legacy geometry is unchanged; only its comparison capture settings are overridden. These are windowless SceneKit renders, not application screenshots or retouched artwork.

The inspected pixels show a leaning crown with unequal shoulders, one convex front wrap, an upper blade concealed behind it, a narrow asymmetric exit, and a recessed dimple between rounded folds. The protruding entry panel remains removed. The focused correction improves four visible defects: the crown now curls inward through a rounded crest, the lower mouth turns inward with a small asymmetric compression fold, the blade gathering releases over a shorter distance immediately below the knot, and extended neck bands place their square ends outside both accepted camera views. The comparison sheet directly shows the initial and revised presets. These changes reduce the cuff-like impression; they do not establish finished fidelity. Dots keep similar local size on the visible wrap and blade; stripes turn independently with their different material directions. The imported asymmetric text/color fixture and Face identity render were also inspected.

The model is still stylized: the front wrap is regular, the neck entries are simple bands, and fine wrinkles/contact shadows are limited. The crown turnover, abrupt back-panel joins, other panel seams and hidden assembly are approximations. The broad body is still an idealized tapered wrap; small wrinkles and fabric-dependent compression are not reconstructed. Front and oblique acceptance does not certify every orbit angle, global self-intersection freedom or topology. There is no calibrated fabric prediction or arbitrary-sequence rendering claim.

## Checks completed

- `Scripts/build.sh`: SwiftUI/SceneKit arm64 app built with the installed Command Line Tools; version 0.8, build 10. Ad-hoc signature verified on a fresh extraction of the clean app archive.
- `Scripts/test-presets.sh`: deterministic mesh; finite normals; nondegenerate front/back/edge triangles; unchanged UVs during layer separation; sloped unequal shoulders; exit/crown width ratio 0.559; recessed dimple; identical flat/tied blade charts; short dimple release rather than long parallel pleats; sampled tucked blade occluded by the wrap, minimum front depth gap 0.220 cm.
- Blade transverse arc-length error: maximum 0.2044%. This checks geometric material length across the folded blade, not a solver.
- `Tools/audit_preset.py`: independent singular-value measurement of emitted world triangles against their material coordinates over the visible wrap interior. Ratios: minimum 0.9788, median 1.0133, 95th percentile 1.0907, maximum 1.1125. The rolled edges and inset crown are outside this measurement. It is not an isometry claim.
- `Scripts/test.sh`: preserved notation/legacy geometry checks passed, including the 85-sequence notation enumeration. This validates notation and stored routes, not authored renderings for 85 knots.
- `Scripts/test-view-state.sh`: 180 display transitions passed; imported image, repeat, angle and offset retained through Fabric / UV grid / Face identity.
- `Scripts/test-rendering.sh --build-only`, then `.build/knot-rendering-checks`: actual uploaded preset UV buffers and imported-image material behavior passed. All eight EXIF orientations and non-square repeat aspect checked. Independent rendered samples: flat 126/128; repeat/offset 128/128; rotated 125/128. Neutral reverse confirmed. 3,287 total decoding, material, buffer and pixel checks passed.
- Package-root README links now resolve through `Source/docs`; the source README retains its correct `docs` links. The root README also names `cd Source` before the build commands.
- Final offscreen set: 19 PNGs, including six material/camera views, imported-image variants, flat blade, faces, grid, back, portrait, and four legacy comparison views. Six initial-preset PNGs are included separately for the matched three-column before/after sheet. Pixels inspected in the six-view sheet, before/after sheet, imported oblique and Face identity renders.
- Legacy mesh export still provides `ribbon.json`, row metadata and phases for historical audit tools.
- The 22 solver/legacy source and experiment files listed in `Evidence/source-comparison.txt` are byte-identical to the 0.7 package. Solver dynamics were not rerun; no solver changes were made.
- The seven older release ZIPs plus the retained first-milestone 0.8 ZIP match their recorded SHA-256 values. The first 0.8 package is preserved as `KnotStudio-Presets-0.8-first-milestone.zip`.

## Interactive limits

Native UI automation was not invoked. Live import/export dialogs, orbit/zoom, tab selection, sliders, display selector interaction, and Gatekeeper launch were not interactively retested. Their implementation compiled; display-state transitions, image decoding, material buffers and offscreen rendering were checked independently. The app is ad-hoc signed, not notarized.

No Xcode license was accepted, permission settings changed, software installed, project relocated or reference photograph shipped.

## Changed files relative to 0.7

- `Sources/KnotCore/PremadeFourInHand.swift`: new appearance mesh and panel material charts.
- `Sources/KnotCore/Surface.swift`: direct panel-mesh initializer (inherited from the unfinished preset branch at task start).
- `Sources/KnotStudio/Scene.swift`: preset selection, close framing, lighting and ambient occlusion; preserves legacy route inspection.
- `Sources/KnotStudio/App.swift`: preset-first language and notation lookup; retained explicit diagnostic selector and imported settings; labeled solver research as paused.
- `Scripts/build.sh`, `Scripts/test-presets.sh`, `Scripts/package-presets.sh`: 0.8 build metadata, deterministic checks and reproducible packaging.
- `Tests/PresetChecks.swift`, `Tests/RenderingChecks.swift`: new shape/material checks and production preset buffer checks.
- `Tools/Render.swift`, `Tools/audit_preset.py`, `Tools/preset_review_sheet.py`: actual preset export, independent scale audit, offscreen comparison sheets.
- `README.md`, `docs/PREMADE-REFERENCES.md`, this report: current scope, references and evidence.
