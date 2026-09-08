# Biome Prop Assets

Generation spec for the scattered set dressing in the five lane wedges. Every entry
here is a Meshy text-to-3D request; nothing in this file has been generated yet.

Companion to `docs/AI_WORKSPACE.md`, which covers the key setup, the pipeline and the
post-generation import checklist. This file is only the *what* and the *prompts*.

## Arena context

The five lane wedges (`NavigationRegion3D/Lanes/Lane_*/Geometry` in
`scenes/misc/main.tscn`) run from radius ~40 out to ~184, roughly 144 m long and
flaring from 59 m to 268 m wide. The mana well sits at radius ~113, the enemy spawner
at ~179. `player_camera_distance` is 3.2, so props are read both close up and against
the horizon.

Each lane therefore gets props across four distance bands:

| Role | Typical size | Purpose |
|---|---|---|
| Ground clutter | 0.8-1.5 m | Dense scatter, breaks up the ground plane underfoot |
| Ground detail | 3-8 m | Flat spreading pieces that sit into the terrain |
| Midground | 2-6 m | Medium density, gives the lane depth |
| Landmark | 8-20 m | Sparse, breaks the horizon near the spawner |

## Generation settings

Defaults come from `tools/meshy_asset.ps1` and do not need to be passed:

- `-ModelType smart-topology` - Meshy's `meshy-t2`, builds directly at the requested
  face count with triangle output and natively separated parts
- `target_formats: glb`, `auto_size: true`, `origin_at: bottom`, `moderation: true`
- Refine stage adds `enable_pbr: true` and `remove_lighting: true`

Per asset, pass name, prompt, texture prompt and polycount:

```powershell
./tools/meshy_asset.ps1 -Name "biome-green-mossy-boulder" -Prompt "<Prompt from below>" -TexturePrompt "<Texture prompt from below>" -TargetPolycount 1200 -DryRun
```

Drop `-DryRun` to spend credits. Use `-PreviewOnly` to judge geometry before paying
for refinement. Output lands in `assets/generated/<name>/` with a preview PNG and a
`.meshy.json` provenance manifest.

## Prompt formula

Every prompt below follows the scaffolding already used by the five mana wells (see
any `assets/structures/mana-well-*/*.meshy.json`), because reusing that exact string
shape is the main lever on cross-asset style consistency:

> Single isolated low-poly fantasy \<subject\>, \<colour\>-aligned \<theme\> design,
> \<specific detail clause\>, \<silhouette clause\>, game prop approximately \<W\>
> meters wide and \<H\> meters tall, no characters, no text, no symbols from existing
> franchises, no ground plane, no environment

The words "low-poly" stay in the prompt even though `model_type` is no longer
`lowpoly`. There it is a *style* descriptor driving the faceted look that matches the
existing arena assets; topology is controlled separately by `-TargetPolycount`.

## Scope caveats

**No foliage from Meshy.** Grass, ferns, reeds and leaf canopies are deliberately
absent from this list. Meshy will bill for a 1500-tri clump of leaves that renders
worse than an alpha-card billboard.

Grass is already handled separately: `tools/build_grass_billboards.gd` keys the 2x2
source sheets in `assets/foliage/grass/source/` into 20 alpha-cutout billboards, four
per biome, and `scripts/grass_scatter.gd` scatters them across each lane wedge as
MultiMeshes. Remaining foliage should follow that route rather than this one.

**Craters are rims, not holes.** Every Meshy prop returns as a closed mesh with
`origin_at: bottom`, so a generated crater sits on the ground like a bowl. The three
red-lane impact pieces are specced as *rims* and *ejecta* meant to be laid over a
depression sculpted into the terrain heightmap. On the current flat `CSGPolygon3D`
wedges they will read wrong - generate them after the terrain work, not before.

**Crates are the weakest value.** Crates and barrels are near-primitive box and
cylinder geometry, and generation gives slightly wobbly non-planar faces where a
hand-made or kitbashed crate would be crisp and free. Included for look consistency;
the first category to cut if credits are tight.

