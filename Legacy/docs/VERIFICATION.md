# Verification — KnotStudio 0.3, 2026-10-09

The native arm64 app was rebuilt at **00:13:05 UTC** from changed source. Bundle version 0.3 (build 3), minimum macOS 13.0. Executable: 660,992 bytes; complete app file contents: 663,871 bytes. Old 0.1 and 0.2 ZIPs are preserved unchanged.

## Passed checks

- Core checks: 177,621 assertions, including all 85 FM sequences, route/depth constraints, actual mesh UV invariance under shape/layer changes, complete flat widths, flat/tied chart identity, closed consistently oriented edge/tip faces, and nondegenerate front triangles.
- Offscreen image/render checks: 3,711 checks. All eight EXIF orientations, non-square image aspect, unequal DPI, unreadable image handling, unknown reverse, actual SceneKit UV buffer values, and layer separation with nonzero angle/offset/repeat are covered.
- Independently predicted pixels in the asymmetric text/arrows/four-corner fixture matched 126/128 at baseline, 128/128 with changed repeat/offset, and 125/128 at 35 degrees; remaining differences fall within the test's letter-edge antialiasing allowance. The rendered reverse is neutral gray.
- Final full-mesh audit: **0 detected intersections across 251,896 triangles**, after 180,986 candidate comparisons. This includes both faces, long edges, tips and nonshared triangles in adjacent rows, plus coplanar checks. Shared-vertex pairs remain excluded.
- Twelve 1100×1100 previews plus four 640×480 test images were generated without app windows. Front/side/back, grid, face identity, routing, portrait, imported artwork, changed repeat/offset, angle and flat views were inspected from PNG files.

## Material limits remain significant

The explicit 145 cm flat chart retains the whole material width. The prior chart silently reduced the transverse material domain along with the spatial width; this revision instead maps all artwork through those compressed regions. That repairs the missing-domain problem, **not the physical narrowing**.

Across triangles touching the knot region (y = -3…3.5 cm), transverse stretch has median **0.602**, 5th percentile **0.330** and minimum **0.212**. Thus many regions compress severely relative to the assumed flat blank. Angular shear has median **7.75°**, 95th percentile **50.81°**, and maximum **70.19°**. The same updated surface with uncorrected authored frame guides had median shear 8.94° and 95th percentile 51.90°: the bounded correction is a modest improvement, not a shear solution. These are unweighted sampled-triangle diagnostics, not physical area-weighted strain estimates. The full numerical report is included.

The upper fold is smaller and the facade has smoother normals/a shallow groove, but front and rear folds still look stiff and stylized. This remains a geometric design study. No material-preserving cloth/contact solve, calibrated interlining, tension, friction, settling dynamics or exact topology guarantee is provided. The other three knot presets remain experimental.

## UI and packaging limits

No CUA, accessibility, browser, screen capture or native window interaction was used. Image decoding/rendering was tested offscreen. The new Flat camera, actual-view PNG export, camera reset behavior and file-error alerts compile, but their live controls/dialogs were not exercised. Gatekeeper acceptance is unverified. No software installation, license acceptance, publication or permissions/security changes occurred.

The package contains the built app, current source, scripts, fixture generator and fixtures, tests, README, geometry notes, final renders, raw exported mesh, full audit and test logs. `source-changes.json` records nine changed implementation/test/tool files plus seventeen additions relative to the 0.2 ZIP. Third-party reference PDFs/images are excluded.
