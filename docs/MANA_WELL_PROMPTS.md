# Mana well prompts (concept image -> Meshy)

New prompts for the five mana wells, replacing `assets/structures/mana-well-<colour>`.

## Why the current ones look wrong

They were made with Meshy **text-to-3D on its `lowpoly` model type**, from prompts that
open with "Single isolated low-poly fantasy mana well". That is the stylised, faceted look
the rest of the game has moved away from (semi-realistic, see the nature set). Text-to-3D
also gives no say over the design before credits are spent.

New route, the same as the nature assets:

1. **Concept image:** generate it from the prompt below (Gemini, or any image model).
2. **Approval:** you pick the one you like.
3. **Mesh:** Meshy **image-to-3D, Smart Topology (meshy-t2)**, about 3,000 triangles.

## Rules every well follows

Gameplay sets these, so every prompt carries them:

- **Size:** about 3 m wide and 2.4 m tall. The model is scaled to that in the engine.
- **Compact base:** at most about 1.6 m from the centre. Myrs stand round the well at
  2.3 m to harvest (`myr_well_slot_radius`), so there must be open ground there. No wide
  steps, platforms or stairs.
- **Five-sided:** a pentagonal basin with five uprights. Five colours, five lanes, and the
  map is a pentagon.
- **An empty cradle on top:** the uprights curve inward over the centre and hold nothing.
  The game puts that colour's glowing mana crystal there (the same tinted crystals now in
  the world), plus a glowing mana pool in the basin, a light and rising motes. That is why:
  - **No glow, no liquid, no light in the concept:** Meshy bakes a glow into the texture as
    a fog shell around the model, and liquid as a solid lump.
  - **Dry, empty basin:** the colour of the magic comes from the engine, so it stays
    tunable for free, and can glow brighter at night.
- **Colour identity from materials and shape,** not from coloured light.
- **Readable from 100 m:** each well needs a silhouette you can tell apart from the
  other four at a glance.

## Real Magic cards to look at

For **mood, materials and silhouette only**: look at them, don't trace them or feed them to a
generator as the image to copy. Card art belongs to Wizards of the Coast and its artists.
All of them can be looked up on [Scryfall](https://scryfall.com).

| Colour | Cards | What to take from them |
|---|---|---|
| All five | **Font of Vigor / Font of Fortunes / Font of Return / Font of Ire / Font of Fertility** (*Born of the Gods*) | A five-colour cycle of literal fonts: one sacred basin, re-dressed per colour. Closest to what a mana well is. |
| All five | **Honden of Cleansing Fire / Seeing Winds / Night's Reach / Infinite Rage / Life's Web** (*Champions of Kamigawa*) | A cycle of shrines, one per colour: compact, upright, iconic. Good for silhouettes. |
| Colourless | **Nykthos, Shrine to Nyx** (*Theros*), **Font of Mythos** (*Conflux*) | A shrine that *makes* mana; an artifact font. |
| White | **Serra's Sanctum** (*Urza's Saga*) | Sunlit order, pale stone, holy light from above. |
| Blue | **Tolarian Academy** (*Urza's Saga*) | Arcane, tidal, scholarly; water and glass. |
| Black | **Cabal Coffers** (*Torment*) | A mana source as a dark crypt; hoarded, sinister. |
| Red | **Valakut, the Molten Pinnacle** (*Zendikar*) | Volcanic rock, heat, jagged peaks. |
| Green | **Gaea's Cradle** (*Urza's Saga*) | Mana cradled in living roots - the literal "cradle" idea. |

## Framing block (paste after every colour's prompt)

The same framing the nature pipeline uses (`mesh_concept_prompt` in
`tools/nature/nature_pipeline.py`). Each line prevents a known Meshy failure:

```
Framing: three-quarter view from slightly above, the whole object centred and fully inside
the frame with a wide empty margin on every side, nothing cropped. Background: plain flat
uniform neutral mid-grey (RGB 128, 128, 128), no gradient, no vignette, no floor, no ground
plane, no cast shadow, no contact shadow, no other objects, no scenery. Nothing around the
object: no soil patch, no ground island, no puddle or water, no grass tufts or pebbles at
its foot, no mist, fog, smoke, steam, sparks, particles or drips - the object alone, cut off
cleanly where it would meet the ground. Lighting: soft even neutral studio light, no
coloured light, no dramatic rim light, no bloom, no glow halo, nothing glowing. No text, no
logo, no watermark, no border, no characters, no symbols from existing franchises.
```

