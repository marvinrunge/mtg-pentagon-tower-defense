# Nature Texture Prompts

Bark and leaf textures for the 20 procedural trees and bushes (`docs/NATURE_ASSETS.md`,
3b and 3c), written to paste into Gemini by hand (Nano Banana Pro in the Gemini app or AI
Studio). Every prompt below is self-contained.

Hand-written, unlike `docs/NATURE_PROMPTS.md`: the manifest does not describe textures yet
(revision 2, task 1). When it does, these move into it.

## How to generate and save

- **Square images.** Ask for the highest resolution offered; 2048 px is ideal, 1024 px works.
- **Save to `assets/nature/_concepts/textures/`.** That folder is behind the concept
  `.gdignore`, so Godot won't import the raw images. Use exactly the file name given above
  each prompt.
- **Generate 2-3 per prompt** and keep the best. Name extras `..._2.png` and so on.

**Check a bark image before keeping it.** It must tile:

1. Open it in any viewer and imagine it repeated side by side and top to bottom. No visible
   seam, no light falloff toward one edge, no single standout knot that would repeat like a
   stamp.
2. If it fails, regenerate. Seam repair is possible but slower than a new roll.

**Check a leaf sheet before keeping it.** It is cut out against white exactly like the grass
(`tools/alpha_key.gd`), so the grass rules apply:

1. The background is pure white: no grey wash, no shadow under the clusters.
2. Four separate clusters, none touching each other or crossing the middle lines.
3. No pale or white-ish leaves or tips. They would fringe; regenerate instead.
4. Leaves are bold and broad, not hair-thin. Conifers are drawn as solid needle clumps for that reason.

## Bark (11 swatches)

Each species points to one bark. Sharing a bark costs nothing visually, because trunks are
also shaped and tinted per species in Blender.

| Bark file | Used by |
|---|---|
| `bark_birch.png` | silver birch |
| `bark_olive.png` | olive sunleaf |
| `bark_oak.png` | great sun oak, broad oak |
| `bark_conifer.png` | windswept pine, tall fir |
| `bark_mangrove.png` | mangrove |
| `bark_willow.png` | weeping willow |
| `bark_cypress.png` | swamp cypress |
| `bark_dragonblood.png` | dragonblood tree |
| `bark_fireheart.png` | fireheart tree |
| `bark_young.png` | sapling, and the branches of every leafy bush |
| `bark_thorn.png` | thorn bramble, ember thornbush |

### `bark_birch.png`

```
A seamless tileable texture of silver birch bark, seen straight on and filling the whole square image edge to edge. Chalky white bark with dark grey-black horizontal lenticel marks and a few thin peeling curls, faint warm cream undertones. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no moss, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_olive.png`

```
A seamless tileable texture of old olive tree bark, seen straight on and filling the whole square image edge to edge. Silver-grey bark that is deeply twisted and furrowed, with swirling knotty ridges and warm brown showing in the cracks. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_oak.png`

```
A seamless tileable texture of mature oak bark, seen straight on and filling the whole square image edge to edge. Thick grey-brown bark broken into deep vertical furrows and blocky ridges, a little green-grey lichen in a few cracks. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_conifer.png`

```
A seamless tileable texture of pine tree bark, seen straight on and filling the whole square image edge to edge. Reddish-brown and dark grey bark in thick overlapping scaly plates separated by dark fissures. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no resin drips, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_mangrove.png`

```
A seamless tileable texture of mangrove bark, seen straight on and filling the whole square image edge to edge. Smooth-ish grey-brown bark with fine vertical fissures, pale salt staining and a few tiny barnacle specks, cool blue-grey undertones. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no water, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_willow.png`

```
A seamless tileable texture of old swamp willow bark, seen straight on and filling the whole square image edge to edge. Dark charcoal-brown bark with deep interlacing diamond-shaped ridges, damp and slightly mossy olive staining in the furrows, faint deep violet undertone. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_cypress.png`

```
A seamless tileable texture of bald cypress bark, seen straight on and filling the whole square image edge to edge. Fibrous stringy bark in long vertical strips, grey with dusty reddish-brown showing underneath, damp dark staining. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_dragonblood.png`

```
A seamless tileable texture of dragon blood tree bark, seen straight on and filling the whole square image edge to edge. Pale grey-brown bark, fairly smooth with fine wrinkles and horizontal ring marks, with thin dark crimson resin streaks running down in a few places. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no trunk edges, no background, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_fireheart.png`

```
A seamless tileable texture of charred magical tree bark, seen straight on and filling the whole square image edge to edge. Deep black and charcoal bark broken into cracked blocky plates like burnt wood, with thin molten orange veins glowing in the deepest cracks - the glow stays inside the cracks. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights, no smoke, no glow haze. Orthographic flat view with no perspective, no trunk edges, no background, no text, no watermark. The bark grain runs vertically from top to bottom.
```

