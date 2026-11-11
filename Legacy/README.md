# KnotStudio 0.8 — photo-referenced presets

A native macOS SwiftUI / SceneKit app for authored tied-knot appearance. **Preset studio** opens with the four-in-hand visual milestone: unequal leaning shoulders, a softly convex single wrap, concealed upper blade and a recessed dimple between rounded folds. Notation identifies a saved preset. Pratt, Half-Windsor and Windsor remain legacy experimental routes.

This release prioritizes faithful preset rendering. Cloth Lab and all solver experiments are preserved, with further solver work paused. The preset does not claim physical simulation accuracy or arbitrary-sequence rendering. The explicit **Fabric / UV grid / Face identity** selector, imported-image settings and swatch preservation remain.

Build 10 refines the crown and mouth turnovers, shortens the gathering below the knot, and extends the neck bands beyond the front/oblique view. The matched before/after sheet includes the initial 0.8 preset alongside the correction. The broad wrap and back assembly remain idealized.

The two requested photographs were inspected and used only as references. See [reference notes](docs/PREMADE-REFERENCES.md) and [0.8 verification](docs/PREMADE-0.8-VERIFICATION.md) for the shape, measured material-scale limits, before/after evidence, and remaining approximation.

## Open

Requires Apple Silicon and macOS 13+. Extract the ZIP, then double-click `KnotStudio.app`, or run:

```sh
open ./KnotStudio.app
```

The app is ad-hoc signed. Interactive UI behavior and Gatekeeper acceptance have not been tested; no security-setting changes are part of these instructions. The expanded app is `build/KnotStudio.app`. The canonical clean build is `build/KnotStudio.app.zip`: File Provider re-adds Finder metadata to expanded app folders in Documents, so strict local bundle verification may fail after it initially passes. The build script verifies a fresh extraction of the clean archive, and release packaging uses that archive. No unrelated user metadata is removed.

## Use

- Preset studio opens with Four-in-hand. Knot, Side and Portrait select camera presets. Drag to orbit; scroll to zoom.
- **Flat** shows the wide end of the authored blade panel without deformation. It uses the same material chart as the tied view and is useful for checking artwork scale and orientation.
- Import PNG, JPEG, TIFF or HEIC. EXIF orientation is applied once; pixel dimensions determine tile aspect, independent of DPI. At angle zero, artwork is upright on the flat front: narrow end above, wide end below, image right toward viewer right. The centerline samples the image's horizontal center. Camera orbit does not mirror artwork.
- Repeat width and along-fabric offset use nominal centimeters on the authored material charts. Tile height preserves the decoded image aspect. Positive angle rotates artwork counterclockwise in the flat front view.
- An imported swatch describes only the front. Its unspecified reverse is neutral gray, not a copy of the artwork. Teal/rust Face identity and the UV grid help inspect material sides and routing.
- Choose **Fabric** in the Display selector to return from either diagnostic view. Diagnostics no longer replace the selected pattern, angle, offset or repeat; camera orbit and zoom are retained.
- Layer separation is an inspection deformation, not a tightening control. UV coordinates stay fixed.
- PNG export now uses the current orbit, zoom and viewport aspect. Import/export errors are shown. Reset pattern placement preserves the imported image.

The blade and neck folds retain transverse material arc length. The wrap uses a developed cone chart with small authored softening; the hidden crown is an approximation. These panels do not represent one solved blank. The legacy flat-blank assumption remains in `Sources/KnotCore/TieBlank.swift` for the retained experiments.

## Preserved Cloth Lab experiments

Select **Cloth lab · research paused**, then choose **Staged loose wrap**, **Strip over support** or **Fold onto held cloth**. The folded case drops its free layer onto a held lower section. Run/Pause, Step and Reset operate independently of Preset studio. Pause cancels unfinished frame work and can resume. Pause before moving the held end by 1 mm or releasing it; a command takes effect on the next step. Orange markers show held positions. Compare starting shape preserves the solver state while showing its initial geometry. Fabric returns to the swatch selected in Preset studio.

The solver uses the flat blank's physical metre coordinates, area-based mass, separate warp/weft/shear constraints, dihedral bending, gravity, rounded-support/floor contact, and discrete vertex–face/edge–edge self-contact. The material chart stays fixed. It is an uncalibrated mechanical experiment, not surface smoothing. See `docs/CLOTH.md` for equations, units, assumptions and sources.

