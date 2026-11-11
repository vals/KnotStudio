# Collision acceptance — 0.7 design

The purpose is to publish only checked mechanical steps and retain the last checked state after failure. This is a bounded prototype, not a certified arbitrary-knot solver. The v0.4 ZIP and its evidence remain unchanged.

## Diagnosis

The v0.4 solver used a different, coarser mesh than the previously audited rendering mesh. That 1,100-vertex mesh starts with two nonshared triangle intersections. The first motion prediction leaves those two unchanged; the first membrane sweep produces 470, bending produces 954, and discrete self-contact only reduces that to 878. Of those 878 pairs, 382 are more than 0.5 mm apart at the endpoint vertex–face / edge–edge features. An edge can already pierce a face while all these endpoint distances are positive. A proximity-only response cannot recover such a crossing reliably. The broad one-ring exclusion also hides relevant contacts.

`trace-v04.txt` was captured before changing the contact implementation. `Tools/ClothTrace.swift` is a diagnostic observer for the current implementation, with acceptance disabled only inside that developer tool; it never changes the production UI's guard.

## Seed preparation

Two added longitudinal rows (1,110 vertices total) remove the initial geometric crossings without moving the retained samples or changing their material coordinates. This is still insufficient: the refined seed has 79 nonlocal pairs below the 0.5 mm thickness requirement, with minimum separation 0.090 mm.

The separate, bounded **contact-only initial-condition preparation** opens those gaps. It solves no membrane, bending or gravity dynamics and advances no time. Its proposed corrections are backtracked against a nonintersection guard; it preserves the physical rest chart. One pass in the verified case gives minimum nonlocal separation 0.499147 mm, above the 0.495 mm acceptance threshold (1% thickness tolerance), with zero nonshared triangle intersections. A failed preparation is not silently accepted: the actual solver mesh is checked again before stepping.

## Response and acceptance are separate

- The existing XPBD membrane/dihedral constraints, physical rest metric, mass and gravity remain. A local rest-edge trust region under-relaxes large nonlinear material corrections; position and multiplier updates receive the same factor. This is a convergence safeguard, not smoothing, shape attraction or calibrated constitutive behavior.
- Discrete VF/EE response uses the previous side and material-distance exclusions. Old-side frictionless contact planes restrict closing displacement near existing contacts. These responses alone do not certify a result.
- The acceptance check considers the **net old-to-proposed motion**, including integration, grasp targets, material projections and contact corrections. The displayed physical path is defined as linear between accepted substep states. Internal optimization iterates are not published and are not claimed to be intersection-free.
- Swept triangle AABBs are generated with sweep-and-prune, without silently dropping oversized boxes. A fixed separating plane between swept convex hulls provides a sufficient certificate when available. Otherwise conservative advancement uses a Lipschitz bound on triangle distance after removing common translation. The distance includes edge–face penetration and coplanar overlap, in addition to closest VF/EE features.
- Triangle-area bounds reject collapse during a path. Point–capsule motion is checked using closest distance between the vertex path and capsule axis; floor motion is linear. The 0.7 guard also checks finite triangle–capsule distance, including faces, edges, caps and axis/face piercing. Geometry is checked for finite values before entering these routines.
- Nonlocal material pairs require 99% of configured shell separation throughout the checked path. Locally adjacent material pairs still get a 0.1 micrometre nonintersection guard. Pairs sharing a topological vertex remain excluded from the triangle-pair check. Triangle interiors against capsule supports are included with the same 99% half-thickness acceptance tolerance as the existing vertex guard. The computations use double precision and bounded numerical iterations, not interval arithmetic or a formal proof.

## Finite-face support response and sweep

Closest-point search covers capsule-axis endpoints against the face, triangle edges against the axis, and axis piercing the face. The barycentric contact correction distributes displacement by inverse mass, respects pinned vertices, and limits tangential correction using the same external-friction coefficient. The response targets half-thickness plus 1% (a 2.5 micrometre outward margin for the configured 0.5 mm cloth). This is stricter response positioning, not a relaxed acceptance threshold. It supplies room for finite-iteration changes from adjacent triangles.

For a proposed moving triangle, a fixed separating plane against the capsule's support function can certify its six-point swept convex hull. Otherwise unresolved time intervals are bisected. An interval is accepted only when a fixed plane separates both endpoint triangles or a midpoint distance exceeds the maximum vertex-speed bound times half the interval. Point samples alone never certify an interval. At most 64 intervals are examined per triangle/support pair, charged to the existing 200,000-evaluation frame budget. Unresolved intervals, penetration, cancellation or exhausted work reject the proposal. The initial and final distance checks use the unchanged 99% half-thickness tolerance, as do every interval certificate.

A speed-only advancement prototype stopped the support-strip impact despite clear endpoints. The bounded interval certificates and outward response margin let it continue without changing the guard distance, substep-refinement limit or work budget. Both crossing regressions and near-tangential accepted motion are tested.

## Bounded failure behavior

A frame starts by checking the actual solver seed for intersections, material-aware clearance and degeneracy. An initially invalid mesh gets a visible error and no time advancement.

If a proposed frame fails, the solver retries from its original position, velocity and time with doubled substeps, up to three refinements by default. A 200,000-evaluation budget and 64-iteration per-pair limit bound conservative checks; exhaustion is failure, never success. A failed frame restores position, velocity, time and contact diagnostics exactly. The UI shows the reason and the retained state. It does not increment the simulation clock.

Pause uses a thread-safe cancellation token checked during constraint iterations, collision audits, broadphase and swept support checks. It discards unfinished frame work without making the error permanent, so Run can resume. Reset cancels prior work and uses a generation token to prevent stale snapshots from being published. Held markers show the retained positions after a rejected grasp.

## Scope and next work

The controlled support strip and folded-strip impact benchmark exercise real motion and contact. The prepared four-in-hand still cannot take an accepted dynamic step: its high initial distortion and narrow, poorly conditioned elements produce unresolved collision motion or excessive speed. Smaller material-projection limits did not resolve it, and none of those rejected trials are shown as a successful solve.

The staged wrap now provides a low-strain flat initial mesh and explicit grasp paths. Shared-vertex contact, self-contact friction, arbitrary solids, convergence and general tying remain unvalidated. FM notation remains separate from the solver and does not determine grasp pose, slack or the specific tuck loop. See `CLOTH.md` for the XPBD/strain-model sources and material assumptions.
