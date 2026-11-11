# The model

The goal is to show what a knot looks like — which layer covers which, and how the pattern lands on each visible panel — at interactive rates and for any notation. The earlier cloth solver aimed at physical accuracy and could not get there. This model starts from the other end: the notation already says nearly everything about the knot’s structure, so build that structure directly and simulate only what is left.

## 1. What the notation fixes

Draped tie, mirror view: narrow (passive) end on the left, wide (active) end on the right. After the first crossing three strands leave the knot — the hanging narrow end, the left neck strand, the right neck strand — and divide the plane into regions L, R and C. Every move takes the wide end across one of those strands into the next region:

| From → to | Strand crossed |
| --- | --- |
| L ↔ R | the hanging narrow end |
| L ↔ C | the left neck strand |
| R ↔ C | the right neck strand |

A move written with `i` arrived pointing into the shirt, so it was laid across the **front**; one written with `o` passed **behind**. Directions alternate, so at every region the cloth goes from the front of the knot to the back or the reverse.

That is a ribbon wound around a flat core: straight passes (“chords”) across the front or back, joined by folds at the left edge, the right edge or over the top. `Layout` turns a sequence into exactly this: one fold point per move, a side per chord, and a stacking depth per chord.

## 2. Stacking order instead of collision

A new wrap is always laid over what is already there. So the k-th chord on the front lies in front of all earlier front chords, and likewise at the back. Depth is just a counter. The one exception is the tuck: it takes the depth of the last front band (the most recent front chord between L and R) and pushes that band, and anything laid over it, out by one.

Because the order is known, nothing has to be detected, separated or untangled, which is where the cloth solver spent its time and failed.

## 3. Flat folds keep the pattern true

A ribbon folded flat along a straight crease has its direction reflected in the crease. Conversely, for any two chord directions there is exactly one crease that joins them: the bisector. `WoundPath` uses this for every fold, so each chord is a flat, unstretched panel of the tie’s own fabric and the fold is a roll of small radius around the crease line (a helix, since the centreline meets the crease obliquely). Rows of the mesh are sheared to lie along the creases, so a row never straddles a fold.

The result is an isometric map from the flat tie to the knot: stripes turn exactly where the cloth turns and flip where it flips. Layer spacing sets how far a fold reaches across the stack, so later folds wrap around earlier ones. Cloth folds flat rather than round, so a fold’s section is an ellipse: it spans the full thickness of the layers it encloses but bulges past its crease by at most about two layer spacings.

Where the tie is wider than the knot allows, the surplus is rolled under at the edges (a flat middle, a tight roll, and a hem underneath), which is also what gives the edges their thickness. Texture stays at true scale on the visible part.

## 4. What is simulated

- **Wound length.** `progress` runs along the folded path. Adding a move extends the path and `progress` advances along it; removing one runs it back. Partial knots are simply shorter paths.
- **The free wide end.** A chain of particles 1 cm apart (position-based: fixed link lengths, bending stiffness, gravity, drag) hangs from wherever the wound part currently ends. It is kept on the outer side of the layer it leaves, so it hangs in front of the knot after a front move and behind it after a back one.
- **Leading.** While a move is in progress the free end is turned, link by link, toward its direction of travel, as if held; when the move ends it is released and eases into the simulated hang. A fold therefore swings the whole end around the edge of the knot like a page.
- **The tuck is threaded.** The last chord is not laid down from the top. The free end is posed as one strip: down the front of the band, up again in a bight, over into the top of the band, under it and out below. Shortening the front leg lifts the tip, feeds it under the band and draws the cloth through until no bight is left, at which point the strip coincides with the tucked knot. It is a path, not physics, but every centimetre of cloth is accounted for and the faces are right: the rising leg shows the tie's back.
- **Length is conserved.** Material is measured from the narrow tip; every centimetre wound into the knot shortens the free end. The narrow end is chosen so the finished knot leaves the wide end a little longer (can be set by hand).

Everything else — fold points, depths, tightness — eases toward its target, so changes are continuous.

## 5. Dressing

While a knot is being tied the layout is open and diagram-like, so each pass can be read. When the tuck goes through, the knot is drawn snug (`dress` goes from 0 to 1 over about a third of a second):

- the folds over the top drop toward the crossing, as far as the strands under them allow;
- the front band rises just enough for its upper edge to cover those folds, and the inner wraps are drawn up level with it and gathered so they hide behind it;
- the taper toward the bottom follows the knot’s bulk: every pass around a neck strand adds to the shoulder on that side, so a Windsor becomes a wide triangle and a four-in-hand stays a narrow, slightly lopsided trapezoid.

This is tension expressed as its outcome — where each fold ends up when pulled in as far as the cloth beneath lets it — not a force computation. Lowering the tightness control undoes it and opens the knot up again.

Dressing also draws the knot up to the neck and folds the collar down over the tie; while tying, the collar stands up so the centre moves stay visible.

## 6. Cloth

A cloth has a thickness relative to ordinary silk twill (fine silk 0.75, wool 1.45). It scales the layer spacing, the size of every fold, the growth of the knot per wrap and the rolled edges, so the same sequence ties a bigger knot in thicker cloth. The weave is a tiled normal map in cloth coordinates (it turns with the fabric), with roughness per cloth. The back face is mapped separately along the whole tie: shell cloth to a centre seam, lining at the tips, keeper loop and label.

## 7. Shaping

The folded stack is flat. A single smooth map of space is applied to every vertex: depth is scaled up toward the middle of the knot (a cushion) and width is tapered toward the bottom. It only rescales depth and width, so it cannot reorder layers. The blade below the knot is cupped and dimpled in its cross-section.

## 8. Cost

About 330 rows × 15 vertices, two faces: ~20k triangles, rebuilt every frame. One step (layout, path, chain, mesh) is ~0.5 ms on an M4 Pro; a 120 Hz frame is 8.3 ms. When nothing is moving the view stops redrawing.

## 9. What is checked

`Tests/Checks.swift` enumerates the 85 Fink–Mao knots from the rules and, for each at every step of tying, verifies on the built geometry that:

- each move crosses exactly the strand in the table above, on the side the notation gives;
- chords stack outward in order and the tuck lies directly under its band;
- every fold is a reflection (error < 0.02 in direction);
- the centreline is not stretched (worst 2.4 % between neighbouring rows, at the sharpest folds).

## 10. Where it is wrong on purpose

Creases are sharp, panels are flat, and cloth does not bunch. Fold points are placed by rule (see Dressing), so proportions are plausible rather than measured. Seen from above the dressed knot is an open cup rather than a closed bundle. The collar is a shape, not cloth, and there is no shirt.
