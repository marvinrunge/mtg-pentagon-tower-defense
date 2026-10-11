# Mana well prompts (concept image -> Meshy)

New prompts for the five mana wells, replacing `assets/structures/mana-well-<colour>`.

**Revision 2:** the wells are **natural, magical formations**, not built shrines. Each one
is a place where mana wells up out of the land on its own: a raised volcanic basin, a
giant magical plant, a natural spring. Their basins are modelled **empty**; the magical
water, lava or ooze is made in Godot.

## Why the current ones look wrong

They were made with Meshy **text-to-3D on its `lowpoly` model type**, from prompts that
open with "Single isolated low-poly fantasy mana well". That is the stylised, faceted look
the rest of the game has moved away from (semi-realistic, see the nature set). Text-to-3D
also gives no say over the design before credits are spent.

New route, the same as the nature assets:

1. **Concept image:** generate it from the prompt below (Gemini, or any image model).
2. **Approval:** you pick the one you like.
3. **Mesh:** Meshy **image-to-3D, Smart Topology (meshy-t2)**, about 3,000-4,000 triangles.

## Rules every well follows

Gameplay and the Meshy pipeline set these, so every prompt carries them:

- **Natural origin:** grown, eroded or erupted, never built. No masonry, no carved
  ornament, no metal, nothing made by hands.
- **Size:** about 3 m wide and 1.6-2.2 m tall, scaled to that in the engine.
- **Compact base:** at most about 1.6 m from the centre. Myrs stand round the well at
  2.3 m to harvest (`myr_well_slot_radius`), so the ground there stays open. No wide
  spreading roots, ledges or slopes beyond that.
- **A raised, empty basin on top:** a bowl with a clean, roughly level rim and a smooth
  dry inside, open to the sky. The engine fills it with the colour's magical surface
  (glowing water, lava, ooze, sap) at a fixed height, so the inside must have no lumps
  sticking up through where the surface will be.
- **Mana crystals grow out of it, subtly:** a few small crystal clusters breaking out of
  the rim and the flanks, in the colour of the well - accents, not the main shape.
- **Magical cracks:** thin veins and fissures in the colour of the well, filled with a
  bright **flat-coloured mineral**. Not glowing in the concept: Meshy bakes a glow into the
  texture as a fog shell around the model. The engine makes these veins and the crystals
  glow (an emission mask keyed on that colour), brighter at night.
- **No liquid, no light, no glow, no mist** in the concept - all of that is the engine's.
- **Readable from 100 m:** each well needs a silhouette you can tell apart from the other
  four at a glance.

## References

For **mood, materials and silhouette only**: look at them, don't trace them or feed them to a
generator as the image to copy. Card art belongs to Wizards of the Coast and its artists;
all of them can be looked up on [Scryfall](https://scryfall.com). The real places are the
best guide for the semi-realistic look.

| Colour | Magic cards | Real places |
|---|---|---|
| White | Mistveil Plains (*Shadowmoor*), Emeria, the Sky Ruin (*Zendikar*) | the white travertine terraces of **Pamukkale**, Turkey; Mammoth Hot Springs, Yellowstone |
| Blue | Halimar Depths (*Zendikar*), Flooded Grove (*Shadowmoor*) | the hexagonal basalt columns of **Giant's Causeway**, Northern Ireland; tidal rock pools |
| Black | Urborg, Tomb of Yawgmoth (*Planar Chaos*), Bojuka Bog (*Worldwake*) | peat bogs and **petrified wood**; mangrove root tangles |
| Red | Valakut, the Molten Pinnacle (*Zendikar*), Lavaclaw Reaches (*Worldwake*) | **spatter cones** and lava lakes, e.g. Erta Ale, Ethiopia; Hawaiian lava tubes |
| Green | Gaea's Cradle (*Urza's Saga*), Yavimaya, Cradle of Growth (*Modern Horizons 2*), Utopia Sprawl (*Dissension*) | **pitcher plants** and bromeliads, bracket fungi on old trees |

## Framing block (paste after every colour's prompt)

The same framing the nature pipeline uses (`mesh_concept_prompt` in
`tools/nature/nature_pipeline.py`). Each line prevents a known Meshy failure:

```
Framing: three-quarter view from slightly above, the whole object centred and fully inside
the frame with a wide empty margin on every side, nothing cropped, the empty basin clearly
visible from above. Background: plain flat uniform neutral mid-grey (RGB 128, 128, 128), no
gradient, no vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other
objects, no scenery. Nothing around the object: no soil patch, no ground island, no puddle
or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, steam, sparks,
particles or drips - the object alone, cut off cleanly where it would meet the ground.
Lighting: soft even neutral studio light, no coloured light, no dramatic rim light, no
bloom, no glow halo, nothing glowing. No text, no logo, no watermark, no border, no
characters, no symbols from existing franchises.
```

