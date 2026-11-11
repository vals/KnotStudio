# 0.7 verification: triangle-interior support contact

## Result

The same staged-wrap benchmark completes **330/330 accepted frames**, **5.5 simulated seconds**, with **zero retries**. It still forms a wrap, holds contact and makes a measurable partial axial slide. It does not obtain clearance by freezing, changing the grasp sequence, changing the rest metric, or loosening safety thresholds.

The new response and guard cover finite triangle interiors against capsule supports. The closest-point routine includes face/axis-endpoint, edge/axis and axis-piercing cases. Barycentric inverse-mass corrections distribute contact motion while respecting pins. Swept acceptance uses capsule support planes over the moving triangle's endpoint hull, with bounded interval subdivision and a conservative distance/speed bound where needed. Sampled points alone never accept an interval.

The response targets **2.5 micrometres outside nominal half-thickness**, leaving a finite-iteration margin. The configured 0.5 mm thickness, 99% acceptance tolerance, three refinement attempts, 200,000-evaluation frame budget and 64-step per-pair limit are unchanged. This outward margin is stricter response positioning. No material, damping, resolution, grasp timing or physical benchmark settings were changed.

## Measured benchmark

| Measure | 0.7 result |
|---|---:|
| Simulated time / wall time | 5.5 s / about 162 s |
| Accepted frames / retries | 330 / 0 |
| Worst nominal triangle-shell gap across all 331 frame states | **+2.410109 micrometres** |
| Worst independent shell gap across nine saved meshes | +2.496097 micrometres |
| Initial area-weighted RMS strain | below 1e-12 |
| Maximum RMS strain over entire sequence | 3.84563% |
| Held-wrap RMS strain | 0.53427–0.53445% |
| Final RMS strain | 0.63225% |
| Held near-contact faces | 246–246 |
| Slide near-contact faces | 233–247 |
| Final-hold near-contact faces | 242–246 |
| Prescribed grasp translation / mean free-cloth slide | 5.000 / 0.969998 mm |
| Final principal stretches | 0.978923–1.035533× |
| Minimum nonlocal separation in nine saved meshes | 3.314346 mm |
| Independent nonshared triangle intersections | 0 in all nine saved meshes |

The 0.6 shell penetration of up to 0.09442 mm at saved states is eliminated at the measured frame states. The native all-triangle distance runs on every frame; the independent Python projected-triangle/cylinder calculation confirms the saved instants. Every triangle remains within the cylindrical axis interval, so that independent calculation covers its entire interior. The midpoint shell gap remains positive at every recorded frame; the **swept** guard still has its documented 99% half-thickness tolerance, rather than an exact-arithmetic zero-penetration claim at every instant.

Near-contact means a triangle's closest point is within 0.05 mm of the nominal support shell, with at least one free vertex. This is sustained geometric face contact, not a measured contact force. Vertex-only near-contact counts are now zero: the flat facets touch while their vertices sit farther outside the curved support. Reusing vertex counts would incorrectly label this response a loss of contact. The benchmark requires at least 100 near-contact faces through the hold and slide and measurable free-cloth translation. Both end grasps remain held; self-support after release is not established.

## Regression evidence

- **19 new finite-face tests:** clear vertices with penetrating interior; an interior inside half-thickness; axis piercing; sphere/face distance; clear endpoints and clear vertex paths with a crossing face; tangential accepted motion; a recorded near-tangential strip impact; work-budget exhaustion; cancellation; rollback; and real face-contact response.
- **28 staged grasp/cancellation/reset checks** pass, including per-substep targets, exact rollback of pins, one-shot cancellation, resume and deterministic reset.
- **447 mechanics checks**, **152 existing safety checks**, **177,621 core assertions**, and **180 display-state checks** pass.
- The controlled support strip advances 1.5 s, with 0.286% final RMS strain. Default 6 vs 12 substeps differ by 0.679 mm at 0.5 s, within the existing 3 mm regression bound. This is sensitivity evidence, not a convergence proof.
- The fold still advances through contact. The high-strain four-in-hand still rejects its first dynamic frame and retains its checked state at time zero.

Development logs named `strip-*-probe.txt` retain earlier rejected certification attempts. The final interval certificates plus outward response margin restore the support strip's full motion; current passing results are in `support-checks.txt`, `mechanics-checks.txt`, `safety-checks.txt` and `wrap-probe.txt`. The main safety thresholds were never relaxed to get those passes.

## Build and packaging

The current app builds as **0.7, build 8**. `Scripts/build.sh` signs in a private temporary folder, writes **`build/KnotStudio.app.zip`** inside the project, extracts it afresh, and strictly verifies the extracted app. Its executable matches the expanded local build. Release packaging uses the clean archive, excluding resource-fork/Finder metadata, and verifies the final archive and every extracted app signature.

**Remaining filesystem limitation:** File Provider repeatedly adds `com.apple.FinderInfo` to expanded `.app` folders under Documents, even after scoped removal from a generated output. This can make strict verification of `build/KnotStudio.app` fail again while executable verification passes. The canonical build ZIP and clean-extraction signatures pass. Unrelated user metadata, File Provider settings and permissions are untouched; no persistent-clean claim is made for the expanded folder.

The 0.6 app checkpoint and ZIP remain preserved, along with older deliverables. App UI and Gatekeeper behavior were not exercised. There were no computer-use calls, graphics access requests, installs, license acceptance or permissions changes. Previews are CPU z-buffer renders of exact saved solver mid-surfaces.

## Remaining mechanics limits

The fixed support shape is a capsule and the floor is planar. Shared-vertex triangle pairs remain excluded; self-contact friction is absent. Accepted motion is linear between substeps. The solver remains finite-resolution, uncalibrated and numerically bounded, without formal interval arithmetic, mesh convergence, general tying plans or demonstrated knot tightening. The slide remains partial rather than a 5 mm rigid motion of the whole cloth.

## Reproduce

```sh
zsh Scripts/test-cloth-support.sh
zsh Scripts/test-cloth-wrap.sh
python3 Tools/summarize_wrap.py
python3 Tools/render_wrap_cpu.py
zsh Scripts/build.sh
```

`Tools/ClothWrapAudit.swift` provides native snapshot distances and principal stretches. `Tools/audit_cloth.py` checks independent finite-mesh intersections. `artifacts/cloth-0.7` contains frame history, nine raw meshes, audit data, test logs, build verification, and five CPU render PNGs. Python diagnostics need already installed NumPy/Pillow; the app does not.