**Materials, not triangles, are the budget.** Each refine produces its own PBR texture
set, so 40 assets means 40 materials. Prefer rotation and scale variance over new
props, and consider atlasing the ground-clutter tier before it feeds a MultiMesh.

---

## White - Plains

Order, sun-bleached stone, harvest, supply lines. Ground texture in play:
`assets/textures/plains2/gravel_ground_01`.

| `-Name` | Role | Polys | Size | Density |
|---|---|---|---|---|
| `biome-white-boundary-stone` | Ground clutter | 1200 | 0.8 m | High |
| `biome-white-hay-bale-cluster` | Midground | 3000 | 2.5 m | Medium |
| `biome-white-broken-fence-run` | Midground | 2500 | 4 m | Medium |
| `biome-white-ruined-marble-arch` | Landmark | 9000 | 14 m | 2-3 per lane |
| `biome-white-single-crate` | Ground clutter | 900 | 1 m | High |
| `biome-white-crate-stack` | Midground | 2500 | 2.5 m | Medium |
| `biome-white-barrel-cluster` | Midground | 2000 | 1.8 m | Medium |
| `biome-white-supply-wagon` | Landmark | 6000 | 5 m | 2-3 per lane |

#### `biome-white-boundary-stone`

```
Single isolated low-poly fantasy boundary marker stone, white-aligned orderly plains design, squat weathered limestone block with a chiseled flat top and a faint carved ring band, simple sturdy readable silhouette, game prop approximately 0.6 meters wide and 0.8 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Sun-bleached pale limestone, fine grit and lichen speckling, restrained warm highlights, game-ready PBR
```

#### `biome-white-hay-bale-cluster`

```
Single isolated low-poly fantasy hay bale cluster, white-aligned harvest plains design, three bound straw bales stacked at slight angles with rope ties and loose straw at the edges, compact readable silhouette, game prop approximately 3 meters wide and 2.5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dry golden straw, pale hemp rope, dusty sun-bleached tones, game-ready PBR
```

#### `biome-white-broken-fence-run`

```
Single isolated low-poly fantasy broken wooden fence run, white-aligned settled plains design, four weathered posts carrying two sagging cross rails with one snapped plank hanging loose, long horizontal readable silhouette, game prop approximately 4 meters wide and 1.2 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Grey weathered oak, split grain, rusted iron nails, muted pale palette, game-ready PBR
```

#### `biome-white-ruined-marble-arch`

```
Single isolated low-poly fantasy ruined marble arch, white-aligned fallen order design, tall freestanding ceremonial archway with one cracked pillar, a missing keystone and fluted column detail, imposing asymmetric readable silhouette, game prop approximately 10 meters wide and 14 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Cream white marble, grey veining, chipped edges, faint remnants of gold leaf, game-ready PBR
```

#### `biome-white-single-crate`

```
Single isolated low-poly fantasy wooden supply crate, white-aligned ordered garrison design, simple planked box with iron corner brackets and a lid sitting slightly ajar, crisp boxy readable silhouette, game prop approximately 1 meter wide and 0.9 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Light pine planking, dark iron banding, clean restrained wear, game-ready PBR
```

#### `biome-white-crate-stack`

```
Single isolated low-poly fantasy supply crate stack, white-aligned ordered garrison design, four planked crates in two sizes stacked slightly askew with rope lashing over the top, blocky stepped readable silhouette, game prop approximately 2 meters wide and 2.5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Light pine planking, dark iron banding, pale hemp rope, restrained wear, game-ready PBR
```

#### `biome-white-barrel-cluster`

```
Single isolated low-poly fantasy barrel cluster, white-aligned ordered garrison design, three banded wooden barrels with one upright, one tipped on its side and one half stacked, rounded readable silhouette, game prop approximately 2 meters wide and 1.8 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Warm oak staves, dark iron hoops, faint damp staining near the base, game-ready PBR
```