### `bark_young.png`

```
A seamless tileable texture of young tree and shrub bark, seen straight on and filling the whole square image edge to edge. Thin smooth grey-brown bark with fine horizontal lenticel dots and a slight green tint, a few tiny bud scars. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no edges, no background, no text, no watermark. The grain runs vertically from top to bottom.
```

### `bark_thorn.png`

```
A seamless tileable texture of the skin of thorny bramble stems, seen straight on and filling the whole square image edge to edge. Very dark brown-black woody surface with faint fine vertical fibres, small sharp thorn bases and scars scattered evenly, a slight dark red undertone. Semi-realistic, high-quality game texture, believable detail and soft colour variation. The image must tile seamlessly on all four edges: no visible seams, no vignette, no light falloff, no single large standout feature that would repeat noticeably. Flat even diffuse lighting from the front, no directional shadows, no highlights. Orthographic flat view with no perspective, no edges, no background, no text, no watermark. The grain runs vertically from top to bottom.
```

---

## Leaf sheets (20, plus 1 moss)

Each is a 2x2 sheet of four leaf clusters (a short twig carrying many leaves), which become
the canopy cards. Every prompt ends with the same constraint paragraph.

### White - Plains

#### `leaves_silver-birch.png`

```
A 2x2 grid of four separate silver birch leaf clusters for a game foliage texture sheet. Each cluster is a short thin twig carrying fifteen to twenty small triangular toothed leaves in pale golden-green and warm green, a few leaves turning gold.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_olive-sunleaf.png`

```
A 2x2 grid of four separate olive branch leaf clusters for a game foliage texture sheet. Each cluster is a short twig densely set with narrow lance-shaped leaves, dusty silvery sage green on top and grey-green underneath, with two or three small golden olives on some twigs.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_great-sun-oak.png`

```
A 2x2 grid of four separate golden oak leaf clusters for a game foliage texture sheet. Each cluster is a short twig with ten to fourteen lobed oak leaves in rich warm gold, amber and a little late-summer green, a couple of acorns on some twigs.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_boxwood-hedge.png`

```
A 2x2 grid of four separate boxwood sprigs for a game foliage texture sheet. Each sprig is a dense rounded bunch of many tiny glossy oval leaves in deep sage green and fresh green, packed tightly like a trimmed hedge surface.

Style: semi-realistic natural leaves with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_sunbloom-shrub.png`

```
A 2x2 grid of four separate flowering shrub sprigs for a game foliage texture sheet. Each sprig is a short twig with sage-green oval leaves and three to five small saturated golden five-petal flowers with amber centres. No white or cream petals anywhere.

Style: semi-realistic natural leaves and flowers with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves and petals broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

### Blue - Islands

#### `leaves_windswept-pine.png`

```
A 2x2 grid of four separate pine branch sprays for a game foliage texture sheet. Each spray is a short twig with dense dark blue-green needle bundles drawn as solid, thick needle clumps rather than individual hairs, all needles sweeping slightly to one side as if shaped by sea wind.

Style: semi-realistic natural foliage with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Bold thick clumps clearly readable in silhouette, not hundreds of fine hairs, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_mangrove.png`

```
A 2x2 grid of four separate mangrove leaf clusters for a game foliage texture sheet. Each cluster is a short twig with eight to twelve thick glossy elliptical leaves in deep teal-green, slightly paler blue-green undersides showing on a few leaves.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_sea-holly-bush.png`

```
A 2x2 grid of four separate sea holly sprigs for a game foliage texture sheet. Each sprig has stiff spiny steel-blue leaves and two or three round thistle-like flower heads in deep metallic blue with a spiky collar of bracts.

Style: semi-realistic natural plant with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Shapes bold and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale silvery or frosted tips, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_tide-hydrangea.png`

```
A 2x2 grid of four separate hydrangea sprigs for a game foliage texture sheet. Each sprig has three or four broad serrated dark-teal leaves crowned by one large round cluster of many small four-petal flowers in deep saturated blue with a hint of violet.

Style: semi-realistic natural leaves and flowers with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves and petals broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out petals, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

### Black - Swamp

#### `leaves_weeping-willow.png`

```
A 2x2 grid of four separate hanging willow strands for a game foliage texture sheet. Each strand is a long thin drooping twig hanging straight down, lined along its whole length with narrow lance-shaped leaves in dark olive and murky green, a few leaves with a deep violet tint, each strand about four times taller than wide.

Style: semi-realistic natural leaves with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate strands, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated dark colour, no pale washed-out leaves, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_swamp-cypress.png`

