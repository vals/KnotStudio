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

The result is an isometric map from the flat tie to the knot: stripes turn exactly where the cloth turns and flip where it flips. Layer spacing sets the roll radius, so later folds wrap around earlier ones.

Where the tie is wider than the knot allows, the surplus is rolled under at the edges (a flat middle, a tight roll, and a hem underneath), which is also what gives the edges their thickness. Texture stays at true scale on the visible part.

## 4. What is simulated

- **Wound length.** `progress` runs along the folded path. Adding a move extends the path and `progress` advances along it; removing one runs it back. Partial knots are simply shorter paths.
- **The free wide end.** A chain of particles 1 cm apart (position-based: fixed link lengths, bending stiffness, gravity, drag) hangs from wherever the wound part currently ends. It is kept on the outer side of the layer it leaves, so it hangs in front of the knot after a front move and behind it after a back one.
- **Leading.** While a move is in progress the free end is turned, link by link, toward its direction of travel, as if held; when the move ends it is released and eases into the simulated hang. A fold therefore swings the whole end around the edge of the knot like a page.
- **Length is conserved.** Material is measured from the narrow tip; every centimetre wound into the knot shortens the free end. The narrow end is chosen so the finished knot leaves the wide end a little longer (can be set by hand).

Everything else — fold points, depths, tightness — eases toward its target, so changes are continuous.

## 5. Shaping

The folded stack is flat. A single smooth map of space is applied to every vertex: depth is scaled up toward the middle of the knot (a cushion) and width is tapered toward the bottom. It only rescales depth and width, so it cannot reorder layers. The blade below the knot is cupped and dimpled in its cross-section.

## 6. Cost

About 300 rows × 15 vertices, two faces: ~18k triangles, rebuilt every frame. One step (layout, path, chain, mesh) is ~0.4 ms on an M4 Pro; a 120 Hz frame is 8.3 ms. When nothing is moving the view stops redrawing.

## 7. What is checked

`Tests/Checks.swift` enumerates the 85 Fink–Mao knots from the rules and, for each at every step of tying, verifies on the built geometry that:

- each move crosses exactly the strand in the table above, on the side the notation gives;
- chords stack outward in order and the tuck lies directly under its band;
- every fold is a reflection (error < 0.02 in direction);
- the centreline is not stretched (worst 0.6 %).

## 8. Where it is wrong on purpose

Creases are sharp, panels are flat, and cloth does not bunch. Fold points are placed by rule, not by tension, so proportions are plausible rather than measured. The tuck passes through the band instead of being threaded tip-first. Good next steps: tension-based placement of the fold points, a collar, per-fabric thickness, and the extended tuck notation for knots like the Eldredge.
