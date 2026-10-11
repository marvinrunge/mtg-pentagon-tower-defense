# Goblin Caves

A modular kit of goblin cliff dwellings for the volcano and the mountains around it in
the Red wedge: doorways carved into the rock, timber walkways, ladders, braziers. **No
reference images have been made and no credits have been spent yet.**

The route is the same as for the nature meshes (`docs/NATURE_ASSETS.md`, section 1):

1. A Gemini 3 Pro Image reference image per asset.
2. You approve it.
3. Meshy image-to-3D with Smart Topology (`meshy-t2`).

The prompts below use the same mandatory clauses as `tools/nature/nature_pipeline.py`
(semi-realistic style, mid-grey background, no shadow, no halo), so the kit matches the
nature assets.

**These pieces are placed by hand, not scattered.** A doorway has to sit on a cliff
face, a walkway against a wall, a ladder between two ledges. That is why they are not in
`tools/nature/nature_assets.json`: its `apply` stage would scatter them across the wedge
as TerraBrush objects (see section 6).

---

## 1. Kit design

**Two rock variants, one set of timber.** The volcano and the mountains need different
rock. The goblin carpentry is the same in both places, so it is generated only once.

| Variant | Where | Rock |
|---|---|---|
| `sand` | the mountains around the volcano | ochre and rust-red sandstone, like the reference art |
| `basalt` | the volcano's flank | black basalt, ash, rust streaks, thin ember cracks |

**Why the rock pieces are walls rather than whole mountains:**

- **The terrain already is the mountain.** The heightmap carries the volcano and its ridges, peak at world (-169, 191). A facade is a slice of cliff sunk 1-3 m into the slope; its back is a rough flat cut that nobody sees.
- **It also fixes the streaking.** On the volcano's ~60 degree flank, TerraBrush's straight-down texture projection streaks (`.agents/learnings.md`). A facade covers exactly those slopes with real rock texture.
- **The edges break up** into irregular rock on purpose, so the transition into the terrain is not a straight seam.
- **Slightly convex**, so the pieces sit on the convex cone of the volcano without gaps.

**Doorways are recesses, not caves.** Image-to-3D turns an opening into a shallow
indentation about 1 m deep with a dark interior. That is exactly right for 90% of the
openings. The one walk-in den gets the `cave-mouth`, whose tunnel fades into darkness.

**Openings stay dark in the image; the light comes from the engine.** Firelight painted
in would be baked into the albedo and would glow at midday too. At night the braziers and
lanterns carry OmniLights in their wrapper scenes (section 5).

**Scale:** doorways about 1.8 m tall, sized for goblins but still passable for the
player, and readable from the gameplay camera (`player_camera_distance` 3.2) as well as
from the lane against the horizon.

**Thin parts:** ladders, rope bridges and railings are the classic weak spot of
image-to-3D, where thin ropes and rungs melt together. The prompts ask for everything to
be "thick and chunky". If `ladder-long` or `rope-bridge` still comes out mushy, build them
procedurally in Blender (`tools/nature/blender/`) instead; that costs zero credits.

---

## 2. Order and costs

Start with the **mood concepts** (2a). They settle the look before a single model is
paid for, and the approved image becomes the style reference (anchor) for every
individual prompt.

| Phase | Assets | Purpose |
|---|---|---|
| 0 | 2 mood concepts | Settle the look (images only, no Meshy) |
| 1 | `sand-cliff-facade-wide`, `basalt-cliff-facade-wide`, `basalt-cave-mouth`, `walkway-straight`, `ladder-long`, `doorframe`, `ember-brazier`, `hanging-lantern` | Smallest set that already reads as "goblin caves". Test it in game before phase 2 |
| 2 | the remaining rock pieces in both variants | Variety, the pillar as a landmark |
| 3 | the remaining timber props | Dressing |

In total, 10 rock and 13 timber models make 23 Meshy models. At the roughly 15 credits
per textured image-to-3D model that `docs/NATURE_ASSETS.md` budgets, that is about 350
credits, of which about 120 are phase 1. Check the current prices before running.

### 2a. Mood concepts (not for Meshy)

Generate these in Gemini (Nano Banana Pro). The reference art you have can be attached as
an image for composition and atmosphere ("use as composition reference"). It only goes
into these two images, not into the asset prompts and not into the repo.

**Mountains (sandstone):**

