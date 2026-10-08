# Nature Assets

Plan for the living layer of the five biomes: grass, ground cover, bushes, trees,
stones, mana crystals, fungus and a few biome specials. 73 assets, 15 per lane (13 in
White). **Nothing in this file has been generated yet, and no credits have been spent.**

**Revision 2 (2026-10-01).** Three changes, explained in sections 3a-3d:

- **Mana crystals:** one set of colourless crystals, recoloured per biome in the engine (3a).
- **Leafy trees and bushes:** move from Meshy to a procedural Blender route (3b).
- **Textures and Blender MCP:** a texture plan (3c) and Blender MCP for interactive authoring (3d).

**The manifest, the generated prompts and the pipeline still describe revision 1.** They
get updated when this revision is approved; the task list is in section 10.

| File | What it is |
|---|---|
| `tools/nature/nature_assets.json` | The source of truth: every asset, its size, polycount, scatter rules and prompt text |
| `docs/NATURE_PROMPTS.md` | Every full prompt, ready to paste. **Generated** from the manifest |
| `tools/nature/nature_pipeline.py` | The automated pipeline (Gemini -> your approval -> Meshy -> Godot -> TerraBrush) |
| `tools/build_nature_cards.gd` | Keys card sheets into foliage textures |
| `tools/build_nature_terrabrush.gd` | Builds meshes, wrapper scenes, TerraBrush resources and scatter masks |
| `assets/shaders/nature_foliage.gdshader` | TerraBrush's foliage shader with the two fixes the cards need |

Companions: `docs/BIOME_ASSETS.md` covers the built and dead set dressing (ruins,
wagons, bones, craters), and nothing here repeats it. `docs/GRASS_ATLAS_PROMPTS.md`
covers the five grass sheets, which this plan reuses as they are.

---

## 1. Tool choice

| Job | Use | Why |
|---|---|---|
| Reference images for 3D | **Gemini 3 Pro Image ("Nano Banana Pro")**, `gemini-3-pro-image` | Best prompt adherence of the Nano Banana family. It can also take a style reference image per group (`anchor` in the manifest). None is set: the mana-well renders were rejected as references, so prompts are text-only for now |
| Iterating on prompts | **Nano Banana 2**, `gemini-3.1-flash-image` (`--draft`) | Cheaper and faster. Use it until a prompt works, then switch to Pro for the keepers |
| 2D foliage cards | Gemini 3 Pro Image | Same rules as the grass sheets: 2x2 on pure white |
| Solid 3D models (rocks, crystals, fungus, stumps, dead trees, specials) | **Meshy image-to-3D, Smart Topology (`meshy-t2`)** - confirmed | Builds directly at the target triangle count (100-15,000), triangles only, PBR textured. It is what `tools/meshy_asset.ps1` already uses for props, so new and old assets match |
| Leafy trees and bushes | **Blender 4.3 (installed), Geometry Nodes, run headless** | Procedural trunks and branches plus alpha leaf cards, or faceted canopy blobs. Any number of variants from one recipe by changing the seed. See 3b |
| Leaf, bark and bush textures | **Gemini 3 Pro Image** + the existing keyer | Leaf-cluster sheets keyed to alpha exactly like the grass; tileable bark. See 3c |
| Interactive tree/bush authoring | **Blender MCP** | Claude drives Blender while you watch, to settle each species' recipe once. Not part of the automated run. See 3d |
| Big landmark (sea-stack arch) | Meshy image-to-3D, `standard` + remesh | Only where t2's budget can't hold the silhouette |
| Orchestration | One Python script + Godot headless | Same pattern as `tools/generate_sfx.py`: standard library only, resumable, keys from the environment. No ComfyUI or n8n: they add a second toolchain to keep alive without doing anything a 700-line script can't |

**Why image-to-3D instead of text-to-3D (as `docs/BIOME_ASSETS.md` uses):** you get
to judge, and automatically gate, a cheap 2D image before paying for 3D. The image
also fixes the art style far more tightly than a text prompt can. Meshy's own text
prompt is only a few lines; a reference image is the whole look.

**Alternative worth knowing:** Meshy's text-to-image API now serves the same Nano
Banana models (`nano-banana-pro`, 9 credits) and can chain straight into image-to-3D
via `input_task_id`. That means one key and one bill, but no style reference images,
which is why the pipeline calls Gemini directly.

---

## 2. Three routes: card, mesh, procedural

| Route | Categories | How it's made | How it's drawn |
|---|---|---|---|
| **card** | grass, ground cover, tall plants (ferns, reeds, flowers) | Gemini 2x2 sheet -> keyed alpha tiles | Crossed quads, one TerraBrush **foliage** layer per biome per height |
| **mesh** | rocks, crystals, fungus, stumps, logs, dead trees, specials | Gemini reference -> Meshy t2 | TerraBrush **objects** (OctreeMultiMesh) |
| **procedural** | every tree and bush with leaves | Blender Geometry Nodes recipe + Gemini leaf/bark textures | TerraBrush **objects**, same as mesh |

