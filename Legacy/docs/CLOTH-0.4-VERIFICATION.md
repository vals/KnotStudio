# 0.4 verification and known failures

Verified with filesystem tools, deterministic executables and windowless SceneKit snapshots. No native UI automation, browser, screen capture, accessibility calls, license acceptance, software installation or security-setting changes were used. The app has not been interactively clicked through.

## Usable checkpoint and regressions

- **0.3.1 Fabric-view checkpoint:** built and ad-hoc signature verified. `build/checkpoints/KnotStudio-0.3.1.app` is preserved separately.
- **180 display-transition checks:** repeated UV grid / Face identity / Fabric changes preserve the original imported image object, colors, repeat, offset and angle; edits made during diagnostics return correctly to Fabric.
- **177,621 existing core assertions:** pass, including all 85 FM sequences and the authored frame/chart/face checks.
- **3,711 rendering checks:** pass, including all eight EXIF orientations, DPI independence, material sides, actual SceneKit geometry buffers and 379/384 sampled rendered-pixel anchors across three placement cases. The five mismatches remain within the existing tolerance; no new regression is claimed.
- **450 cloth checks:** pass. These cover rest and rigid-motion invariance, analytic membrane and dihedral gradients against finite differences, separate stretch/shear relaxation, near-isometric bending, floor/capsule thickness, sampled vertex–face and crossing edge–edge separation, external friction bounds, timestep comparison, immutable chart, reset determinism, grasp translation/release, and unsafe-frame rollback. A fast vertex–face crossing intentionally reproduces the discrete collision limitation.

## Controlled strip result

The 205-vertex, 320-triangle tapered strip has a rest chart taken from 72–108 cm along the assumed blank. Both end patches are initially held. Its initial folded shape is intrinsically unstretched. At 90 frames / 1.5 simulated seconds:

| Measure | Result |
|---|---:|
| Area-weighted RMS strain (weft, warp, normalized shear) | 0.00283 (0.283%) |
| Warp stretch range | 0.9934–1.0103× |
| Weft stretch range | 0.9983–1.0045× |
| Maximum shear angle | 0.90° |
| Minimum vertex-to-support gap beyond shell thickness | approximately 0 m |
| Peak speed | 0.0169 m/s |
| Nonshared mid-surface triangle intersections at the final snapshot | 0 |

Three versus six substeps per frame differ by 1.714 mm in mean vertex position after 0.5 simulated seconds; the regression limit is 3 mm. This is a bounded numerical check, not convergence or calibration. Solid contact constrains cloth vertices; triangle interiors and swept motion are not certified.

The saved strip render plausibly resembles a thin fabric strip bending around a rounded support. Orange points identify held patches; suspended tips are constrained, not levitating free cloth. The mesh is coarse and lighting is illustrative.

## Four-in-hand: failed contact milestone

The full authored route is sampled into **1,100 vertices / 1,752 mid-surface triangles**, with rest dimensions taken from the full 145 cm flat blank. Coarsening changes geometry: the new seed already has **2 nonshared triangle intersections**, despite the earlier full authored render mesh having passed its own finite-mesh audit.

The ordinary strip solver settings reject the knot's high-energy initial deformation. The exposed experiment uses 12 substeps/frame and strong damping 80/s. It advances, but this does **not** produce a valid knot:

| Measure | Initial | 10 frames / 0.167 s |
|---|---:|---:|
| Area-weighted RMS strain | 21.075% | 14.159% |
| Maximum shear angle | 71.06° | 63.80° |
| Nonshared triangle intersections | 2 | **388** |

A 30-frame probe reached 0.5 simulated seconds without numerical rollback, with 15.548% RMS strain and 1.22 m/s peak speed. It took about 94 wall-clock seconds on this host. This is a numerical survival test, **not contact success, physical plausibility or a topology certificate**. Lower strain does not compensate for interpenetration.

The close render does not establish a tight, physically plausible four-in-hand. Large residual deformation, discrete collision failure, missing self friction, coarse geometry and fixed neck patches remain material limitations. The UI labels this as a known contact failure. Pattern study remains available for the earlier authored visual approximation.

## Evidence and reproduction

`artifacts/cloth-0.4` contains build/test logs, six raw solver snapshots, seven PNG previews, the parameter probe and finite-mesh audit reports. `Tools/ClothRender.swift` also checks that the actual SceneKit material-coordinate buffer is byte-identical across each experiment's three snapshots. `Tools/audit_cloth.py` independently tests each coarse mid-surface at a single instant; it excludes shared-vertex pairs and makes no swept/thickness claim.

Run the commands in README. Do not interpret the passing mechanical checks as a passing knot audit. A next milestone should preserve an intersection-free seed at sufficient resolution, implement swept collision handling or another validated intersection barrier, validate thickness/friction under tightening, and then add explicit collision-aware grasp paths. The notation parser remains separate and cannot supply these missing geometric decisions.
