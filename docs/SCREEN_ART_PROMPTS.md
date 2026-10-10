# Screen art prompts (render → card-art painting)

Art for the splash screen, the main menu, the loading screen and the game-over screen. Each
image starts from an in-engine render of the real map with the game's own creatures posed in
it (`docs/screen_art/renders/`), and is repainted with image-to-image generation into the look
of a **Magic: The Gathering card illustration**. The render fixes the composition and makes
the creatures the ones the player actually fights; the generator supplies the painting.

Re-render after a map or model change:

```
"G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --windowed --resolution 2400x1350 res://tools/tests/key_art_shot.tscn -- "G:/Projekte/mtg-pentagon-tower-defense/docs/screen_art/renders" [splash,menu,...]
```

The shots, their cameras and who stands where are in `tools/tests/key_art_shot.gd` (`_shots()`).

## How to run each one

1. Use the render as the **init / reference image**, 16:9.
2. Paste the **shared style block** below, then the shot's own prompt. Add the negative
   prompt if the tool has a field for it.
3. **Strength / denoise ~0.5–0.6** in an img2img tool: low enough that the layout, the
   creatures' poses and the crystal survive, high enough that the plastic game shading turns
   into paint. Go to 0.65–0.7 for `loading_black`, which renders very dark. In a chat-style
   editor (Gemini, ChatGPT) say "repaint this image, keep the composition and the creatures'
   positions and poses" in front of the prompt instead.
4. Generate at least 1920×1080; 2560×1440 if the tool allows. Keep the **safe areas** clear;
   the UI goes there.
5. Save the picks into `docs/screen_art/final/` under the render's name (`menu.png` ...).

### Shared style block (paste first, every time)

```
Fantasy trading card game illustration in the style of Magic: The Gathering card art.
Semi-realistic painterly digital oil painting, visible confident brushwork, rich saturated
colour, dramatic cinematic lighting with strong rim light and atmospheric depth, epic sense
of scale, one clear focal subject, high detail on the creatures, softer painterly
background. Keep the composition, the camera angle and every creature's position and pose
from the reference image.
Colour language of the five factions: white = warm gold and ivory holy light; blue = icy
cyan and deep ocean blue; black = violet, sickly purple and shadow; red = fire orange,
crimson and ember; green = vivid leaf green and earthy brown.
```

### Negative prompt (all shots)

```
text, letters, title, logo, watermark, signature, card frame, card border, mana symbols,
UI, cartoon, cel shading, anime, low-poly, toy-like, plastic, 3D render look, blurry,
extra limbs, deformed hands, duplicated creatures
```

## The cast

So the prompts can name things the same way every time:

| In the render | Paint it as |
|---|---|
| The crystal | a towering floating mana crystal, faceted, glowing from within with all five colours |
| Standing stones | a ring of ancient weathered monoliths around the crystal |
| Hero | a battle-scarred warrior in fur and dark plate armour with a broad sword |
| White boss / minions | a golden-armoured holy paladin giant / human clerics and soldiers in white and gold |
| Blue boss / minions | a frost giant with blue ice-rimed skin / merfolk warriors and tide-mages |
| Black boss / minions | a hulking zombie lord / shambling undead, ghouls with violet glowing cracks |
| Red boss / minions | a fire giant with ember-cracked skin / goblin raiders with crude blades and torches |
| Green boss / minions | an ancient treant of living wood / elven warriors and druids |

---

## splash.png - splash screen

The first thing on screen. Safe area: the **upper third** (sky) is the logo.

```
Low heroic view across a ring of ancient standing stones at the centre of a wild valley. A
towering floating mana crystal glows in the middle of the ring, faceted, light of all five
colours shifting inside it, casting coloured light on the stones. In front of it, seen from
behind, a lone battle-scarred warrior in fur and dark plate armour walks towards it, sword
in hand. Beyond, a smoking volcano under a vast golden late-afternoon sky with a low sun
haloing the stones. Calm before the storm, majestic, hopeful. Keep the upper third open sky.
```

## menu.png - main menu background

Safe area: the **left 40%** holds the menu panel, so keep it calm (sky, slope, haze).