The line between mesh and procedural follows what image-to-3D can and can't do (3b):
anything that is one solid lump goes to Meshy, and anything that is mostly leaves goes
to Blender. The "No foliage from Meshy" caveat in `docs/BIOME_ASSETS.md` therefore
stands as written.

---

## 3. The list

Full prompts: `docs/NATURE_PROMPTS.md`. Sizes are width x height in metres; tris is the
Meshy target polycount.

### White - Plains (13)

Sun, order, harvest: gold, cream limestone, sage.

| Asset | Kind | Route | Tier | Size | Tris |
|---|---|---|---|---|---|
| wheat-grass | grass | card (existing sheet) | ground cover | 0.9 | - |
| wildflowers | flowers | card | ground cover | 0.7 | - |
| tall-meadow | tall grass + sunflowers | card | tall cover | 1.3 x 1.6 | - |
| boxwood-hedge | clipped hedge bush | **procedural** | bush | 1.8 x 1.4 | 900 |
| sunbloom-shrub | flowering shrub | **procedural** | bush | 1.6 x 1.3 | 1000 |
| silver-birch | slender tree | **procedural** | tree | 4.5 x 8.5 | 2500 |
| olive-sunleaf | gnarled wide tree | **procedural** | tree | 6 x 6 | 3000 |
| great-sun-oak | lone golden oak | **procedural** | landmark | 16 x 16 | 8000 |
| limestone-pebbles | stone cluster | mesh | clutter | 0.9 | 400 |
| limestone-outcrop | layered slabs | mesh | bush | 4 x 1.8 | 1500 |
| dawn-crystal-cluster | **mana crystal** | **shared crystal** (3a) | crystal | 1.4 x 1.5 | 1200 |
| sunspire-crystal | **mana crystal spire** + light | **shared crystal** (3a) | landmark | 1.6 x 4.5 | 1500 |
| puffball-cluster | fungus | mesh | clutter | 0.7 | 800 |

The White flowers are gold, amber and cornflower blue **on purpose**: white petals on a
white keying backdrop are the one thing the card keyer cannot separate (see
`docs/GRASS_ATLAS_PROMPTS.md`, "Pale blades fringe").

### Blue - Islands (15)

Coast, tide, wet stone: teal, sea blue, slate, sand.

| Asset | Kind | Route | Tier | Size | Tris |
|---|---|---|---|---|---|
| sea-grass | grass | card (existing) | ground cover | 0.9 | - |
| sea-lavender | sea holly / lavender | card | ground cover | 0.7 | - |
| dune-reeds | tall reeds | card | tall cover | 1.2 x 1.7 | - |
| sea-holly-bush | spiky bush | **procedural** | bush | 1.4 x 1.1 | 900 |
| tide-hydrangea | flowering shrub | **procedural** | bush | 1.6 x 1.2 | 1100 |
| windswept-pine | wind-bent pine | **procedural** | tree | 6 x 9 | 3000 |
| mangrove | stilt-root tree, may stand in water | **procedural** | tree | 6 x 7 | 3500 |
| sea-stack-arch | rock arch with pine | mesh (standard) | landmark | 12 x 15 | 7000 |
| beach-pebbles | stone cluster | mesh | clutter | 0.9 | 400 |
| basalt-columns | hexagonal columns | mesh | bush | 4 x 2.2 | 2000 |
| sapphire-geode | **mana crystal** geode | **shared crystal** (3a) | crystal | 1.6 x 1.2 | 1500 |
| tide-crystal-spires | **mana crystal spires** + light | **shared crystal** (3a) | crystal | 1.8 x 3 | 1500 |
| lantern-caps | glowing fungus | mesh | clutter | 0.8 x 0.7 | 900 |
| driftwood | driftwood log | mesh | bush | 4 x 0.9 | 1200 |
| giant-clam | clam shell | mesh | clutter | 1.1 x 0.6 | 900 |

### Black - Swamp (15)

Decay, black water, mist: charcoal, aubergine, olive, violet glow.

