# Geometry and material model — 0.3

## One ribbon

The four-in-hand follows Li Ro Li Co T, with the full neck, initial crossing, back wrap, final front wrap, upper fold, tuck and both tips. Its visible front is the third move of the same strip. No separate facade, hidden replacement shell, deleted interior rows or procedural occluder is used.

The reference is [Denne, Joireman & Young, The Mathematics of Tie Knots, §3, Figures 5–6](https://arxiv.org/pdf/2005.13000), with practical sequences from [Ties.com](https://www.ties.com/how-to-tie-a-tie/four-in-hand) and [Tie-a-Tie](https://www.tie-a-tie.net/fourinhand/). These references were inspected in the earlier development work. Their PDFs and images are not redistributed. Route and depth checks do not establish exact topology.

## Shape changes

The four-in-hand uses bounded Hermite route interpolation. A partial frame correction reduces longitudinal skew where it can be applied without folding neighboring rows through one another; it fades to zero around the left wrap joins. Full orthogonal projection was tested and rejected because it caused intersections.

The upper fold and overall depth are compressed by one common smooth spatial map applied to every front/back surface point. Its vertical derivative is at least 0.38, its depth scale is positive, and x is unchanged. The continuous map is invertible; it introduces no separate covering geometry. The emitted triangles are still audited independently because a discretized mesh is not the continuous map itself. The rear Co section is narrower spatially, and a shallow continuous groove plus actual surface normals softens the facade/blade transition. This remains a stylized tapered wrap rather than settled cloth.

## Material domain

`TieBlank` specifies an assumed 145 cm blank with a piecewise-linear width profile. Reference route distance maps to this longitudinal domain once during construction. Shape, layer separation, camera, pattern and width-frame changes do not reset material coordinates. Each mesh row spans the **entire flat width**, even where the rendered cross-section is narrow. Both faces have identical material coordinates. The Flat view uses x = -transverse and y = length/2 - s, with no spatial compression or crown.

The current representation therefore preserves artwork identity and the complete domain. It does **not** preserve the intrinsic fabric metric: authored spatial narrowing still produces compression, and oblique/twisted rulings still produce shear. Those are exposed by the new mesh audit instead of being hidden by shrinking the UV width. A true solution requires material-preserving folds and contact mechanics; neither is claimed here.

On the flat front, s runs from narrow tip toward wide tip (down); -transverse points right. Image u=0.5 is the central material line and v increases down the image. This fixes the old horizontal mirroring. One affine transform handles angle, repeat width and longitudinal offset. ImageIO decodes pixels; an explicit EXIF transform handles orientations 1–8 without applying DPI aspect correction. Images larger than 4096 pixels on their longest edge are reduced. The unknown reverse of an imported swatch is neutral gray.

## Independent verification and remaining limits

`RibbonMesh` is shared by production rendering and file export. It contains front/back positions, normals, a raw material chart, correctly oriented long edge faces and closed tips. Core tests check mesh closure and real chart invariance; rendering tests inspect SceneKit's actual UV buffer and compare an asymmetric rendered swatch against independently calculated image samples. All eight EXIF transforms and unequal DPI are exercised.

`Tools/check_mesh.py` consumes the exported positions/indices/chart directly. It checks nonshared triangle pairs, including adjacent rows, both faces, edge caps and coplanar overlap. It measures the material-to-surface deformation gradient per front triangle, including principal stretch, transverse stretch and angular shear. Percentiles are unweighted over sampled triangles; they are diagnostics, not area-weighted physical strain estimates. The tiny tips can dominate extrema.

Triangle pairs sharing a vertex are excluded, so overlaps extending beyond shared adjacency are not ruled out. Finite mesh tests do not establish smooth-surface collision freedom, minimum clearance, a contact/tension solution or exact topology. The three other presets retain their experimental geometry and are not covered by the four-in-hand collision result.

No native UI automation was used for 0.3. Import decoding, texture mapping, rendering and error paths were tested offscreen. Actual dialogs, live orbit/export interaction, accessibility, and Gatekeeper acceptance remain unverified.
