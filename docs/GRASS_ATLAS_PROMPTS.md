# Grass Atlas Prompts

Image-generation prompts for replacement grass sheets, one per biome. These feed
`tools/build_grass_billboards.gd`, which keys them to alpha cutouts that
`scripts/grass_scatter.gd` scatters across the lane wedges.

Separate from `docs/BIOME_ASSETS.md` on purpose: that file is Meshy text-to-3D, this
is flat 2D texture sheets. Different tool, different rules.

## Why the prompts look the way they do

Grass renders through an **alpha scissor** - a binary test. Every pixel is either
fully drawn or fully discarded; there is no such thing as a half-opaque blade edge.
Two consequences drive every constraint below.

**Thin blades die.** A blade thinner than a couple of pixels loses coverage as the
texture mipmaps down, and breaks into dashes and speckle in the distance. Photoreal
tufts made of hundreds of hair-fine blades are the worst possible input, which is
exactly why the current sheets read as messy. Game grass atlases are drawn with
**fewer, thicker, bolder blades** for precisely this reason - it is not a stylistic
choice, it is what survives the technique.

**Pale blades fringe.** Anything close to the backdrop's colour gets promoted to a
solid opaque pixel of that colour rather than fading out. On a white backdrop, pale
straw and white halo are nearly indistinguishable - measured on the current wheat
sheet, only 6.5% of pixels separate the two, versus 2.0% on the green sheet. So the
prompts ask for saturated, contrasty colour and explicitly rule out washed-out tips.

Everything else - no shadows, no ground, flat lighting - exists so the keying has a
clean, uniform backdrop to remove.

## Output spec

- **2x2 grid, four distinct tufts**, matching what the build script expects
- **Square, at least 1024x1024**; 2048 if the tool offers it. Each quadrant becomes
  one billboard capped at 512px, so 1024 total is the practical floor
- Save as `assets/foliage/grass/source/<biome>_grass_sheet.png` using the existing
  names: `white`, `blue`, `black`, `red`, `green`
- Then run:

```bash
"G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_grass_billboards.gd
```

If your generator produces better results one plant at a time, generate four separate
images instead and say so - the build script's 2x2 split is a few lines and can take
four loose files just as easily.

## Shared constraints

Every prompt below already embeds this block. It is repeated here so you can re-attach
it if you rewrite a prompt:

> 2x2 grid of four separate grass tufts, evenly spaced with clear empty gaps between
> them, none touching or overlapping, none cropped at the image edge. Pure flat white
> background, exactly #FFFFFF, no shadow, no gradient, no vignette, no ground, no soil,
> no pot. Orthographic front view at eye level, flat even lighting, no rim light, no
> dramatic highlights. Bold thick broad blades - a few dozen per tuft, not hundreds of
> fine hairs - each blade clearly readable in silhouette. Crisp hard edges, sharp focus
> throughout, no motion blur, no depth of field, no soft glow or haze. Strongly
> saturated colour, no pale washed-out tips, no near-white values anywhere in the
> plant. All four tufts at the same scale with their bases level along the bottom.
> Flat game asset texture sheet.

---

## White - Plains

```
A 2x2 grid of four separate golden wheat grass tufts for a game texture sheet. Deep amber and rich harvest gold, warm and strongly saturated, with heavy drooping seed heads on thick upright stalks. No pale cream, no straw-white, no bleached tones anywhere - the palest blade must still read as solid gold against white.

2x2 grid of four separate grass tufts, evenly spaced with clear empty gaps between them, none touching or overlapping, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette, no ground, no soil, no pot. Orthographic front view at eye level, flat even lighting, no rim light, no dramatic highlights. Bold thick broad blades - a few dozen per tuft, not hundreds of fine hairs - each blade clearly readable in silhouette. Crisp hard edges, sharp focus throughout, no motion blur, no depth of field, no soft glow or haze. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere in the plant. All four tufts at the same scale with their bases level along the bottom. Flat game asset texture sheet.
```

This is the hardest of the five to get right - gold sits closest to white, and it is
the sheet that fringed worst last time. If a generation comes back pale, regenerate
rather than trying to fix it downstream.

---

## Blue - Islands

```
A 2x2 grid of four separate coastal sea-grass tufts for a game texture sheet. Deep teal and blue-green, cool and strongly saturated, with broad ribbon-like blades arcing outward as if salt-stiffened. No mint, no pale aqua, no frosted tips - every blade holds a deep sea colour to its very end.

2x2 grid of four separate grass tufts, evenly spaced with clear empty gaps between them, none touching or overlapping, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette, no ground, no soil, no pot. Orthographic front view at eye level, flat even lighting, no rim light, no dramatic highlights. Bold thick broad blades - a few dozen per tuft, not hundreds of fine hairs - each blade clearly readable in silhouette. Crisp hard edges, sharp focus throughout, no motion blur, no depth of field, no soft glow or haze. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere in the plant. All four tufts at the same scale with their bases level along the bottom. Flat game asset texture sheet.
```