#### `biome-white-supply-wagon`

```
Single isolated low-poly fantasy supply wagon, white-aligned campaign caravan design, four wheeled cart with a bare canvas hood frame, a tilted axle and stacked crates in the bed, distinctive readable silhouette, game prop approximately 5 meters long and 3 meters tall, no characters, no animals, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Weathered oak frame, pale sun-faded canvas, iron rims, road dust, game-ready PBR
```

---

## Blue - Islands

Coast, tide, arcane study, leviathan remains.

| `-Name` | Role | Polys | Size | Density |
|---|---|---|---|---|
| `biome-blue-tidal-rock` | Ground clutter | 1000 | 1.2 m | High |
| `biome-blue-coral-kelp-clump` | Midground | 3000 | 2 m | Medium |
| `biome-blue-floating-monolith` | Midground | 2500 | 5 m | Low |
| `biome-blue-wrecked-ship-prow` | Landmark | 10000 | 16 m | 1-2 per lane |
| `biome-blue-leviathan-vertebra` | Ground clutter | 1200 | 1.5 m | High |
| `biome-blue-leviathan-fin-bones` | Midground | 2500 | 3 m | Medium |
| `biome-blue-leviathan-skull` | Midground | 8000 | 6 m | Low |
| `biome-blue-leviathan-ribcage` | Landmark | 11000 | 13 m | 1-2 per lane |

The four leviathan pieces are designed to compose into one implied skeleton running
down a lane - vertebrae scattered as a trail, fin bones and skull midway, ribcage as
the horizon piece - or to be reused independently.

#### `biome-blue-tidal-rock`

```
Single isolated low-poly fantasy tide-worn rock, blue-aligned coastal design, smooth rounded sea boulder with a barnacle crust and a wet shelf ledge, simple rounded readable silhouette, game prop approximately 1.2 meters wide and 0.9 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Wet blue-grey stone, pale barnacle crust, damp specular sheen, game-ready PBR
```

#### `biome-blue-coral-kelp-clump`

```
Single isolated low-poly fantasy coral and kelp clump, blue-aligned tidal design, branching stony coral fans with thick drying kelp fronds draped over the base, organic readable silhouette, game prop approximately 2 meters wide and 2 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Pale bleached coral, deep teal kelp, wet sheen, restrained cyan tint, game-ready PBR
```

#### `biome-blue-floating-monolith`

```
Single isolated low-poly fantasy arcane monolith, blue-aligned scholarly design, tall narrow slab of polished stone with carved geometric channels and a fractured top corner, clean vertical readable silhouette, game prop approximately 1.5 meters wide and 5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Polished blue-grey stone, inlaid silver channels, restrained cyan glow in the grooves, game-ready PBR
```

#### `biome-blue-wrecked-ship-prow`

```
Single isolated low-poly fantasy wrecked ship prow, blue-aligned drowned voyage design, splintered bow section of a wooden sailing vessel tilted at an angle with broken hull ribs and a snapped bowsprit, dramatic diagonal readable silhouette, game prop approximately 6 meters wide and 16 meters long, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Salt-bleached timber, tar seams, verdigris copper sheathing, kelp staining, game-ready PBR
```

#### `biome-blue-leviathan-vertebra`

```
Single isolated low-poly fantasy sea monster vertebra, blue-aligned leviathan remains design, single large weathered spinal bone with broad flat processes and a hollow central channel, chunky readable silhouette, game prop approximately 1.5 meters wide and 1.2 meters tall, no gore, no flesh, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Bleached bone, salt crust, faint algae staining in the crevices, game-ready PBR
```

#### `biome-blue-leviathan-fin-bones`

```
Single isolated low-poly fantasy sea monster fin bone fan, blue-aligned leviathan remains design, splayed array of long tapering fin rays joined at a heavy socket base with two rays snapped short, fanned readable silhouette, game prop approximately 3 meters wide and 2.5 meters tall, no gore, no flesh, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Bleached bone, salt crust, thin verdigris tide line, game-ready PBR
```