| Asset | Kind | Route | Tier | Size | Tris |
|---|---|---|---|---|---|
| swamp-grass | grass | card (existing) | ground cover | 0.9 | - |
| nightshade | flowers | card | ground cover | 0.7 | - |
| bog-cattails | tall reeds | card | tall cover | 1.2 x 1.8 | - |
| thorn-bramble | thorny bush | **procedural** | bush | 1.8 x 1.3 | 1200 |
| weeping-willow | drooping tree | **procedural** | tree | 8 x 9 | 4000 |
| swamp-cypress | cypress with knees, may stand in water | **procedural** | tree | 6 x 11 | 3500 |
| dead-snag | dead leaning tree | mesh | tree | 4 x 7 | 1500 |
| slate-shards | stone cluster | mesh | clutter | 0.9 | 500 |
| bog-stones | half-sunk boulders | mesh | bush | 2.5 x 1.2 | 1200 |
| void-amethyst | **mana crystal** | **shared crystal** (3a) | crystal | 1.4 x 1.5 | 1200 |
| rootbound-obelisk | **mana crystal obelisk** + light | **shared crystal** (3a) | landmark | 1.6 x 4.5 | 1600 |
| witch-toadstools | glowing fungus | mesh | clutter | 0.9 x 1.2 | 1000 |
| bracket-log | log with shelf fungus | mesh | bush | 3 x 0.9 | 1800 |
| spore-pods | giant glowing pods | mesh | crystal | 2.2 x 2.5 | 2500 |
| bog-lilies | lily pads, **water only** | mesh | clutter | 1.6 x 0.25 | 600 |

### Red - Mountains (15)

Lava, ash, ember: basalt black, rust, ember orange, sulphur.

| Asset | Kind | Route | Tier | Size | Tris |
|---|---|---|---|---|---|
| ash-grass | grass | card (existing) | ground cover | 0.9 | - |
| ember-flowers | flame flowers | card | ground cover | 0.7 | - |
| scorched-reeds | tall reeds | card | tall cover | 1.1 x 1.5 | - |
| ember-thornbush | burning-leaf bush | **procedural** | bush | 1.6 x 1.3 | 1000 |
| fire-succulent | agave rosette | mesh | clutter | 1 x 0.8 | 800 |
| dragonblood-tree | umbrella tree | **procedural** | tree | 7 x 8 | 3500 |
| charred-pine | burnt pine, ember seams | **existing** (your Meshy burned trees, import later) | tree | 3.5 x 9 | - |
| fireheart-tree | molten-vein giant | **procedural** | landmark | 14 x 15 | 8000 |
| lava-pebbles | stone cluster | mesh | clutter | 0.9 | 400 |
| pillow-lava | cooled lava mound | mesh | bush | 3 x 1.4 | 1500 |
| sandstone-mesa | layered block | mesh | landmark | 6 x 5 | 2500 |
| ruby-crystals | **mana crystal** | **shared crystal** (3a) | crystal | 1.4 | 1200 |
| magma-spire | **mana crystal spire** + light | **shared crystal** (3a) | landmark | 1.6 x 4.5 | 1500 |
| ember-caps | glowing fungus on wood | mesh | clutter | 0.8 x 0.5 | 900 |
| sulfur-vent | sulphur-crusted vent | mesh | bush | 2 x 1 | 1200 |

### Green - Forest (15)

Old growth, moss: deep greens, bark, mushroom red and cream, emerald glow.

| Asset | Kind | Route | Tier | Size | Tris |
|---|---|---|---|---|---|
| forest-grass | grass | card (existing) | ground cover | 0.9 | - |
| clover-flowers | clover + flowers | card | ground cover | 0.6 | - |
| ferns | ferns | card | tall cover | 1.3 x 1.1 | - |
| round-bush | leafy bush | **procedural** | bush | 1.8 x 1.4 | 1000 |
| berry-bush | berry bush | **procedural** | bush | 1.6 x 1.3 | 1100 |
| broad-oak | spreading oak | **procedural** | tree | 10 x 12 | 4000 |
| tall-fir | conical fir | **procedural** | tree | 5 x 14 | 2500 |
| sapling | young tree | **procedural** | bush | 1.6 x 3 | 900 |
| river-stones | mossy stone cluster | mesh | clutter | 0.9 | 400 |
| rootbound-rock | root-gripped boulder | mesh | bush | 3 x 2.2 | 1800 |
| emerald-root-crystals | **mana crystal** | **shared crystal** (3a) | crystal | 1.4 | 1200 |
| verdant-spire | **mana crystal spire** + light | **shared crystal** (3a) | landmark | 1.6 x 4.5 | 1500 |
| toadstool-cluster | red-cap fungus | mesh | clutter | 0.8 x 0.6 | 900 |
| giant-mushroom | glowing giant mushroom | mesh | landmark | 6 x 7 | 3000 |
| mossy-stump | cut stump | mesh | clutter | 1.2 x 0.8 | 1000 |

**Totals (revision 2):**

- **Meshy:** 27 per-biome meshes plus 4 shared crystal shapes, 31 in all (plus your existing burned trees for the charred pine).
- **Procedural:** 20 species (12 trees, 8 bushes), several seeded variants each.
- **Cards:** 15 assets, 5 of them the existing grass sheets.
- **Crystal objects:** 10 per-biome entries in the game, built from those 4 shapes.

The per-biome crystal rows above stay as the list of what each biome gets. They no
longer each need their own model.

