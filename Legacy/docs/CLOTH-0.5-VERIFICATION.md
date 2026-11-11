# 0.5 verification and remaining blocker

All checks used filesystem tools, deterministic executables and windowless SceneKit rendering. No native UI automation, browser, screen capture, accessibility calls, software installation, license acceptance or security-setting changes were used. Interactive clicking and Gatekeeper acceptance remain untested.

## Result

The controlled support strip and folded-strip impact advance with real mechanical motion. Accepted substeps are checked for the documented swept collision and thickness conditions. The four-in-hand seed is now refined and contact-prepared, but its dynamic frame is rejected and its last checked state is retained exactly. This is not successful knot tightening or an arbitrary-knot solver.

The Fabric display option and imported-swatch preservation remain intact. The unchanged v0.4 ZIP has SHA-256 `451c9f12dda4d6d8d45d1e5aa7ac5aabd43153c59acbe7392ed55f99e3a02cf7`; the 0.3.1 checkpoint also remains preserved. The v0.4 verification report is retained as `CLOTH-0.4-VERIFICATION.md`.

## Passing regressions

| Suite | Result |
|---|---:|
| Existing core / FM notation / authored geometry | 177,621 assertions |
| Repeated Fabric / UV grid / Face identity transitions | 180 checks |
| Image decoding, EXIF, DPI, sides, SceneKit buffers and rendered pixels | 3,711 checks |
| Material mechanics, gradients, bending, response, timestep and reset | 447 checks |
| Collision predicates, swept motion, clearance, acceptance, pause and rollback | 152 checks |

The rendering suite retains its existing tolerance: 379/384 independent pixel anchors match over the three asymmetric-image placements. The five tolerated differences are not new regressions. Actual material-coordinate buffers are byte-identical across every emitted snapshot in each cloth experiment.

Collision checks include clear-endpoint tunnelling, edge–face piercing with positive endpoint feature distances, coplanar overlap, triangle collapse, tangential sliding at thickness, crossing grasp targets, zero-velocity constraint-shaped proposals, rounded-support crossing, invalid initial geometry, inadequate clearance, work-budget exhaustion, exact state rollback and cancellation/resumption. Accepted motion is not a frozen display: the controlled cases advance time and move vertices substantially.

## Controlled strip and fold

| Measure | Support strip | Fold onto held cloth |
|---|---:|---:|
| Vertices / triangles | 205 / 320 | 365 / 576 |
| Simulated duration | 1.5 s | 0.5 s |
| Final area-weighted RMS strain | 0.292% | 1.093% |
| Final maximum shear | 0.91° | 1.73° |
| Final peak speed | 0.0180 m/s | 1.6496 m/s |
| Final nonshared triangle intersections | 0 | 0 |

The fold test performs 64,716 contact corrections over 30 accepted frames. Every accepted frame has zero nonshared triangle intersections in the native audit. Its final minimum nonlocal separation is 2.8083 mm; the guard requires at least 0.495 mm for the 0.5 mm configured thickness. It first contacts the held layer and then unfolds/falls; the final larger separation is not evidence of sustained resting contact. The saved 0.25 s preview shows the intermediate fold. Motion is not real time; this benchmark took about a minute on the host during testing.

The independent Python finite-mesh audit reports zero intersecting nonshared pairs for the support strip at 1.5 s, the fold at 0.25 and 0.5 s, and both the initial and retained knot snapshots. This audit checks only those saved instants, not swept motion or shell thickness.

## Timestep sensitivity

At 0.5 simulated seconds, mean vertex differences are:

- 3 to 6 base substeps/frame: **3.520 mm**, missing the old 3 mm target.
- Default 6 to 12: **0.807 mm**, passing the 3 mm regression limit.
- 12 to 24: **0.803 mm**.

The regression now checks the default configuration against halved nominal timestep. The coarser failed comparison remains recorded in `timestep-probe.txt`; it is not hidden by widening the tolerance. Adaptive retries and finite-iteration constraints affect these results. This is a sensitivity check, not proof of convergence, timestep independence or calibrated cloth behavior.

## Four-in-hand status

The original 1,100-vertex seed has two intersections. Refining two longitudinal intervals yields 1,110 vertices / 1,768 triangles and zero intersections, but still 79 thickness violations. A separately labeled contact-only preparation opens those gaps without changing the rest chart or advancing time. The checked seed has minimum nonlocal separation **0.499147 mm**, above the 0.495 mm threshold, and zero nonshared triangle intersections.

The prepared seed still has **21.105% RMS strain**, 71.06° maximum shear, and poorly conditioned narrow elements. Its dynamic proposal fails swept checks or the speed bound even after three refinements. The final tested rejection reported 37.8 m/s proposed peak speed. Smaller material projection limits also fail; their rejected trials remain in the evidence. No rejected position, velocity or simulated time is published. The retained snapshot has time 0 and zero speed.

Visually, the retained object resembles the earlier authored knot, but that appearance is not a solved or physically plausible tight-knot result. It remains a high-strain initial condition. The next useful knot work is a well-conditioned, low-strain loose mesh and explicit grasp paths, followed by validated tightening.

## Scope

See `COLLISION-ACCEPTANCE.md` for the trace and algorithm. Accepted physical motion is defined as linear between substep states. Internal optimization iterates can be invalid; they are never shown as accepted states. Triangle pairs sharing a vertex and triangle interiors against solid supports remain outside the swept guard. Material-local pairs have a smaller nonintersection guard instead of full thickness. Self-contact friction is absent. Double-precision conservative bounds with finite budgets are not a formal proof or topology certificate.

`artifacts/cloth-0.5` contains logs, raw snapshots, native and independent audits, parameter probes and windowless PNGs. Sources and evidence are included in the deliverable. The app uses the same assumed flat material dimensions and image pipeline; it does not infer rest shape from texture UVs or the compressed authored ribbon.