```
Wide establishing concept painting for a semi-realistic fantasy tower defense game: a goblin cliff settlement carved into towering wind-eroded ochre and rust-red sandstone cliffs, dozens of goblin-sized doorways and small square windows on many levels, crooked timber walkways and platforms braced against the rock, long chunky lashed ladders between the ledges, stitched hide awnings, rusted scrap-iron chimneys, ember braziers glowing in a few doorways, a smoking volcano rising in the hazy background. Late afternoon light, warm dusty air, deep shadows inside the openings. Semi-realistic, believable materials and real surface detail, colour slightly richer than life, like a high-quality modern fantasy game environment concept - not cartoon, not low-poly, not hand-painted, not a photograph. No characters, no text, no logo, no watermark, no symbols from existing franchises.
```

**Volcano (basalt):**

```
Wide establishing concept painting for a semi-realistic fantasy tower defense game: goblin dens carved into the steep black basalt flank of an active volcano, goblin-sized doorways and small windows on several levels linked by crooked timber walkways, chunky lashed ladders and a sagging plank bridge, a large arched cave mouth leading deep into the mountain, riveted scrap-iron forge chimneys, ember braziers and hanging iron lanterns, ash-grey dust in every crevice, thin glowing ember cracks in the rock, smoke drifting from the summit. Dusk, warm ember light against cool ash-grey haze. Semi-realistic, believable materials and real surface detail, colour slightly richer than life, like a high-quality modern fantasy game environment concept - not cartoon, not low-poly, not hand-painted, not a photograph. No characters, no text, no logo, no watermark, no symbols from existing franchises.
```

Once a mood concept is approved, attach it to every asset prompt in that group as a
style reference, adding this sentence in front of "About ... metres":

```
Match the art style, rendering and palette of the reference image, but do not copy its composition - show only the single object described.
```

Use the sandstone concept for the `sand` pieces, the basalt concept for the `basalt`
pieces, and either one for the timber props.

---

## 2b. Generation settings

**Gemini:** model `gemini-3-pro-image`, iterate with `gemini-3.1-flash-image` until a
prompt works. Make 2 variants per asset and pick the better one.