```
A lone battle-scarred warrior in fur and dark plate armour stands on the right of the
frame, sword lowered, roaring a battle cry towards the valley. Below the smoking volcano a
red warband pours down the slope towards him: goblin raiders with crude blades and
torches, and behind them a fire giant with ember-cracked skin. Hot orange sun low behind
the volcano, embers and ash drifting in the air, red-leaved trees and dark pines. Epic
standoff, one against a horde. Keep the left side of the image calm and uncluttered.
```

## loading_<colour>.png - loading screen (one per faction)

Shown while the map loads; pick one at random, or the colour of the lane the next wave
favours. Safe area: the **bottom 18%** holds the progress bar and a tip.

**loading_white.png**
```
A golden-armoured holy paladin giant leads a column of human clerics and soldiers in white
and gold across an autumn meadow of golden oaks. Shafts of warm holy light break through
the clouds onto the giant, gold filigree gleaming on its armour. Righteous, unstoppable,
a crusade on the march. Keep the bottom of the image plain ground.
```

**loading_blue.png**
```
A frost giant with blue ice-rimed skin wades up from a pale sand beach, leading merfolk
warriors and tide-mages out of the shallows among mangrove trees with tangled roots. Cold
cyan light, sea spray turning to frost in the air, a jagged sea stack in the haze. Ancient,
cold, tidal power. Keep the bottom of the image plain sand.
```

**loading_black.png** - the render is very dark; lift it.
```
A hulking zombie lord rises out of a fog-choked swamp under weeping willows, a horde of
shambling undead and ghouls with violet glowing cracks behind it. Sickly purple light
glowing through the mist, dead branches, black water, a pale moon breaking through. Dread,
decay, inevitability. Brighten the scene enough to read the creatures clearly. Keep the
bottom of the image dark mud.
```

**loading_red.png**
```
A fire giant with ember-cracked skin strides out of a scorched valley below an erupting
volcano, goblin raiders swarming around its feet with crude blades and torches. Smoke
column glowing orange from below, the sun a burning disc behind the ash, sparks and embers
everywhere. Chaos, fury, fire. Keep the bottom of the image plain scorched ground.
```

**loading_green.png**
```
An ancient treant of living wood raises a gnarled arm in a towering primeval forest,
elven warriors and druids gathering among the giant trunks. Green-gold light filtering
through the canopy in god rays, moss, ferns and wildflowers, mist between the trees. Wild,
ancient, overwhelming nature. Keep the bottom of the image plain forest floor.
```

## game_over.png - game over

The crystal is destroyed. Safe area: **centre band** for "DEFEAT" and the buttons - the
crystal explosion sits behind it, so it should read as light and debris, not detail.

```
The ring of ancient standing stones overrun at dusk. The towering mana crystal in the
centre is shattering in a huge fireball explosion, shards of glowing crystal and fire
bursting outwards, the five colours of its light tearing loose into the sky. Around it
creatures of all five factions - goblins, undead, merfolk, elves and human soldiers -
stand over the ruins, and the five giant bosses loom in the smoke behind. In the
foreground a fallen warrior in fur and dark plate armour lies in the dust. Blood-red sky,
smoke, embers, tragic and final.
```

## Where the finished images live

The painted versions are in `assets/images/`; the white-background originals of the two
lettering images, and the splash painting the boot splash is composed from, are in
`docs/screen_art/source/` (not shipped).

| Image | Used by |
|---|---|
| `boot_splash.png` | `project.godot` → `application/boot_splash/image`: the splash painting with the logo composed on it. Also laid over the main menu the first time it opens and faded out, so the start flows into the menu. |
| `menu.jpg` | the main menu's backdrop (`scripts/main_menu.gd`, `_build_backdrop`) - the painting first made for game over |
| `loading_<colour>.jpg` | `scripts/loading_screen.gd`, one at random per load |
| `logo_pentafall.png` | the main menu column and the loading screen |
| `title_defeat.png` | the defeat panel (`scripts/hud.gd`, `_style_game_over_panel`), over the burning hub - there is no game-over painting |

The lettering was cut out of its white background with `tools/cut_out_lettering.py`
(`python -I tools/cut_out_lettering.py <in> <out.png> [min_hole_px] [white_threshold]`;
DEFEAT used a threshold of 175 to take its pale halo with the background).