---

## Black - Swamp

```
A 2x2 grid of four separate blighted swamp grass tufts for a game texture sheet. Deep aubergine and charcoal with violet edges, dark and richly saturated, blades drooping and curling as if rotting from the tips. Dark values throughout, but never flat black - keep violet and plum tones readable inside the shadows.

2x2 grid of four separate grass tufts, evenly spaced with clear empty gaps between them, none touching or overlapping, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette, no ground, no soil, no pot. Orthographic front view at eye level, flat even lighting, no rim light, no dramatic highlights. Bold thick broad blades - a few dozen per tuft, not hundreds of fine hairs - each blade clearly readable in silhouette. Crisp hard edges, sharp focus throughout, no motion blur, no depth of field, no soft glow or haze. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere in the plant. All four tufts at the same scale with their bases level along the bottom. Flat game asset texture sheet.
```

The easiest of the five to key - dark blades separate from a white backdrop
trivially. Push for thick blades here, since the current purple sheet is the wispiest
of the set and thins out worst at distance.

---

## Red - Mountains

```
A 2x2 grid of four separate volcanic red grass tufts for a game texture sheet. Deep crimson and rust red with darker oxblood shadows, hot and strongly saturated, blades stiff and blade-straight with sharp pointed tips as if scorched. No pink, no salmon, no sun-bleached tips - the colour stays deep and heavy from base to point.

2x2 grid of four separate grass tufts, evenly spaced with clear empty gaps between them, none touching or overlapping, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette, no ground, no soil, no pot. Orthographic front view at eye level, flat even lighting, no rim light, no dramatic highlights. Bold thick broad blades - a few dozen per tuft, not hundreds of fine hairs - each blade clearly readable in silhouette. Crisp hard edges, sharp focus throughout, no motion blur, no depth of field, no soft glow or haze. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere in the plant. All four tufts at the same scale with their bases level along the bottom. Flat game asset texture sheet.
```

---

## Green - Forest

```
A 2x2 grid of four separate lush forest grass tufts for a game texture sheet. Deep saturated forest green with darker moss-green shadows, broad upright blades with a slight natural arc, thick and healthy. No yellow-green, no lime, no pale sunlit tips - every blade stays a rich deep green to its end.

2x2 grid of four separate grass tufts, evenly spaced with clear empty gaps between them, none touching or overlapping, none cropped at the image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no vignette, no ground, no soil, no pot. Orthographic front view at eye level, flat even lighting, no rim light, no dramatic highlights. Bold thick broad blades - a few dozen per tuft, not hundreds of fine hairs - each blade clearly readable in silhouette. Crisp hard edges, sharp focus throughout, no motion blur, no depth of field, no soft glow or haze. Strongly saturated colour, no pale washed-out tips, no near-white values anywhere in the plant. All four tufts at the same scale with their bases level along the bottom. Flat game asset texture sheet.
```

---

## Accepting or rejecting a generation

Check these before running the build script. All five are quick eyeball tests, and
catching a bad sheet here is far cheaper than diagnosing it in-engine.

1. **Background is genuinely white.** Open it and check a corner pixel is near
   #FFFFFF, not a light grey wash. Generators love adding a soft shadow under plants;
   that shadow will key as opaque grey blobs.
2. **No pale blade tips.** Drop the image on a black layer in any viewer. Blades that
   nearly vanish are the ones that will fringe.
3. **Blades are thick.** At the final 512px tile size a blade wants to be at least
   4-5 pixels wide. If it looks like hair at 100% zoom, it will speckle at distance.
4. **Four tufts, fully separated, none cropped.** The build script splits on exact
   quarters, so anything crossing the midlines gets sliced in half.
5. **Bases roughly level.** Each tuft is cropped to its own alpha bounds and planted
   at its base, so wildly different baselines make some clumps float.

If a sheet fails 1 or 2, regenerate it. Failures on 3 usually mean the prompt's
"bold thick broad blades" clause needs pushing harder - try "very few, very wide
blades, almost leaf-like".

## After the sheets are in

The build script handles keying, cropping, background fill, dilation and downscaling.
Worth knowing that two known limits remain, neither fixed by better source art:

- **Mipmap alpha coverage is not preserved.** Distant grass still loses coverage as
  it mips down. The standard fix rescales alpha per mip level so coverage stays
  constant; Godot does not do it at import and the build script does not do it yet.
- **Alpha-to-coverage needs MSAA on.** `scripts/grass_scatter.gd` requests it, but
  `GraphicsSettings` defaults `msaa_level` to 0, so it is inert until a preset is
  chosen in the menu.