```
A 2x2 grid of four separate cypress branchlets for a game foliage texture sheet. Each branchlet is a short twig with flat feathery sprays of soft needles arranged like a fern frond, in dark green with rusty brown at the tips, drawn as solid feathery shapes rather than individual hairs.

Style: semi-realistic natural foliage with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Bold shapes clearly readable in silhouette, not hundreds of fine hairs, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `moss_hanging.png` (for the swamp cypress and willow)

```
A 2x2 grid of four separate strands of hanging Spanish moss for a game foliage texture sheet. Each strand is a long tangled curtain of moss hanging straight down from a short horizontal twig, in dark grey-green and olive grey, drawn as thick clumped tangles rather than fine hair, each strand about three times taller than wide.

Style: semi-realistic natural plant with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate strands, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting. Bold clumps clearly readable in silhouette, crisp edges, sharp focus throughout, no blur, no glow. Dark saturated colour, no pale silvery grey, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_thorn-bramble.png`

```
A 2x2 grid of four separate bramble sprigs for a game foliage texture sheet. Each sprig is a short curving black thorny stem with a few serrated dark olive leaves and a small cluster of glossy violet-black berries.

Style: semi-realistic natural plant with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Shapes bold and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated dark colour, no pale washed-out leaves, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

### Red - Mountains

#### `leaves_dragonblood-tree.png`

```
A 2x2 grid of four separate dragon blood tree leaf rosettes for a game foliage texture sheet. Each rosette is a dense upward-pointing tuft of stiff sword-shaped leaves at the end of a short branch tip, dark green with a dusty grey-red cast and darker crimson bases.

Style: semi-realistic natural leaves with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_fireheart-tree.png`

```
A 2x2 grid of four separate fireheart leaf clusters for a game foliage texture sheet. Each cluster is a short charred black twig with ten to fourteen broad maple-like leaves in flame orange, crimson and deep red, the brightest leaves near the twig tip. The colour is in the leaves themselves - no glow around them.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow, no sparks, no smoke. Strongly saturated colour, no pale yellow or washed-out leaves, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_ember-thornbush.png`

```
A 2x2 grid of four separate ember thornbush sprigs for a game foliage texture sheet. Each sprig is a short black thorny twig carrying small oval leaves in crimson, ember orange and dark rust, like a bush caught mid-burn but without any fire or glow.

Style: semi-realistic natural leaves with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow, no fire, no smoke. Strongly saturated colour, no pale washed-out leaves, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

### Green - Forest

#### `leaves_broad-oak.png`

```
A 2x2 grid of four separate oak leaf clusters for a game foliage texture sheet. Each cluster is a short twig with ten to fourteen lobed oak leaves in deep and mid forest greens, a few darker shaded leaves behind.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no yellow-green, no pale sunlit tips, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_tall-fir.png`

```
A 2x2 grid of four separate fir branch sprays for a game foliage texture sheet. Each spray is a flat drooping branch tip with short flat needles arranged in neat rows on both sides of each twig, dark blue-green on top, drawn as solid needle rows rather than individual hairs.

Style: semi-realistic natural foliage with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Bold shapes clearly readable in silhouette, not hundreds of fine hairs, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_round-bush.png`

```
A 2x2 grid of four separate leafy shrub sprigs for a game foliage texture sheet. Each sprig is a short twig densely covered in broad rounded leaves in deep green and fresh mid green, overlapping into a full rounded clump.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no yellow-green, no pale tips, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_berry-bush.png`

```
A 2x2 grid of four separate berry bush sprigs for a game foliage texture sheet. Each sprig is a short twig with oval serrated deep green leaves and one or two hanging clusters of glossy bright red berries.

Style: semi-realistic natural leaves and berries with believable shape, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves and berries clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no pale washed-out leaves, no white highlights on the berries, no near-white values anywhere. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```

#### `leaves_sapling.png` (optional - the sapling can reuse `leaves_broad-oak.png`)

```
A 2x2 grid of four separate young leaf clusters for a game foliage texture sheet. Each cluster is a thin fresh twig with six to nine soft oval young leaves in fresh saturated green with slightly darker veins.

Style: semi-realistic natural leaves with believable shape, veins, real colour variation and soft shading, like a high-quality foliage texture from a modern fantasy game - not flat vector art, not clip-art, not cartoon outlines. 2x2 grid of four separate clusters, evenly spaced with clear empty gaps between them, none touching or overlapping, none crossing the middle lines of the image, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette. Viewed straight from the front, flat even lighting, no rim light, no dramatic highlights. Leaves broad and clearly readable in silhouette, crisp hard edges, sharp focus throughout, no blur, no glow. Strongly saturated colour, no lime or yellow-green, no pale tips, no near-white values anywhere in the leaves. No grid lines, no borders, no labels, no letters, no numbers. Flat game asset texture sheet.
```
