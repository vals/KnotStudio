# 0.6 verification: staged loose wrap

The preceding relocation-only turn made no source changes. The working tree already contained the staged grasp controller, substep target sampling, collision-audit cancellation, and an exploratory probe. This milestone completes the app integration and independently verifies a fresh run of that implementation. The 0.5 ZIP and app checkpoint remain unchanged.

## Measured result

A flat, initially unstrained 32 cm tapered slice of the assumed tie blank (material s=30–62 cm) forms one helical wrap around a 35 mm radius support. It has 325 vertices and 512 triangles. Only the two end patches are prescribed; free vertices are mechanically solved. The script settles for 0.25 s, forms the wrap over 4 s, holds for 0.5 s, commands a 5 mm axial slide over 0.5 s, and holds for another 0.25 s. Quintic easing sets the grasp poses at each substep.

The fresh run accepted **330/330 frames**, reached **5.5 simulated seconds**, used **zero retries**, and took about 151 wall-clock seconds. Every frame used the existing safety checks and passed the 0.495 mm nonlocal clearance requirement for the configured 0.5 mm thickness. No threshold, refinement limit or work budget was relaxed.

| Measure | Result |
|---|---:|
| Initial RMS strain | < 1e-12 |
| Maximum RMS strain during entire run | 3.8464% |
| Held-wrap RMS strain, t=4.25–4.75 s | 0.54477–0.54479% |
| Final RMS strain | 0.63833% |
| Hold free vertices within 0.05 mm of support shell | 158 at all 31 frame samples, including both boundaries |
| Slide near-contact vertices | 148–158 |
| Final hold near-contact vertices | 151–153 |
| Prescribed axial grasp displacement | 5.000 mm |
| Mean free-vertex axial displacement during slide | 0.96512 mm |
| Final principal stretches | 0.97923–1.03525× |
| Held-wrap principal stretches | 0.99738–1.01717× |
| Minimum nonlocal separation over nine saved meshes | 3.31435 mm |
| Final nonlocal separation | 3.34013 mm |
| Independent nonshared intersections, nine saved meshes | 0 |

This demonstrates sustained *geometric near-contact with a solid support*, followed by partial cloth sliding. It is not a 5 mm rigid translation of the whole cloth, a self-contact knot, a tuck, or a general tying planner. Near-contact counts use free vertices and geometric distance, not contact forces. The mean hold displacement is less than 0.000001 mm. The saved near-support centerline covers about 412 degrees including the incoming portion; this angular range is not a contact-pressure measurement.

## Safety scope and measured limitation

Accepted physical motion remains linear between solver substeps. Existing swept triangle/triangle separation, collapse, vertex/capsule and floor checks remain enabled. Material-local and shared-vertex exclusions, double-precision arithmetic, finite work budgets, and missing self-friction remain documented in `COLLISION-ACCEPTANCE.md`.

The minimum free-vertex support-shell gap across all accepted frames is -1.37e-14 mm, numerical roundoff. **Triangle interiors against the solid support are outside that guard.** An additional independent projected-triangle/cylinder calculation finds nominal shell penetration of up to **0.09442 mm** at the nine saved instants; at the final state it is **0.09119 mm**. The mid-surfaces remain at least 0.15558 mm outside the support at those instants, but a 0.25 mm half-thickness extends through it. The audit uses the exact cylindrical section because every triangle stays inside its axial interval. This limitation is visible in the evidence and is not dismissed as vertex safety or a full-shell clearance guarantee.

There is no claim of mesh/timestep convergence, calibrated material properties, self-support after releasing the grasps, arbitrary knot tying, or successful four-in-hand tightening. The earlier high-strain four-in-hand still rejects its first dynamic frame and retains time zero; the existing safety regression confirms this.

## Tests and app

| Fresh check | Result |
|---|---:|
| Core / authored geometry / notation | 177,621 assertions |
| Fabric / UV grid / Face identity state transitions | 180 checks |
| Material mechanics and timestep sensitivity | 447 checks |
| Existing swept collision and acceptance suite | 152 checks |
| New staged grasp, cancellation, rollback and reset suite | 28 checks |
| Full staged sequence benchmark | 330 accepted frames with strain, contact and clearance assertions |
| Native saved-mesh and independent Python intersection audits | 9 saved instants each |
| Independent NumPy principal-stretch audit | agrees with native analytic values |
| Native macOS app build | 0.6, build 7 |

New cancellation tests interrupt broadphase/audit work at polls 1, 100 and 700, and use a one-shot cancellation after a real prediction. Interruption is explicit and never counts as a successful empty audit. The proposal rolls back geometry, velocity, time and grasp poses; resume succeeds. Reset clears attempt history, restores the flat state and replays the first frame identically. Unsafe scripted grasps that cross the support still fail. A separate rigid-motion test verifies 12 target samples per frame at the substep times.

The app has a Staged loose wrap case with phase/progress, automatic completion, and locked manual grasp controls during this scripted experiment. Reset reconstructs the original flat experiment. App interaction was not exercised. No UI automation, graphics access escalation, installation, license acceptance or permissions change was used. This revision's previews are CPU z-buffer renders of saved solver triangles, not screenshots or generated illustrations. The previous 3,711 rendering checks were not rerun because they require graphics access; the 0.5 results remain separately labeled.

## Reproduce

```sh
zsh Scripts/test-cloth-wrap.sh
python3 Tools/summarize_wrap.py
python3 Tools/render_wrap_cpu.py
```

`Tools/ClothWrapAudit.swift` audits the selected raw snapshots using native predicates and analytic principal stretches; `Tools/audit_cloth.py` is the independent finite-mesh intersection audit. `artifacts/cloth-0.6` contains full frame history, nine meshes, logs, audit results, and five CPU preview PNGs. The app needs no Python; these optional diagnostics require already installed NumPy/Pillow.
