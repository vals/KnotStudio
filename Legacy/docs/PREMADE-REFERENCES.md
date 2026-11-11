# Four-in-hand photographic references — 0.8

The two requested photographs were visually inspected before remodeling:

- [Gentleman’s Gazette, How to Tie a Four in Hand Knot](https://www.gentlemansgazette.com/how-to-tie-four-in-hand-knot/): the pale-yellow medallion tie in the oblique hero photograph. Used for front-wrap convexity, a concealed tuck, rounded dimple folds, and motif scale through the curved surface.
- [Ties.com, How to Tie a Necktie](https://www.ties.com/how-to-tie-a-tie): the photographic “A Visual Comparison of Necktie Knots” image, four-in-hand second in the top row. Used for the upward-right crown slope, unequal shoulders, modest lower-mouth width, and gradual blade expansion. The page says the comparison ties share material, thickness and width. The nearby line illustration was not used as a shape reference.

Reference downloads remain outside the project, in `/tmp/knotstudio-photo-references`. No photograph or crop is an app resource or release asset. This is a visual interpretation, not a dimensionally calibrated reconstruction of either tie.

## Authored construction

`PremadeFourInHand.swift` is the appearance model. `FourInHand.swift`, the legacy ribbon route, and the Cloth Lab solver remain preserved. The preset has a single leaning wrap, an inset crown turnover, a folded blade, neck entries and a passive tail. The wrap covers the upper blade; there is no protruding tuck panel. The narrow exit opens into unequal rounded folds around a recessed dimple, with gathering concentrated close below the knot. Neck entries extend beyond the accepted front/oblique frames.

The base wrap has a generalized-cone development. Small belly corrections, inward-curling crown and mouth edges, and localized lower compression soften its silhouette; their material-scale error is measured separately. The blade and gathered neck entries integrate fiber direction over material arc length. A folded cross-section retains its material width rather than scaling a full texture width to the projected silhouette. Wrap and blade have separate material positions/orientations, so the front-view image is not projected through both. Pattern phase need not match across their occlusion.

The inset crown approximates hidden assembly and does not have an isometric chart. This is a panel assembly, not a globally continuous flat blank, a topology certificate, an arbitrary-sequence renderer, or a physically solved knot. The greatest remaining visual simplifications are the regular wrap, idealized neck bands, and limited small wrinkles and contact shadows.

Notation identifies the available preset. The other named knots remain legacy experimental routes. Solver research is paused; the retained experiments are still available.