**Gate before Meshy** (the same checks as the pipeline's `pick`):

- Nothing cropped at the frame edge.
- No shadow under the object.
- No glow halo.
- The background is flat grey.
- For walls: the openings really are recesses, not painted on.

**Meshy image-to-3D**, settings as in `nature_pipeline.py` `meshy_request()`:

| Field | Value |
|---|---|
| `ai_model` / `model_type` | `meshy-t2` / `smart-topology` |
| `target_polycount` | the asset's "Tris" column (cap 15,000) |
| `should_texture`, `enable_pbr` | `true` |
| `origin_at` | `bottom` |
| `target_formats` | `["glb"]` |

Smart Topology rejects `remove_lighting`. Leave it out.

**Output:** `assets/generated/goblin-<id>/` with the GLB, a preview PNG and the approved
reference image next to it as provenance.

---

## 3. Rock pieces (two variants each)

| Asset | Size (m) | Tris | View |
|---|---|---|---|
| `goblin-sand-cliff-facade-wide` | 14 x 10 | 6000 | wall |
| `goblin-basalt-cliff-facade-wide` | 14 x 10 | 6000 | wall |
| `goblin-sand-cliff-facade-tall` | 8 x 14 | 5000 | wall |
| `goblin-basalt-cliff-facade-tall` | 8 x 14 | 5000 | wall |
| `goblin-sand-cave-mouth` | 7 x 6 | 3000 | wall |
| `goblin-basalt-cave-mouth` | 7 x 6 | 3000 | wall |
| `goblin-sand-rock-pillar-dwelling` | 10 x 18 | 9000 | object |
| `goblin-basalt-rock-pillar-dwelling` | 10 x 18 | 9000 | object |
| `goblin-sand-carved-stairs` | 2.5 x 2.5 | 1500 | object |
| `goblin-basalt-carved-stairs` | 2.5 x 2.5 | 1500 | object |

### `goblin-sand-cliff-facade-wide`

```
Game asset concept render of a single isolated section of goblin cliff dwellings for a fantasy tower defense game: a broad slightly convex cliff wall of weathered ochre and rust-red sandstone with soft horizontal strata, wind-rounded bulges and vertical cracks, carved with six goblin-sized dwelling doorways and four small square windows on three uneven levels, each doorway about 1.8 metres tall with a crooked rectangular or rounded top, narrow carved ledges and a few rock-cut steps linking the levels, soot blackening above the doorways; every opening is a shallow recess about one metre deep with a dark sooty interior and no light inside; both side edges and the top break up into rough irregular rock so the piece blends into a surrounding slope, and the back is a rough flat cut because it will be sunk into a mountain. Setting: goblin cliff dwellings carved into the weathered sandstone mountains around a volcano, dry, dusty and sun-baked. Palette: warm ochre, rust red and burnt sienna sandstone, dark soot stains above the openings, ash grey dust, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 14 metres wide and 10 metres tall. Framing: front view turned about 25 degrees to the left and seen from slightly above, so the depth of the openings and ledges is visible, the whole piece centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-basalt-cliff-facade-wide`

```
Game asset concept render of a single isolated section of goblin cliff dwellings for a fantasy tower defense game: a broad slightly convex cliff wall of dark fractured basalt with rough columnar jointing, ash-grey dust in every crevice and rust-red oxidised streaks, carved with six goblin-sized dwelling doorways and four small square windows on three uneven levels, each doorway about 1.8 metres tall with a crooked rectangular or rounded top, narrow carved ledges and a few rock-cut steps linking the levels, soot blackening above the doorways; every opening is a shallow recess about one metre deep with a dark sooty interior and no light inside; both side edges and the top break up into rough irregular rock so the piece blends into a surrounding slope, and the back is a rough flat cut because it will be sunk into a mountain. Setting: goblin dens carved into the flank of an active volcano, ash, cooling lava and ember. Palette: basalt black, ash grey, rust red, thin ember orange cracks, sulphur-yellow crust accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 14 metres wide and 10 metres tall. Framing: front view turned about 25 degrees to the left and seen from slightly above, so the depth of the openings and ledges is visible, the whole piece centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-sand-cliff-facade-tall`

```
Game asset concept render of a single isolated tall narrow section of goblin cliff dwellings for a fantasy tower defense game: a tall slightly convex cliff wall of weathered ochre and rust-red sandstone with soft horizontal strata, wind-rounded bulges and vertical cracks, carved with four goblin-sized doorways stacked on four levels one above another and slightly offset, small square windows between them, a narrow ledge in front of every doorway, a crude chimney hole near the top streaked with soot; every opening is a shallow recess about one metre deep with a dark sooty interior and no light inside; both side edges and the top break up into rough irregular rock so the piece blends into a surrounding slope, and the back is a rough flat cut because it will be sunk into a mountain. Setting: goblin cliff dwellings carved into the weathered sandstone mountains around a volcano, dry, dusty and sun-baked. Palette: warm ochre, rust red and burnt sienna sandstone, dark soot stains above the openings, ash grey dust, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 8 metres wide and 14 metres tall. Framing: front view turned about 25 degrees to the left and seen from slightly above, so the depth of the openings and ledges is visible, the whole piece centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-basalt-cliff-facade-tall`

```
Game asset concept render of a single isolated tall narrow section of goblin cliff dwellings for a fantasy tower defense game: a tall slightly convex cliff wall of dark fractured basalt with rough columnar jointing, ash-grey dust in every crevice and rust-red oxidised streaks, carved with four goblin-sized doorways stacked on four levels one above another and slightly offset, small square windows between them, a narrow ledge in front of every doorway, a crude chimney hole near the top streaked with soot; every opening is a shallow recess about one metre deep with a dark sooty interior and no light inside; both side edges and the top break up into rough irregular rock so the piece blends into a surrounding slope, and the back is a rough flat cut because it will be sunk into a mountain. Setting: goblin dens carved into the flank of an active volcano, ash, cooling lava and ember. Palette: basalt black, ash grey, rust red, thin ember orange cracks, sulphur-yellow crust accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 8 metres wide and 14 metres tall. Framing: front view turned about 25 degrees to the left and seen from slightly above, so the depth of the openings and ledges is visible, the whole piece centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-sand-cave-mouth`

```
Game asset concept render of a single isolated goblin cave entrance for a fantasy tower defense game: a large rough arched cave mouth cut into a block of weathered ochre and rust-red sandstone with soft horizontal strata, wind-rounded bulges and vertical cracks, about 4 metres wide and 3.5 metres tall, the tunnel behind it running deep into the rock and fading into darkness, a rough rock lintel above with soot stains, worn smooth threshold stones, two short rock buttresses on either side; both side edges and the top break up into rough irregular rock so the piece blends into a surrounding slope, and the back is a rough flat cut because it will be sunk into a mountain. Setting: goblin cliff dwellings carved into the weathered sandstone mountains around a volcano, dry, dusty and sun-baked. Palette: warm ochre, rust red and burnt sienna sandstone, dark soot stains above the openings, ash grey dust, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 7 metres wide and 6 metres tall. Framing: front view turned about 25 degrees to the left and seen from slightly above, so the depth of the openings and ledges is visible, the whole piece centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-basalt-cave-mouth`

```
Game asset concept render of a single isolated goblin cave entrance for a fantasy tower defense game: a large rough arched cave mouth cut into a block of dark fractured basalt with rough columnar jointing, ash-grey dust in every crevice and rust-red oxidised streaks, about 4 metres wide and 3.5 metres tall, the tunnel behind it running deep into the rock and fading into darkness, a rough rock lintel above with soot stains, worn smooth threshold stones, two short rock buttresses on either side; both side edges and the top break up into rough irregular rock so the piece blends into a surrounding slope, and the back is a rough flat cut because it will be sunk into a mountain. Setting: goblin dens carved into the flank of an active volcano, ash, cooling lava and ember. Palette: basalt black, ash grey, rust red, thin ember orange cracks, sulphur-yellow crust accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 7 metres wide and 6 metres tall. Framing: front view turned about 25 degrees to the left and seen from slightly above, so the depth of the openings and ledges is visible, the whole piece centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-sand-rock-pillar-dwelling`

```
Game asset concept render of a single isolated free-standing rock pillar riddled with goblin dwellings for a fantasy tower defense game: a tall wind-eroded hoodoo rock pillar of weathered ochre and rust-red sandstone with soft horizontal strata, wind-rounded bulges and vertical cracks, wider at the middle and with an overhanging cap, honeycombed with goblin-sized doorways and small windows on five levels, narrow ledges spiralling around it, a few rock-cut steps; every opening is a shallow recess about one metre deep with a dark sooty interior and no light inside; the base cut off flat where it meets the ground. Setting: goblin cliff dwellings carved into the weathered sandstone mountains around a volcano, dry, dusty and sun-baked. Palette: warm ochre, rust red and burnt sienna sandstone, dark soot stains above the openings, ash grey dust, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 10 metres wide and 18 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-basalt-rock-pillar-dwelling`

```
Game asset concept render of a single isolated free-standing rock pillar riddled with goblin dwellings for a fantasy tower defense game: a tall wind-eroded hoodoo rock pillar of dark fractured basalt with rough columnar jointing, ash-grey dust in every crevice and rust-red oxidised streaks, wider at the middle and with an overhanging cap, honeycombed with goblin-sized doorways and small windows on five levels, narrow ledges spiralling around it, a few rock-cut steps; every opening is a shallow recess about one metre deep with a dark sooty interior and no light inside; the base cut off flat where it meets the ground. Setting: goblin dens carved into the flank of an active volcano, ash, cooling lava and ember. Palette: basalt black, ash grey, rust red, thin ember orange cracks, sulphur-yellow crust accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 10 metres wide and 18 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-sand-carved-stairs`

```
Game asset concept render of a single isolated flight of goblin rock-cut stairs for a fantasy tower defense game: a narrow staircase of nine uneven steps cut into a sloping block of weathered ochre and rust-red sandstone with soft horizontal strata, wind-rounded bulges and vertical cracks, rising about 2.5 metres over 6 metres length, worn and chipped edges, a low rough rock parapet on one side, the underside and back a rough flat cut because it will be sunk into a slope. Setting: goblin cliff dwellings carved into the weathered sandstone mountains around a volcano, dry, dusty and sun-baked. Palette: warm ochre, rust red and burnt sienna sandstone, dark soot stains above the openings, ash grey dust, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 2.5 metres wide and 2.5 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-basalt-carved-stairs`

```
Game asset concept render of a single isolated flight of goblin rock-cut stairs for a fantasy tower defense game: a narrow staircase of nine uneven steps cut into a sloping block of dark fractured basalt with rough columnar jointing, ash-grey dust in every crevice and rust-red oxidised streaks, rising about 2.5 metres over 6 metres length, worn and chipped edges, a low rough rock parapet on one side, the underside and back a rough flat cut because it will be sunk into a slope. Setting: goblin dens carved into the flank of an active volcano, ash, cooling lava and ember. Palette: basalt black, ash grey, rust red, thin ember orange cracks, sulphur-yellow crust accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 2.5 metres wide and 2.5 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

## 4. Timber and goblin props (shared, once)

| Asset | Size (m) | Tris |
|---|---|---|
| `goblin-walkway-straight` | 6 x 2.2 | 1800 |
| `goblin-platform-corner` | 3 x 3 | 1500 |
| `goblin-ladder-long` | 1 x 6 | 600 |
| `goblin-doorframe` | 1.6 x 2.2 | 900 |
| `goblin-hide-awning` | 2.6 x 2.2 | 900 |
| `goblin-rope-bridge` | 10 x 1.8 | 2500 |
| `goblin-ember-brazier` | 0.8 x 1.2 | 700 |
| `goblin-hanging-lantern` | 0.6 x 1 | 400 |
| `goblin-pulley-crane` | 3.5 x 4 | 1800 |
| `goblin-junk-pile` | 2 x 1 | 1200 |
| `goblin-forge-chimney` | 1.2 x 4 | 1000 |
| `goblin-spiked-barricade` | 4 x 2.2 | 1200 |
| `goblin-war-banner` | 0.9 x 4 | 600 |

### `goblin-walkway-straight`

```
Game asset concept render of a single isolated goblin cliff walkway for a fantasy tower defense game: a straight 6-metre plank walkway of crooked uneven boards nailed with oversized iron nails, carried by three angled timber struts that would brace against a cliff wall on one side, a crude railing of thick knobbly posts and one thick rope on the open side, a few boards missing or patched with riveted scrap iron. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 6 metres wide and 2.2 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-platform-corner`

```
Game asset concept render of a single isolated goblin cliff platform for a fantasy tower defense game: a roughly square 3 by 3 metre timber platform of crooked planks on four thick stilts with diagonal braces, thick knobbly railing posts and rope on two sides, the other two sides open to connect walkways, one corner patched with a riveted scrap iron plate. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 3 metres wide and 3 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-ladder-long`

```
Game asset concept render of a single isolated goblin ladder for a fantasy tower defense game: a single tall crude ladder made of two thick crooked timber poles and eight chunky round rungs lashed on with thick rope, slightly leaning, the poles a bit uneven in length, every part thick and chunky, no thin parts. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 1 metres wide and 6 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-doorframe`

```
Game asset concept render of a single isolated goblin door frame for a fantasy tower defense game: a crude goblin door frame of three thick crooked timbers lashed and nailed together, reinforced with riveted rusty scrap iron plates and iron spikes along the lintel, a heavy stitched hide curtain hanging closed in the middle, sized to fit a 1.8 metre doorway in a rock wall, flat at the back. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 1.6 metres wide and 2.2 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-hide-awning`

```
Game asset concept render of a single isolated goblin hide awning for a fantasy tower defense game: a lean-to awning of stitched patched hides in rust red and ochre stretched over two crooked poles and tied with rope, sloping down from a flat back edge that would be fixed to a rock wall, the hides thick and sagging slightly, a frayed hem. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 2.6 metres wide and 2.2 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-rope-bridge`

```
Game asset concept render of a single isolated goblin plank bridge for a fantasy tower defense game: a short sagging bridge of thick crooked planks laid across two heavy ropes, chunky knotted rope handrails on both sides tied to a stout wooden post at each of the four corners, a few planks missing, every rope thick and chunky. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 10 metres wide and 1.8 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-ember-brazier`

```
Game asset concept render of a single isolated goblin ember brazier for a fantasy tower defense game: a crude brazier of a rusted iron bowl riveted from scrap plates on three crooked iron legs, heaped with glowing orange embers and coals, the glow strictly inside the bowl - no flames, no halo, no light cast onto the iron or the background. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 0.8 metres wide and 1.2 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-hanging-lantern`

```
Game asset concept render of a single isolated goblin hanging lantern for a fantasy tower defense game: a crooked iron lantern cage riveted from scrap with a glowing orange ember lump inside, hanging from a short bent iron bracket that would be fixed to a rock wall, the glow strictly inside the cage - no halo, no light cast onto the bracket or the background. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 0.6 metres wide and 1 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-pulley-crane`

```
Game asset concept render of a single isolated goblin pulley crane for a fantasy tower defense game: a crude wooden jib crane of crooked beams lashed with rope, a big wooden pulley wheel at the tip, a thick rope hanging down to a woven basket of scrap and stones, a small hand winch at the base, the base flat because it would stand on a cliff ledge. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 3.5 metres wide and 4 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-junk-pile`

```
Game asset concept render of a single isolated goblin junk pile for a fantasy tower defense game: a heap of goblin scrap: broken barrels, bent iron plates with rivets, a cracked shield, splintered planks, a coil of rope, a dented pot and a few animal bones. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 2 metres wide and 1 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-forge-chimney`

```
Game asset concept render of a single isolated goblin forge chimney for a fantasy tower defense game: a crooked chimney pipe riveted from mismatched rusted iron plates, bent twice, with a dented conical cap and iron bands, blackened with soot at the top, a flat flange at the bottom where it would come out of a rock wall. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 1.2 metres wide and 4 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-spiked-barricade`

```
Game asset concept render of a single isolated goblin spiked barricade for a fantasy tower defense game: a 4-metre barricade of sharpened crooked stakes lashed together with rope, leaning outward, two diagonal braces at the back, a few rusted iron spikes and a dented scrap shield nailed to the front. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 4 metres wide and 2.2 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

### `goblin-war-banner`

```
Game asset concept render of a single isolated goblin war banner for a fantasy tower defense game: a crooked wooden pole topped with a rusted iron blade and a bundle of feathers, a tattered rust-red cloth banner hanging from a crossbar with a crude ochre painted flame shape on it, the cloth thick and heavy, frayed and torn at the bottom. Setting: a crude goblin cliff settlement built from scavenged timber, rope, hides and riveted scrap iron, used both in sandstone mountains and on a volcano. Palette: sun-bleached grey-brown timber, frayed tan hemp rope, rust-red and ochre hides, dark rusted iron, small ember orange accents. Style: semi-realistic fantasy game asset - believable natural materials and proportions, real surface detail (fractures, weathering, grain, subtle colour variation), colour slightly richer than life, and a clear silhouette that still reads from far away. Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not low-poly, not hand-painted, and not a photograph. About 0.9 metres wide and 4 metres tall. Framing: three-quarter view from slightly above, the whole object centred and fully inside the frame with a wide empty margin on every side, nothing cropped. Background: plain flat uniform neutral mid-grey (#808080), no gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the object: no soil patch, no ground island, no base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off cleanly where it would meet the ground. Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no bloom, no glow halo outside the object. No text, no logo, no watermark, no border, no characters, no symbols from existing franchises.
```

---

## 5. Integration in Godot

- **Placement:** by hand under a node such as `GoblinCaves` in `scenes/misc/main.tscn`, Red wedge only. The facades go on the volcano's steep flanks and on the mountains around it. Sink each rock piece 1-3 m into the terrain so no edge floats.
- **Ledges in the terrain:** where walkways and platforms stand, flatten the slope locally with the TerraBrush sculpt tool, the same as the crater rims in `docs/BIOME_ASSETS.md`.
- **Wrapper scenes:** one `.tscn` per asset under `scenes/environment/goblin/`. It fixes scale and orientation and adds collision:
  - rock pieces get a convex hull, or a few boxes, never trimesh on large pieces;
  - timber props get none, or a box.
- **Light at night:**
  - `ember-brazier` and `hanging-lantern` get a warm OmniLight (ember orange, short range, no shadow) plus an emissive material on the embers.
  - The doorways get a dark-orange emissive patch at the back of the recess, or simply a lantern in front of them. That stays dark by day and glows at night.
  - Keep the number of lights small, so a few braziers in each settlement rather than one per door.
- **Smoke:** reuse `scenes/environment/volcano_smoke.tscn` (and its puff texture) on the `forge-chimney` pieces.
- **Validation:** `./tools/validate_godot.ps1`, then look at the pieces from the gameplay camera and from the lane, and check them at night.

## 6. Option: through the pipeline

If you want the concept, pick, approve and mesh stages of `nature_pipeline.py` for these
assets as well (review page, automatic gates, resumable Meshy runs), the pipeline needs
one small change:

1. A placement field (`"placement": "manual"`) that `build` and `apply` skip.
2. The `wall` framing as a second framing variant in `mesh_concept_prompt()`.
3. A `goblin` group with the moods and palettes from this file.

The prompts here were assembled from exactly those building blocks, so they would stay
the same.