#### `biome-blue-leviathan-skull`

```
Single isolated low-poly fantasy sea monster skull, blue-aligned leviathan remains design, long tapering serpentine skull with a heavy jaw, empty eye sockets and rows of blunt conical teeth, one side partly collapsed, dramatic readable silhouette, game prop approximately 6 meters long and 3 meters tall, no gore, no flesh, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Bleached bone, salt crust, barnacle patches, faint teal algae staining, game-ready PBR
```

#### `biome-blue-leviathan-ribcage`

```
Single isolated low-poly fantasy sea monster ribcage, blue-aligned leviathan remains design, towering arch of paired curving ribs on a heavy spine section with several ribs snapped and one fallen inward, cathedral-like readable silhouette, game prop approximately 8 meters wide and 13 meters tall, no gore, no flesh, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Bleached bone, salt crust, hanging dried kelp, faint teal staining at the base, game-ready PBR
```

---

## Black - Swamp

Decay, charnel remains, tar, crypts.

| `-Name` | Role | Polys | Size | Density |
|---|---|---|---|---|
| `biome-black-bone-pile` | Ground clutter | 1200 | 1 m | High |
| `biome-black-dead-stump` | Midground | 2800 | 3 m | Medium |
| `biome-black-tar-pool-crust` | Ground detail | 1500 | 4 m | Medium |
| `biome-black-gallows-tree` | Landmark | 9000 | 15 m | 2-3 per lane |
| `biome-black-grave-marker-cluster` | Ground clutter | 1500 | 1.5 m | High |
| `biome-black-stone-sarcophagus` | Midground | 3000 | 2.5 m | Medium |
| `biome-black-iron-crypt-gate` | Midground | 2800 | 4 m | Low |
| `biome-black-crypt-entrance` | Landmark | 10000 | 8 m | 2-3 per lane |

Every black-lane prompt carries explicit `no gore, no bodies, no blood` clauses. Meshy
runs with `moderation: true` and these subjects sit closest to the line.

#### `biome-black-bone-pile`

```
Single isolated low-poly fantasy bone pile, black-aligned charnel design, heaped assortment of weathered animal long bones with a cracked skull fragment, loose mounded readable silhouette, game prop approximately 1.2 meters wide and 0.8 meters tall, no gore, no flesh, no blood, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dirty yellowed bone, swamp mud staining, dull matte finish, game-ready PBR
```

#### `biome-black-dead-stump`

```
Single isolated low-poly fantasy dead tree stump, black-aligned blighted swamp design, hollow splintered trunk broken off at head height with twisted exposed roots and a rotted cavity, gnarled asymmetric readable silhouette, game prop approximately 2 meters wide and 3 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Blackened rotting wood, damp fungal patches, sickly grey-green tint, game-ready PBR
```

#### `biome-black-tar-pool-crust`

```
Single isolated low-poly fantasy tar pool crust, black-aligned corrupted mire design, low flat irregular slab of hardened tar with a cracked glossy surface and a raised rippled rim, flat spreading readable silhouette, game prop approximately 4 meters wide and 0.3 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Glossy black tar, dull cracked crust, faint iridescent oil sheen, game-ready PBR
```

#### `biome-black-gallows-tree`

```
Single isolated low-poly fantasy dead gallows tree, black-aligned blighted swamp design, tall leafless twisted trunk with long reaching bare branches, hanging empty iron chains and a split hollow in the bole, ominous clawed readable silhouette, game prop approximately 9 meters wide and 15 meters tall, no gore, no bodies, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Blackened bark, rusted iron chain, damp grey rot, game-ready PBR
```

#### `biome-black-grave-marker-cluster`

```
Single isolated low-poly fantasy grave marker cluster, black-aligned forgotten burial design, three leaning weathered headstones of differing heights with blank chipped faces and moss at the base, uneven readable silhouette, game prop approximately 1.8 meters wide and 1.5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dark pitted stone, damp moss, grey-green swamp staining, game-ready PBR
```