---

## 3a. Mana crystals: one white set, tinted per biome

Yes, and it is the better design, not just the cheaper one. Generate the crystals
once, colourless, and give each biome its colour in the shader.

**The four shapes** (Meshy t2, generated once):

| Shape | Tier | Size (m) | Tris | Used as |
|---|---|---|---|---|
| `crystal-shard-cluster` | clutter | 0.8 x 0.7 | 600 | small shards in the grass |
| `crystal-cluster` | crystal | 1.4 x 1.5 | 1200 | the main cluster in every biome |
| `crystal-geode` | crystal | 1.6 x 1.2 | 1500 | a split boulder lined with crystals |
| `crystal-spire` | landmark | 1.6 x 4.5 | 1500 | the tall spire, with its light |

**Prompt rule:**

- Ask for clear, colourless, milky-white quartz with soft grey internal shading.
- Ask for **no colour tint anywhere**: no glow, no base, the crystals rising straight out of an invisible ground.
- Leaving the rock base off is what makes recolouring clean. A tint shader can't tell crystal from stone when both are in one texture.
- The geode is the exception: its rock shell is mid-grey and its crystals near-white, so a brightness mask separates them.
- Biome character comes from what is scattered around the crystal (limestone, basalt, roots), not from a baked-in base.

**Recolouring:** a new `assets/shaders/mana_crystal.gdshader`.

- **Albedo:** the white texture's brightness times the biome tint. The facets and internal shading Meshy painted survive; only the hue changes.
- **Emission:** the tint, strongest where the crystal is brightest, plus a fresnel rim. This replaces the albedo-driven glow of revision 1, which lit the rock base too.
- **One material per biome:** five materials from one shader, tints taken from `crystal_glow` in the manifest.
- **In TerraBrush:** each biome's crystal is its own ObjectResource pointing at the same mesh with that biome's material, via the `materialOverride` slot on `ObjectOctreeLODMeshDefinitionResource`. One mesh in memory, five looks.
- **Spires** keep the PackedScenes wrapper for their OmniLight, which takes the tint from the same colour.

**What it buys:**

- 10 crystal models become 4, about 150 credits down to about 60.
- Colours stay tunable at any time, for free, including for Sky3D's night.
- The same crystals become available to anything else that wants a mana colour (pickups, spell props, a multicolour crystal on a guild camp).
- Decor crystals can be kept visibly dimmer than the mana wells (section 9) with one number.

**Could the same trick cover the rocks?** Partly. A neutral "stone kit" could be
generated once and given a biome-specific top layer in the shader: moss for Green,
ash for Red, salt crust for Blue, lichen for Black, sun-bleach for White. Pebbles and
boulders would carry it well. The outcrop, basalt columns, mesa and pillow lava are
shape-specific and should stay per biome. This is optional; decide after the crystal
shader has proven the approach.

---

## 3b. Trees and bushes: Blender instead of Meshy

**Is Meshy good for trees? Not for leafy ones, and your experience is the usual result.**

- **Mushy canopies:** image-to-3D reconstructs a canopy as one closed shell, so the leaves melt into a lumpy blob with smeared texture.
- **Fused branches:** thin branches merge or vanish.
- **Wasted triangles:** much of the budget goes on the hidden inside of the canopy.
- **Nothing to sway:** no alpha leaf cards and no separate leaf part, so nothing wind can move.

Meshy (and Tripo, Rodin or Hunyuan3D, which share the method) is fine for solid
lumps: **stumps, logs, driftwood, the dead snag, the charred pine, mushrooms and
rocks.** Those stay on Meshy. Every tree and bush with leaves moves to Blender.

**Options compared:**

| Tool | Cost | Automatable | Fit |
|---|---|---|---|
| **Blender Geometry Nodes, own recipes** | free | yes, `blender -b -P` | **Recommended.** Full control of the stylized look, any number of variants from one seed, fully headless |
| Free GN generators (e.g. RC12's stylized tree generator, IRCSS's low-poly trees) | free | yes, as the starting node group | Good starting point for the recipes instead of building nodes from zero |
| TreeDesigner / Stylized Tree Asset Generator (Superhive) | paid, one-off | yes | Polished stylized presets; worth it if the free route stalls |
| EZ-Tree (MIT, three.js, npm `@dgreenheck/ez-tree`) | free | yes, Node | Quick to automate and exports GLB with alpha-card leaves, but leans realistic; less stylized control than Blender |
| SpeedTree | subscription | partly | Industry standard, but overkill and GUI-bound for 20 stylized species |
| Meshy | credits | yes | Only for the bare and dead trees (above) |

**The recommended route:**