## The prompts

Each starts with the same opening sentence, then the colour's design, then the framing block.

**Shared opening** (start of every prompt):

```
Game asset concept render of a single isolated mana well for a semi-realistic fantasy
tower defense game. Style: semi-realistic fantasy game asset - believable materials and
proportions, real surface detail (chisel marks, weathering, cracks, grain, subtle colour
variation), colour slightly richer than life, a clear silhouette that reads from far away.
Like a high-quality modern fantasy game asset render: not cartoon, not toon-shaded, not
low-poly, not hand-painted, not a photograph. About 3 metres wide and 2.4 metres tall, on a
compact footprint. Shape: a low five-sided (pentagonal) basin, dry and empty inside, with
five uprights rising from its corners and curving inward over its centre to form an open,
empty cradle at the top - nothing in the cradle, nothing in the basin.
```

### White - the sun shrine

```
Design: a sunlit sanctum well of pale cream limestone and polished white marble. The basin
rim is a broad marble band with thin gold inlay lines and a running laurel relief; each of
its five faces carries a carved sunburst. The five uprights are slender fluted columns of
white marble, banded with gold at their capitals, curving inward at the top into five
gilded ribs that form an elegant open crown-shaped cradle. Ordered, symmetrical, serene,
like a temple font in a wheat field at noon.
```

### Blue - the tide font

```
Design: a tidal font of dark blue-grey basalt and polished wet-looking slate. The basin is
built from short hexagonal basalt columns, its rim carved with flowing wave scrollwork and
inlaid with pale mother-of-pearl. The five uprights are tall sweeping fins shaped like
breaking waves or nautilus shells, smooth and sea-worn, curling inward at the top into an
open spiral cradle. Small barnacles and salt crust at the base edges. Cold, elegant,
ancient, like a font of the sea.
```

### Black - the ossuary well

```
Design: a sinister swamp ossuary well of cracked black slate and old weathered dark stone.
The basin is bound with tarnished, pitted iron bands and has a small carved skull at each
of its five corners. The five uprights are long crooked bone-white ribs, like the ribcage
of some huge dead thing, rising from the corners and bending inward at the top into an
open claw-like cradle. Dead black roots grip the base. Grim, decayed, hungry, like a
well in a drowned graveyard.
```

### Red - the forge well

```
Design: a volcanic forge well of rough dark basalt and cracked black obsidian. The basin is
clamped with heavy hammered bronze braces and rivets, its rim jagged and scorched-looking
(dark soot staining, no glow). The five uprights are jagged obsidian horns with sharp
fractured edges, flame-shaped stone fins between them, hooking inward at the top into an
aggressive open cradle like a dragon's claw. Brutal, angular, hot-blooded, like an anvil
shrine at the foot of a volcano.
```

### Green - the root cradle

```
Design: a living root well of mossy grey fieldstone, its basin cracked and half swallowed
by thick living tree roots. The five uprights are gnarled roots as thick as an arm,
twisting up from the corners and braiding inward at the top into an open woven cradle,
with a few fresh leaves budding on them. Spiral druidic knotwork is carved into the stone
under the moss. Ancient, wild, alive, like the heart of a primeval forest.
```

## After the images

1. **Pick:** choose one image per colour. Save it as
   `assets/structures/mana-well-<colour>/mana-well-<colour>_concept.png`.
2. **Mesh:** that image goes to Meshy image-to-3D (meshy-t2, about 3,000 triangles). It
   costs credits, so only when you say so.
3. **Engine:**
   - **Cradle:** the colour's tinted crystal cluster, with `mana_crystal.gdshader`, brighter
     than the decor crystals.
   - **Basin:** a glowing mana-pool disc.
   - **Light and motes:** a light in the well's colour, plus rising motes.
   - **Hand-over:** `scripts/well_crystals.gd` already lights the wells and rings them with
     crystals. The well's own glow moves into the new well scene.