## The prompts

Each prompt is: the shared opening, then the colour's design, then the framing block.

**Shared opening** (start of every prompt):

```
Game asset concept render of a single isolated natural mana well for a semi-realistic
fantasy tower defense game: a place where magic wells up out of the land on its own -
grown, eroded or erupted, not built, with no masonry, no carvings, no metal and nothing
made by hands. Style: semi-realistic fantasy game asset - believable natural materials and
proportions, real surface detail (cracks, weathering, grain, subtle colour variation),
colour slightly richer than life, a clear silhouette that reads from far away. Like a
high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not
low-poly, not hand-painted, not a photograph. About 3 metres wide and 2 metres tall, on a
compact footprint. On top, a raised open basin: a bowl with a clean, roughly level rim and
a smooth, completely EMPTY and DRY inside - no liquid, no lava, no water, nothing in it.
A few small mana crystal clusters break subtly out of the rim and flanks, and thin magical
cracks run through the surface, filled with a bright flat-coloured mineral (not glowing).
```

### White - the sunstone spring

```
Design: a natural sunstone spring of pure white travertine, like the mineral terraces of
Pamukkale: a raised rounded basin built up from layered, scalloped white mineral
deposits, its rim lined with small natural terrace lips, the stone pale cream to bright
white with warm golden mineral streaks. Thin cracks filled with bright gold mineral run
up its sides. Small clusters of pale gold citrine crystals break out of the rim. Pure,
bright, orderly, serene - a holy spring that formed itself.
```

### Blue - the tidal column pool

```
Design: a natural tidal pool rising out of tightly packed hexagonal basalt columns, like
the Giant's Causeway: the columns stand at different heights, the tallest ones forming the
basin's raised rim, their tops worn smooth and wet-looking, dark blue-grey. Patches of
barnacles, salt crust and pale coral cling to the lower columns. Thin cracks filled with
bright icy-cyan mineral run between the columns. Small clusters of deep sapphire-blue
crystals grow out of the gaps between the columns at the rim. Cold, ancient, tidal.
```

### Black - the bog sink

```
Design: a natural swamp sinkhole raised on a mound of black peat and petrified bog wood:
gnarled, blackened, half-fossilised roots and dead branches coil up and twist together
into the basin's rim, with a few huge fossilised ribs of some ancient creature arching out
of the mound among them. Dark, wet-looking, rotting textures, pale grey lichen in places.
Thin cracks filled with bright violet mineral run through the petrified wood. Small
clusters of dark amethyst-violet crystals grow out of the roots near the rim. Sinister,
ancient, hungry - a place where death pools.
```

### Red - the volcanic vent

```
Design: a raised volcanic spatter cone of rough black basalt and cooled lava: the basin is
the vent's crater, its rim jagged and built from congealed lava splatter and ropey
pahoehoe folds, the flanks scorched dark with rust-red and sulphur-yellow mineral staining
(no glow). Deep jagged fissures filled with bright orange-red mineral split the cone from
the rim down. Small clusters of ruby-red crystals break out of the cracks near the rim.
Raw, violent, hot-blooded - the earth itself bleeding mana.
```

### Green - the cradle plant

```
Design: a giant magical plant that grows as a living basin, like an enormous pitcher plant
or bromeliad: thick, waxy, overlapping leaves curve up from a knot of roots to form a
deep cupped bowl, their edges slightly frilled, deep green fading to lime at the tips and
veined with paler green. Clusters of small mushrooms and bracket fungi grow out of the
base and the lower leaves, cream and pale green. Thin veins filled with bright lime-green
mineral run along the leaves. Small clusters of emerald-green crystals grow among the
mushrooms at the foot and out of the leaf joints. Wild, alive, ancient - mana drawn up
out of the forest floor.
```

## After the images

1. **Pick:** choose one image per colour. Save it as
   `assets/structures/mana-well-<colour>/mana-well-<colour>_concept.png`.
2. **Mesh:** that image goes to Meshy image-to-3D (meshy-t2, about 3,000-4,000 triangles).
   It costs credits, so only when you say so.
3. **Engine:**
   - **Basin surface:** a disc at the basin's height with an animated shader per colour -
     golden light-water for White, glowing sea-water for Blue, violet ooze for Black, lava
     for Red, luminous sap for Green - brighter at night on the `crystal_night` clock.
   - **Glowing cracks and crystals:** an emission mask keyed on each well's crack colour,
     so the mineral veins and crystal outgrowths light up, again stronger at night.
   - **Light and motes:** a light in the well's colour plus rising motes.
   - **Hand-over:** the crystals round the wells (`PlacedCrystals/Wells` in main.tscn)
     stay; the `WellGlow_<colour>` lights there move into the new well scenes.