1. **One recipe per species.** A Geometry Nodes recipe stored as `tools/nature/blender/species/<id>.json` (seed, height, trunk taper, branch levels and angles, gnarl, canopy layout, leaf density), plus a shared node library in `tools/nature/blender/nature_trees.blend`.
2. **Two canopy styles, chosen per species.** With the semi-realistic art direction, card
   canopies are the default; faceted ones only where a species reads better solid:
   - **Faceted:** low-poly clumps, flat shaded, no alpha. Cheapest, and it matches the faceted low-poly look of the arena (boxwood, hydrangea, oak, fir).
   - **Card canopy:** alpha leaf-cluster cards on the branch tips. Fuller and softer, and it sways (willow, birch, cypress moss, mangrove).
   - Pilot both on the Green oak and fir before committing the other 18.
3. **Headless build.** `blender -b tools/nature/blender/nature_trees.blend -P tools/nature/blender/build_trees.py -- --only <id>` does the following:
   - generates 3-4 seeded variants per species;
   - realizes the geometry and assigns bark and leaf materials;
   - writes a wind mask (vertex colour: 0 at the trunk base, 1 at leaf tips);
   - exports `assets/generated/<id>/<id>_v<n>.glb`, the same folder Meshy assets use.
4. **Into the game unchanged.** `tools/build_nature_terrabrush.gd` already bakes, scales and LODs anything in that folder. Leaf cards arrive as glTF alpha-mask materials, which Godot imports with alpha scissor.
5. **New tree material.** `assets/shaders/nature_tree.gdshader` adds wind sway driven by the vertex-colour mask, and the same back-face normal fix as the foliage cards.

**Status (2026-10-04): all 11 trees with ready textures are built.** The trees are birch, olive, great sun oak, windswept pine, mangrove, willow, cypress, dragonblood, fireheart, broad oak and fir. They are 1,500-9,000 triangles each; the landmarks and the oak and fir are the heavy ones. The 9 bushes still need recipes. All 20 species are marked `"route": "procedural"` in the manifest, so the Meshy stage can never pick them up.

The generator now also does wind bias (pine), hanging cards (willow strands, cypress moss), stilt roots (mangrove), knees (cypress), upward rosettes and exact forks (dragonblood), and several leaf sets per tree.

**Earlier (same day): first two species.**

The generator is `tools/nature/blender/build_trees.py`, run headless in Blender 5.2 (`G:/Program Files/Blender Foundation/Blender 5.2`). It is written as Python/bmesh rather than Geometry Nodes: every number lives in the recipe JSON (`tools/nature/blender/species/<id>.json`), the same seed gives the same tree, and it diffs cleanly.

| Species | Triangles | Leaves |
|---|---|---|
| Green broad oak | ~7,500 | the golden sun-oak sheet, hue-shifted green in the recipe (no new images) |
| Green tall fir | ~9,000 | windswept-pine needles, retinted |

Both are above the 4,000 / 2,500 triangle targets; trim the card counts once they are judged in game.

In Godot, every alpha-cut leaf material is swapped for `assets/shaders/nature_leaves.gdshader`. It does three things:

- keeps back-face normals (otherwise half the crown goes black);
- sways by the wind weight baked into vertex colour R;
- lets light show through the leaves.

Blender MCP (`mcp-for-blender`) is installed and enabled in Blender 5.2 and registered in `.mcp.json`. It is for tuning recipes interactively; production stays the headless script.

**Cost:** zero credits for geometry. Only the leaf and bark textures cost Gemini images
(about 2-3 per species, section 3c). Recipes take authoring time up front; that is
what Blender MCP is for (3d).

---

## 3c. Textures

| Texture | Tool | How |
|---|---|---|
| Leaf clusters (card canopies, bushes) | **Gemini 3 Pro Image** | 2x2 sheet of leaf clusters on pure white, keyed by `tools/alpha_key.gd`, exactly like the grass. Packed into one atlas per species |
| Bark | **Gemini 3 Pro Image** | Prompt for a seamless tileable bark swatch in the hand-painted style. A new free `pick` gate checks seams by offsetting the image half a tile. Normal and roughness are derived in Blender (bake from a height pass) |
| Faceted canopies | none | Vertex colour gradients baked in Blender (dark inside, light on top, biome palette), no texture at all, so one material per species |
| Rocks, crystals, fungus | Meshy t2 | Unchanged: Meshy textures from the reference image |
| PBR from a single image, if needed | **Material Maker** (free, open source, built on Godot) | Height, normal and roughness from an albedo, for any Gemini texture that needs more than flat colour |

Also considered:

- **Meshy Retexture** (`POST /openapi/v1/retexture`, about 10 credits, keeps your UVs with `enable_original_uv`) can paint a texture onto a Blender-made mesh from text or an image. It is useful for a hero trunk or stump, but it can't produce alpha leaf cards, so it is no replacement for the above.
- **Substance 3D Sampler** (paid) is the strongest "photo to material" tool if the free route ever falls short.

---