#### `biome-black-stone-sarcophagus`

```
Single isolated low-poly fantasy stone sarcophagus, black-aligned crypt design, heavy rectangular coffin on a low plinth with its carved lid slid half open and cracked along one corner, solid blocky readable silhouette, game prop approximately 2.5 meters long and 1.2 meters tall, no gore, no bodies, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dark grey granite, chiselled relief edges, damp moss in the seams, game-ready PBR
```

#### `biome-black-iron-crypt-gate`

```
Single isolated low-poly fantasy iron crypt gate, black-aligned tomb design, freestanding pair of tall rusted iron gates in a narrow stone frame with one leaf hanging ajar on a broken hinge, vertical barred readable silhouette, game prop approximately 3 meters wide and 4 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Heavily rusted wrought iron, dark pitted stone frame, damp moss, game-ready PBR
```

#### `biome-black-crypt-entrance`

```
Single isolated low-poly fantasy crypt entrance, black-aligned tomb design, squat stone mausoleum facade with a recessed dark doorway, a cracked lintel, flanking pilasters and a partly collapsed roof corner, heavy readable silhouette, game prop approximately 6 meters wide and 8 meters tall, no gore, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dark weathered granite, damp moss, rust streaks, deep shadowed recess, game-ready PBR
```

---

## Red - Mountains

Volcanic rock, obsidian, impacts. Ground texture in play:
`assets/textures/mountains/cracked_red_ground`.

| `-Name` | Role | Polys | Size | Density |
|---|---|---|---|---|
| `biome-red-basalt-shard-cluster` | Ground clutter | 1000 | 1.5 m | High |
| `biome-red-scorched-boulder` | Midground | 2500 | 3.5 m | Medium |
| `biome-red-fissure-vent` | Ground detail | 2000 | 5 m | Low |
| `biome-red-obsidian-spire` | Landmark | 8000 | 18 m | 2-3 per lane |
| `biome-red-meteor-fragment` | Ground clutter | 1200 | 1.5 m | High |
| `biome-red-crater-rim-small` | Ground detail | 2000 | 3 m | Medium |
| `biome-red-crater-rim-large` | Ground detail | 3000 | 8 m | Low |
| `biome-red-smoldering-impact-site` | Landmark | 8000 | 12 m | 2-3 per lane |

The two crater rims are open rings with no floor, meant to sit over a terrain
depression. See the crater caveat above - generate these after the terrain step.

#### `biome-red-basalt-shard-cluster`

```
Single isolated low-poly fantasy basalt shard cluster, red-aligned volcanic design, group of three angular columnar rock shards of differing heights jutting at sharp angles from a common base, spiky readable silhouette, game prop approximately 1.5 meters wide and 1.4 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dark basalt, red-brown dust in the crevices, dry matte finish, game-ready PBR
```

#### `biome-red-scorched-boulder`

```
Single isolated low-poly fantasy scorched boulder, red-aligned volcanic design, large cracked rock with a blackened burnt face and deep fissures running through it, chunky rounded readable silhouette, game prop approximately 3.5 meters wide and 2.5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Cracked red-brown stone, soot blackening, faint ember glow deep in the fissures, game-ready PBR
```

#### `biome-red-fissure-vent`

```
Single isolated low-poly fantasy lava fissure vent, red-aligned volcanic design, long low split in slabbed rock with raised broken edges and a narrow deep channel running its length, flat elongated readable silhouette, game prop approximately 5 meters long and 0.6 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Charred black rock, cracked red crust, glowing molten channel, game-ready PBR
```

#### `biome-red-obsidian-spire`

```
Single isolated low-poly fantasy obsidian spire, red-aligned volcanic design, tall leaning shard of glassy black rock with sharp faceted planes and a fractured broken tip, dramatic angular readable silhouette, game prop approximately 4 meters wide and 18 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Glossy black obsidian, sharp conchoidal facets, faint red internal glow, game-ready PBR
```

