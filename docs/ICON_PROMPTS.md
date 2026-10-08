# Skill icon prompts (Gemini image generation)

Prompts for the skill tree nodes that still have no icon of their own. Every filename below is
already wired in `SpellDatabase.ICON_FILES`: until its file exists, `get_icon_path` falls back to
what the node shows now (a borrowed icon, or the colour's mana symbol), so adding the file is the
whole change.

## All nine in one image (recommended)

1. Start a Gemini chat and attach 3-4 existing icons as style references, e.g.
   `assets/icons/unsummon.png`, `fire-cone.png`, `wall-of-souls.png`, `roar.png`.
2. Send the prompt below. It asks for a 3 x 3 sheet in a fixed order.
3. Save the sheet and cut it into the nine files:
   `python tools/slice_icon_sheet.py <sheet.png>` (writes into `assets/icons/`, skips files that
   already exist unless `--force`).
4. Open the project in the editor once so Godot imports the new files.

```
Create ONE square image (1:1, as large as possible) that is a sprite sheet of 9 ability
icons for a fantasy action game inspired by Magic: The Gathering, laid out as an exact
3 x 3 grid of equal square cells, separated by straight, plain, near-black gutters about
2% of the image wide. Each cell holds exactly one complete icon, centred, filling the cell.

Style - match the attached reference icons exactly, the same for all 9:
painterly digital illustration, polished like a high-end ARPG / mobile spell icon; one bold
central subject with a strong silhouette, readable at 48 px; dramatic lighting, magical
glow and rim light, rich saturated colours; soft dark vignette background tinted in the
icon's colour, slightly rounded square. No text, letters, numbers, labels, borders, frames,
UI elements or watermark anywhere in the image.
Colour language: white = warm gold and ivory light; blue = icy cyan and deep ocean blue;
black = violet, sickly purple and shadow; red = fire orange, crimson and ember; green =
vivid leaf green and earthy brown. Two-colour icons blend both palettes.

Cells, row by row, left to right:
1. Wall of Frost (blue): a thick, jagged wall of blue ice crystals erupting from the ground
   in a straight line, low three-quarter view, frost mist at its base, cyan glow inside.
2. Contagion (black): a sickly violet plague cloud leaping from one skull-like silhouette to
   the next in a chain of three, glowing purple-green spores, the infection spreading.
3. Kodama's Reach (green): a small white forest spirit (kodama, round head, simple face),
   arms outstretched, green roots and rings of light spreading out across mossy ground.
4. Azorius Justiciar (white + blue): a stern armoured law-mage raising a glowing sceptre,
   chains of white-gold light and blue arcane runes binding the air before him.
5. Dimir Guildmage (blue + black): a hooded mage with a hidden face, one hand of cold blue
   frost, the other of violet death magic, a ghostly figure rising from frozen ground.
6. Mayhem Devil (black + red): a grinning red-skinned horned imp gleefully holding a skull
   that bursts into fire and violet sparks.
7. Rubblebelt Rioters (red + green): a raging barbarian brute mid-swing with a stone club,
   shattered rocks and embers flying, wild green energy around his fists.
8. Trostani, Selesnya's Voice (green + white): a serene dryad whose body merges into a
   blossoming white tree, golden light flowing from her open hands.
9. Displace (blue): a mage dissolving into blue light particles on the left and reappearing
   solid on the right, a streak of arcane distortion between them.
```

If one cell comes out wrong, regenerate just that one with the matching single-icon line below
(after the style block) and save it under its filename by hand.

## One icon at a time

Send the **style block** once, then one **icon line** per message, and save each result as a
square PNG under `assets/icons/` with the filename from the table. Size does not matter much
(the existing ones are about 210 px).

`tools/tests/skill_tree_full_shot.tscn` photographs the tree with every node bought, which is the
quickest way to see which nodes still wear a mana symbol.

## Style block

```
I need square ability icons for a fantasy action game inspired by Magic: The Gathering.
Match the style of the attached reference icons exactly:
- painterly digital illustration, polished like a high-end ARPG / mobile spell icon
- ONE bold central subject with a strong silhouette, readable at 48 px
- dramatic lighting, magical glow and rim light, rich saturated colours
- soft dark vignette background tinted in the icon's colour, slightly rounded square
- no text, no letters, no numbers, no border or frame, no UI elements, no watermark
- 1:1 square, 512x512
Colour language: white = warm gold and ivory light; blue = icy cyan and deep ocean blue;
black = violet, sickly purple and shadow; red = fire orange, crimson and ember;
green = vivid leaf green and earthy brown. Two-colour guild icons blend both palettes,
split or swirled together.
Reply with one icon per message. I will describe each one next.
```

## Icon lines

| File | Node | Prompt |
|---|---|---|
| `wall-of-frost.png` | Blue: Wall of Frost | `Icon: "Wall of Frost". A thick, jagged wall of blue ice crystals erupting from the ground in a straight line, seen at a low three-quarter angle, frost mist rolling at its base, cold cyan glow inside the ice. Blue palette.` |
| `contagion.png` | Black: Contagion | `Icon: "Contagion". A sickly violet plague cloud leaping from one skull-like silhouette to the next in a chain of three, glowing purple-green spores and drips, the infection visibly spreading. Black palette.` |
| `kodamas-reach.png` | Green aura: Kodama's Reach | `Icon: "Kodama's Reach". A small white forest spirit (kodama, round head, simple face) with arms outstretched, green roots and ripples of light spreading outward across mossy ground in widening rings. Green palette.` |
| `guild-azorius.png` | Guild White/Blue: Azorius Justiciar | `Icon: "Azorius Justiciar". A stern armoured law-mage holding up a glowing gavel-sceptre, chains of white-gold light and blue arcane runes binding the air in front of him. White and blue palette, gold and sapphire.` |
| `guild-dimir.png` | Guild Blue/Black: Dimir Guildmage | `Icon: "Dimir Guildmage". A hooded shadow mage whose face is hidden, one hand of cold blue frost, the other of violet death magic, a ghostly figure rising from frozen ground below. Blue and black palette.` |
| `guild-rakdos.png` | Guild Black/Red: Mayhem Devil | `Icon: "Mayhem Devil". A grinning red-skinned imp devil with horns, gleefully holding a bursting skull that explodes into fire and violet sparks. Black and red palette, crimson and purple.` |
| `guild-gruul.png` | Guild Red/Green: Rubblebelt Rioters | `Icon: "Rubblebelt Rioters". A huge raging barbarian brute mid-swing with a stone-and-bone club, shattered rocks and embers flying, wild green energy around his fists. Red and green palette.` |
| `guild-selesnya.png` | Guild Green/White: Trostani | `Icon: "Trostani, Selesnya's Voice". A serene dryad woman whose body merges into a blossoming white tree, golden light flowing from her open hands onto small figures below. Green and white palette, leaf green and soft gold.` |

## Optional: icons that borrow a picture

| File | Node | Now uses | Prompt |
|---|---|---|---|
| `displace.png` | Blue: Displace (blink) | `flying.png` (wings) | `Icon: "Displace". A mage figure dissolving into blue light particles on the left and reappearing solid on the right, a streak of arcane distortion between the two. Blue palette.` |
| `rhystic-study.png` | Blue aura: Rhystic Study | `sylvan-library.png` (blue rune book) | `Icon: "Rhystic Study". An open ancient tome floating, its pages radiating a protective blue shield bubble edged with frost crystals. Blue palette.` |

Both are wired too: the new file wins over the borrowed one as soon as it exists.