## 3d. Blender MCP

[Blender MCP](https://github.com/ahujasid/blender-mcp) (community, MIT) connects Claude
to a running Blender through an addon. Its tools include `execute_blender_code`, scene
inspection and viewport screenshots, plus Poly Haven, Sketchfab and Poly Pizza
downloads and Rodin and Hunyuan3D generation, which we don't need.

**How it fits:**

- **Authoring, not production.** Use it to iterate on a species with you watching ("thicker trunk, lower first branch, more lean"). Once a species looks right, its parameters are frozen into the recipe JSON.
- **Production stays headless and reproducible.** `blender -b -P build_trees.py` needs no MCP, no running UI, and gives the same tree from the same seed every time.

**Setup (not done yet, needs your OK because it installs software):**

1. Install `uv` (not on this machine yet).
2. Install the Blender addon (`uvx mcp-for-blender install-addon` per the current README), then enable it in Blender 4.3 preferences.
3. Register the server with Claude Code.
4. Start the addon's server from Blender's side panel.

**Caution:** `execute_blender_code` runs arbitrary Python inside Blender. Keep it local,
save before each session, and keep the `.blend` under git.

---

## 4. Prompt design

Both prompt types are assembled in `nature_pipeline.py` from three parts: the asset's
own `subject` + `details`, the biome's `mood` + `palette`, and a fixed block of
constraints. Shared wording is the consistency lever (as `docs/BIOME_ASSETS.md` found
for Meshy), so keep edits to the asset clauses.

**Mesh reference images:** one object; **semi-realistic** (believable materials and
surface detail, slightly rich colour, explicitly not cartoon, low-poly or hand-painted -
the art direction since 2026-10-04); three-quarter view from slightly above; full margin on every side; flat mid-grey
background with no floor and no shadow; even neutral light; no glow halo. Each clause
blocks a known way image-to-3D fails:

- **Cropped edge:** becomes a flat cut in the mesh.
- **Cast shadow:** gets reconstructed as a slab under the model.
- **Halo:** gets baked into the texture as a fog shell.
- **Grey background, not white:** the White biome's limestone and quartz must not melt into it.

**No style reference images for now.** The mana-well renders were tried as references
and rejected (2026-10-04): they don't look good enough to copy. Any group can get one later
via an `anchor` path in the manifest; a strong candidate is the first image you approve in
each biome, once it exists, so the rest of that biome follows it.

**Card sheets:** the grass rules unchanged. 2x2 grid on pure #FFFFFF; bold broad shapes;
saturated colour; nothing pale; nothing crossing a midline.

---

## 5. The automated workflow

```
nature_assets.json
   |  prompts  ->  docs/NATURE_PROMPTS.md                          (free)
   |  concept  ->  Gemini, 2 variants/asset                         (paid, --go)
   |  pick     ->  automatic quality gates suggest a variant,
   |               review page                                      (free)
   |  approve  ->  YOU approve each mesh reference image            (manual gate)
   |  mesh     ->  Meshy image-to-3D (t2), approved images only     (paid, --go, --max-credits)
   |  build    ->  Godot: key cards, --import, bake meshes,
   |               TerraBrush resources, scatter masks              (free)
   |  apply    ->  scenes/misc/main.tscn                            (free)
   v  validate ->  ./tools/validate_godot.ps1
```

Per biome, the rhythm is two sittings:

```bash
python tools/nature/nature_pipeline.py concept --go --biome green
python tools/nature/nature_pipeline.py pick --biome green
```

Review `assets/nature/_concepts/index.html`, then approve or reject:

```bash
python tools/nature/nature_pipeline.py approve nature-green-river-stones:v2 nature-green-mossy-stump
```

```bash
python tools/nature/nature_pipeline.py reject nature-green-toadstool-cluster
```

Then build only what you approved:

```bash
python tools/nature/nature_pipeline.py mesh --go --biome green --max-credits 150
```

`run --go` chains every stage, but its `mesh` step still only takes images approved
before the run. Anything new waits on the review page.

**Safety rails**

- **Nothing reaches Meshy unless you approved its reference image.**
  - `approve` records the file and its SHA-256, and `mesh` re-checks the hash before sending.
  - An image regenerated or edited after approval (even one pixel) needs approving again.
  - Verified offline: unapproved -> not queued; approved -> queued; one pixel changed -> blocked.
- `concept`, `mesh` and `run` are dry runs without `--go`: they print the exact request and spend nothing.
- `mesh` stops before passing `--max-credits` (default 200).
- Resumable: existing images and GLBs are never re-bought, and a submitted Meshy task is resumed from its saved id rather than paid for twice.
- Keys come only from `GEMINI_API_KEY` / `MESHY_API_KEY` in the environment.
- `status` shows what's missing and the credits still to spend.

**Automatic quality gates (`pick`)** reject the failures that waste Meshy credits:

- Mesh concepts must have a flat, non-gradient background, an object that doesn't touch the frame, and a fill of 10-85% of the frame.
- Card sheets must have white corners, one plant per quarter, and nothing crossing a midline.

The gates only **suggest**: the best passing variant gets a yellow border on the review
page. If none passes, the page says so; `reject` and generate again.

**The review page** (`assets/nature/_concepts/index.html`) shows, per asset:

- the prompt subject;
- every variant with its gate result;
- the copyable `approve <id>:vN` and `reject <id>` commands.

Approved images get a green border. `approve <id>` with no variant takes the
suggestion. You can also just tell Claude which ones to approve in chat.

Card sheets (Gemini only, no Meshy credits) still feed `build` from the suggestion, and
can be approved the same way if you want the same control there.

The gates were checked against real inputs:

- The five mana-well renders (used here only as test images) pass, and a deliberately cropped one fails.
- Four of the five existing grass sheets pass. The green sheet fails because 17 pixels of blade cross its vertical midline, so `build_grass_billboards.gd` has been slicing a few green blades in half all along. Regenerate that sheet when convenient.

Outputs:

- Meshy results keep the house rule: `assets/generated/<id>/` with the GLB, preview, concept and `.meshy.json` provenance.
- Concept art lives in `assets/nature/_concepts/`, behind a `.gdignore`.

---

## 6. TerraBrush integration

How TerraBrush stores this, read from its source (spimort/TerraBrush) and checked
against this map:

- Each foliage or object entry on the node pairs **by index** with one RGBA8 image per
  zone (`ZoneResource.foliagesImage[i]` / `objectsImage[i]`).
- The single 512 m zone is **centred on the origin**: pixel (x, y) = world (x - 256,
  y - 256). Verified: the heightmap's peak at pixel (87, 447) is world (-169, 191),
  inside the Red wedge, where the volcano is.
- **Objects** spawn at every pixel whose alpha > 0 *and* whose x and y are both
  multiples of `objectFrequency`, jittered by `randomRange`.
- **Foliage** shows where red > 0, scaled by alpha.

What the builder makes:

| Thing | Resource | Strategy |
|---|---|---|
| Card layer (per biome x low/tall) | `FoliageResource`, all tiles in one Texture2DArray, tiles repeated by `weight` | MultiMesh, `nature_foliage.gdshader` |
| Mesh asset | `ObjectResource` | **OctreeMultiMeshes** with a near LOD (shadows, collision) and a far LOD (no shadows). Crystals with a light use **PackedScenes**, because a MultiMesh can't carry an OmniLight |
| Every mesh asset | `assets/nature/scenes/<id>.tscn` wrapper | For hand placement too |

Meshes are re-measured, not trusted. Meshy's `auto_size` is a fixed box normalisation
and its bottom origin doesn't always hold (both in `.agents/learnings.md`). So every
surface is baked into one mesh at the manifest size, base on y = 0, centred, with
automatic LODs from `ImporterMesh.generate_lods`.

**Scatter rules (`_paint_objects` / `_paint_foliage`):**

- **Biome:** nearest lane angle, with the border pushed around by noise (+-9 degrees) so the wedges interlock instead of meeting on a ruler line.
- **Radius band per tier.** Nothing on the central plateau (< 48 m). Landmarks only in the outer ring (130-250 m).
- **Slope limit per tier, from the heightmap.** Trees stop at 32 degrees, stones go to 50.
- **Water:** off by default. `allow` for mangrove and cypress; `only` for the lily pads.
- **Lane corridor:** blocking tiers (trees, landmarks) keep out of a 15 m half-width strip along every lane's centre line, and nothing grows within 10 m of a mana well.
- **No overlap:** the biggest assets are placed first and claim their footprint, so a bush never spawns inside a trunk.
- **Clumping:** density times per-asset clump noise, seeded by asset id, so results are deterministic.

The masks are ordinary TerraBrush zone images (`scenes/misc/Main/Nature_<name>.res`),
so after generation you can **touch them up with TerraBrush's own brushes**.
`build --no-scatter` keeps hand-painted masks intact.

**`apply`** edits `main.tscn` as text: two ext_resource lines per entry plus the four
array lines, so the diff stays small. It is idempotent, and it refuses to
run if the node already has hand-made foliage or objects (index pairing would break).
**Close `main.tscn` in the editor first**, or the editor's stale copy will overwrite it.

**Tested end to end without spending anything.** An existing pillar GLB stood in for a
Meshy result and the green grass sheet for a card. Results:

- `build` -> `apply` -> `validate_godot.ps1` passed in full.
- Perf probe: the grass layer plus 86 rocks cost under 1 ms per frame on the RTX 2070S.
- The test exposed, and fixed, two problems that would have hit every card:
  - TerraBrush's stock foliage shader cuts alpha at 0.01, not the keyer's 0.3, which would draw every halo.
  - Back faces of the crossed cards rendered black, because Godot flips the normal on a back face.

---

## 7. Budget

| | Estimate |
|---|---|
| Meshy (revision 2) | 30 x ~15 credits (t2 + texture) + 1 x ~30 (sea stack) = **~480 credits**, down from ~915 (the charred pine comes from your existing burned trees). The 4 shared crystals alone are ~60 |
| Meshy, Green pilot | rocks, fungus, stump and the shared crystals: 9 meshes = **~135** |
| Gemini | ~48 concept/card assets x 2 variants, plus ~2-3 leaf/bark textures per procedural species (~50). Check current Google pricing; iterate with `--draft` |
| Blender | free; authoring time per species instead of credits |
| Triangles | Clutter 400-1000, bushes 900-2000, trees 1500-4000, landmarks <= 8000 |
| Materials | One per mesh asset (58). Clutter in one biome could later share an atlas; not needed for TerraBrush MultiMesh, which batches per asset anyway |
| Card VRAM | ~70 tiles at 512 px, BPTC-compressed with mipmaps, roughly 25 MB |

Meshy's credit numbers come from its pricing page (image-to-3D with texture: 15-30).
Confirm on the dashboard before the first paid run.

---

## 8. Phases

0. **Free (done):** manifest, prompts, pipeline, builders, foliage shader, end-to-end test with stand-ins.
1. **Implement revision 2 (free):** the tasks in section 10.
2. **Green pilot.** Green exercises every route: cards, procedural oak, fir and bushes, Meshy rocks and fungus, and the shared crystals in all five tints.
   - Author the oak and fir in Blender with MCP, in both canopy styles, and pick one.
   - `concept --biome green --draft` to tune prompts, then Pro.
   - `mesh --go --biome green --max-credits 150`.
   - Then `build`, `apply`, and judge in the perf probe and a real match.
3. **Tune** spacing, density, corridor width and crystal tints in the manifest, rebuild for free.
4. **White, Blue, Black, Red**, one biome per run: their species recipes first, then their Meshy assets.
5. **Polish:**
   - The optional stone kit with biome top layers (3a).
   - Alpha-coverage-preserving mipmaps for cards and leaves.
   - Check every glow reads at night under Sky3D.

## 9. Decisions and risks to settle before Phase 1

- **Decor crystals vs. economy.** Mana is harvested from the wells. Ten kinds of glowing
  crystal in the same colours could read as harvestable. Options: keep decor crystals
  visibly smaller and dimmer than wells (current plan), or make some of them real mana
  nodes later (a design change for `docs/ECONOMY.md`).
- **Navigation.** The navmesh is baked from the terrain and the stone rings only, so
  TerraBrush objects are invisible to it. The corridor rule keeps blocking objects off
  the paths, but an enemy that strays off-corridor will walk through trunk colliders.
  If that shows, the trees join the `navmesh_source` group via their wrapper scenes.
- **Collision layer of OctreeMultiMesh objects.** This TerraBrush build has no
  per-definition collision layer property (newer upstream versions do). Which layer
  its octree colliders land on is **unverified**; check before relying on tree
  collision. Wrapper scenes (PackedScenes) use layer 16 (Environment) explicitly.
- **Texture array per foliage layer** needs identical tile sizes. The card builder pads
  every tile to 512x512, which is why it does not reuse the grass builder's
  crop-to-bounds tiles in `assets/foliage/grass/`. Those stay unused until removed.

---

## 10. Implementation tasks for revision 2

Nothing below spends credits.

1. **Manifest.**
   - Add the 4 shared crystal shapes, with a `tint_biomes` list.
   - Turn the 10 per-biome crystal entries into placements of those shapes (biome, tier, scatter) without their own prompt.
   - Set the 20 leafy species to `"route": "procedural"` with a `canopy` field (`faceted` / `cards`).
   - Add a `textures` list per species (leaf sheet, bark).
   - Drop the pine from the sea-stack prompt.
2. **Pipeline (`nature_pipeline.py`).**
   - A `trees` stage that runs Blender headless.
   - Card-style generation for leaf sheets, and a tileable-bark prompt with a seam gate in `pick`.
   - `prompts` regenerates `docs/NATURE_PROMPTS.md` with all of the above.
3. **Blender.** `tools/nature/blender/nature_trees.blend` (node library), `build_trees.py`, and the first two recipes (Green oak and fir).
4. **Godot.**
   - `mana_crystal.gdshader` and the per-biome material override in `build_nature_terrabrush.gd`.
   - `nature_tree.gdshader` (wind from vertex colour, back-face normal fix).
   - Multiple seeded variants per species as separate objects, or as several meshes in one LOD entry.
5. **Blender MCP setup** (3d), after your OK.