#### `biome-red-meteor-fragment`

```
Single isolated low-poly fantasy meteor fragment, red-aligned impact design, dense pitted iron rock lump with a fused blistered crust and one flattened impact face, compact readable silhouette, game prop approximately 1.5 meters wide and 1 meter tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Dark pitted iron crust, heat-blued patches, faint ember glow in the pits, game-ready PBR
```

#### `biome-red-crater-rim-small`

```
Single isolated low-poly fantasy crater rim ring, red-aligned impact design, low circular ring of upthrust broken rock and ejected debris with an open hollow centre and no floor, flat ring readable silhouette, game prop approximately 3 meters across and 0.5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Shattered red-brown rock, grey ash dusting, scorched inner edge, game-ready PBR
```

#### `biome-red-crater-rim-large`

```
Single isolated low-poly fantasy large crater rim ring, red-aligned impact design, broad uneven ring of upthrust shattered rock and ejecta blocks with an open hollow centre and no floor, one side breached lower than the rest, flat ring readable silhouette, game prop approximately 8 meters across and 1.2 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Shattered red-brown rock, heavy grey ash, scorched blackened inner slope, game-ready PBR
```

#### `biome-red-smoldering-impact-site`

```
Single isolated low-poly fantasy smouldering impact site, red-aligned impact design, huge embedded meteor mass half buried in a ring of upthrust shattered rock with radiating cracked slabs and scattered ejecta blocks, heavy dominating readable silhouette, game prop approximately 12 meters across and 5 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Blackened fused iron, cracked red rock, grey ash, glowing molten seams, game-ready PBR
```

---

## Green - Forest

Old growth, moss, ruins reclaimed by the wood. Ground texture in play:
`assets/textures/forest/forrest_ground_01`.

| `-Name` | Role | Polys | Size | Density |
|---|---|---|---|---|
| `biome-green-mossy-boulder` | Ground clutter | 1200 | 1.5 m | High |
| `biome-green-fallen-log` | Midground | 2800 | 6 m | Medium |
| `biome-green-mushroom-ring` | Ground detail | 2000 | 2 m | Low |
| `biome-green-ancient-great-tree` | Landmark | 12000 | 20 m | 1-2 per lane |
| `biome-green-ruin-wall-fragment` | Ground clutter | 2000 | 2.5 m | High |
| `biome-green-toppled-column` | Midground | 2500 | 5 m | Medium |
| `biome-green-mossy-statue-torso` | Midground | 3000 | 3 m | Low |
| `biome-green-ruined-temple-arch` | Landmark | 10000 | 12 m | 1-2 per lane |

The four ruin pieces share one implied architecture - the same pale mossy stone - so
they can be clustered into a single readable ruin site or scattered apart.

#### `biome-green-mossy-boulder`

```
Single isolated low-poly fantasy mossy boulder, green-aligned old forest design, rounded granite rock with a thick moss cap spilling over one shoulder and small ferns at the base, simple rounded readable silhouette, game prop approximately 1.5 meters wide and 1.1 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Grey granite, deep green moss, damp forest-floor tint, game-ready PBR
```

#### `biome-green-fallen-log`

```
Single isolated low-poly fantasy fallen log, green-aligned old forest design, long moss-covered tree trunk lying on its side with a splintered break at one end, shelf fungus along its length and a hollow interior, long horizontal readable silhouette, game prop approximately 6 meters long and 1.2 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Damp bark, thick green moss, pale shelf fungus, soft rot at the break, game-ready PBR
```

#### `biome-green-mushroom-ring`

```
Single isolated low-poly fantasy mushroom ring, green-aligned enchanted forest design, circular arrangement of seven fat capped toadstools of varying heights with thick curved stems, low ring readable silhouette, game prop approximately 2 meters across and 0.7 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Muted green and cream caps, damp pale stems, restrained soft bioluminescent underglow, game-ready PBR
```