The solver checks the linear motion path between substeps, including prescribed grasp and constraint corrections. Failed proposals retry with smaller substeps within fixed limits. A rejected frame retains its previous position, velocity and simulated time and displays the reason. The support check includes triangle interiors. Shared-vertex triangle pairs remain excluded; self-contact friction is absent. This is not a formal collision guarantee or calibrated drape model.

The four-in-hand case refuses unsafe motion. It has strong numerical damping; smaller projection limits did not resolve its dynamic failure. The controlled fold also runs much slower than real time. Reset is safe; Preset studio, the 0.3.1 app and the unchanged 0.4 ZIP remain available. The staged wrap is one explicit manipulation script; there is no arbitrary-knot planner. Notation alone does not specify grasp poses, slack or a tuck path.

The permanent source location on the original Mac is `/Users/val/Documents/Software/KnotStudio`. The earlier task location is a symlink to it. The Fabric-view-only checkpoint is `build/checkpoints/KnotStudio-0.3.1.app`; earlier ZIPs remain intact under `deliverables`.

### Staged loose wrap

Choose **Staged loose wrap** and Run. A flat 32 cm strip settles, gradually wraps around a rounded support, holds for 0.5 simulated seconds, attempts a 5 mm axial slide, then stops at 5.5 seconds. The sequence controls both grasps; Reset restores the flat blank. It takes about 162 seconds to compute on the tested host. The free cloth moves only 0.970 mm on average during the slide. Held-wrap RMS strain is 0.534%, final strain 0.632%, with sustained support near-contact. This does not tie or tighten a knot.

The support guard now covers finite triangle interiors, with the same 99% half-thickness acceptance tolerance. Contact response aims 2.5 micrometres outside the nominal shell to accommodate finite iterations. See the current verification report for full-frame and independent snapshot measurements. Earlier app checkpoints and ZIPs remain preserved.

## Build and verify

Use an already installed Apple command-line Swift toolchain:

```sh
zsh Scripts/test-presets.sh
zsh Scripts/test.sh
zsh Scripts/test-view-state.sh
zsh Scripts/test-cloth.sh
zsh Scripts/test-cloth-safety.sh
zsh Scripts/test-cloth-wrap.sh
zsh Scripts/test-cloth-support.sh
python3 Tools/summarize_wrap.py
python3 Tools/render_wrap_cpu.py
zsh Scripts/build.sh
zsh Scripts/test-rendering.sh
zsh Scripts/render.sh artifacts/review fabric,offset,grid,faces,side,back,routing,portrait,imported,imported-shift,imported-angle,flat
zsh Scripts/render-cloth.sh artifacts/cloth-review
python3 Tools/audit_cloth.py artifacts/cloth-review/strip-90.json artifacts/cloth-review/fold-30.json artifacts/cloth-review/four-in-hand-seed-retained.json
```

The rendering checks and preview renderer are windowless but require local graphics access. In a restricted shell, build them with `--build-only` and execute `.build/knot-rendering-checks` or `.build/knot-render` in an authorized graphics environment. They do not launch the application UI.

The app requires no Python. The independent mesh diagnostic uses an already available Python 3 and NumPy:

```sh
.build/knot-render artifacts/preset-review mesh
python3 Tools/audit_preset.py artifacts/preset-review/surface.json

# Optional historical route audit:
.build/knot-render artifacts/legacy-review legacy-mesh
python3 Tools/check_mesh.py artifacts/legacy-review/surface.json --full
```

Use `legacy-mesh` instead of `mesh` to export the old routing surface for the historical full mesh audit. `mesh` exports the new authored preset and its panel metadata. `python3 Tools/audit_preset.py artifacts/preset-review/surface.json` measures the new visible wrap’s material scale. The old diagnostic audits both faces, long edges and tip caps. Shared-vertex triangle pairs remain excluded. Finite-mesh results do not prove smooth-surface separation, contact mechanics or knot topology. The old `check_surface.py` is retained for historical reproduction only.

`Tests/Fixtures` contains the asymmetric swatch and eight EXIF cases; `Tools/make_fixture.py` regenerates them with Pillow when available. No dependency installation is included. Earlier ZIPs remain unchanged in the original working project's `deliverables` directory.