#### `biome-green-ancient-great-tree`

```
Single isolated low-poly fantasy ancient great tree, green-aligned primeval forest design, massive buttressed trunk with heavy gnarled roots, a hollow arch through the base and thick low branches cut short, towering readable silhouette, game prop approximately 12 meters wide and 20 meters tall, minimal foliage, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Deep furrowed bark, heavy green moss on one face, damp earth at the roots, game-ready PBR
```

#### `biome-green-ruin-wall-fragment`

```
Single isolated low-poly fantasy ruined wall fragment, green-aligned reclaimed ruins design, short section of mortared stone wall broken off at both ends with an uneven crumbling top and moss creeping up one face, blocky readable silhouette, game prop approximately 2.5 meters wide and 1.6 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Grey mossy stone, crumbling mortar, damp green staining, game-ready PBR
```

#### `biome-green-toppled-column`

```
Single isolated low-poly fantasy toppled stone column, green-aligned reclaimed ruins design, fluted pillar lying broken into three uneven drums with a cracked capital at one end and moss along the underside, long horizontal readable silhouette, game prop approximately 5 meters long and 1 meter tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Weathered pale stone, deep green moss, damp earth staining, game-ready PBR
```

#### `biome-green-mossy-statue-torso`

```
Single isolated low-poly fantasy ruined statue torso, green-aligned reclaimed ruins design, weathered armless stone figure broken off above the knees on a cracked square plinth with the features worn completely smooth and moss over one shoulder, upright readable silhouette, game prop approximately 1.2 meters wide and 3 meters tall, no gore, no recognisable face, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Weathered grey stone, heavy green moss, lichen patches, damp staining, game-ready PBR
```

#### `biome-green-ruined-temple-arch`

```
Single isolated low-poly fantasy ruined temple arch, green-aligned reclaimed ruins design, tall freestanding stone archway with a cracked keystone, one collapsed side pillar and thick vines climbing the standing leg, imposing asymmetric readable silhouette, game prop approximately 9 meters wide and 12 meters tall, no characters, no text, no symbols from existing franchises, no ground plane, no environment
```

```
Weathered pale stone, deep green moss, climbing vines, damp lichen, game-ready PBR
```

---

## Cost and sequencing

40 assets. `assets/structures/mana-well-black/mana-well-black.meshy.json` records
`consumed_credits: 10` for its refine task with preview billed separately, so treat
**10-15 credits per finished asset** as the working estimate - roughly **400-600
credits** for the full set. Confirm current per-stage pricing on the Meshy dashboard
before committing; the numbers here are extrapolated from a single manifest.

`ultra_mode` (+5 credits, added 2026-08-13) is worth considering only for the six
landmark pieces, if at all.

Suggested order:

1. All 40 as `-DryRun` - free, and the point at which to red-line prompts.
2. Green lane as a live pilot (8 assets). Green exercises both an organic set and a
   ruins set, so it is the best single test of whether the prompt scaffolding holds
   style across subject types.
3. Import, scatter and judge at gameplay distance before spending further.
4. White, blue, black.
5. Red last, after the terrain heightmap work - the craters depend on it.

## After generation

Follow the checklist in `docs/AI_WORKSPACE.md`: run `./tools/validate_godot.ps1` to
import, inspect the scene and materials through Godot MCP, add scale correction and
collision in a wrapper scene, then check silhouette at gameplay distance, texture
memory, polygon count, origin, orientation and license.

Two additions specific to these props:

- **Collision.** Ground clutter should have none - it is scatter, and the player and
  enemies walk through it. Midground and landmark pieces need a convex or simplified
  trimesh shape, and anything placed inside a lane must be re-baked into
  `NavigationRegion3D` or enemies will path straight through it.
- **Material dedupe.** Check whether ground-clutter props in the same lane can share
  one atlased material before they go into a MultiMesh.
