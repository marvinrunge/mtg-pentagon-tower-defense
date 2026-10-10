# Character Classes Plan

A staged plan for letting each player pick one of five playable characters. Every stage
ships something playable on its own; later stages extend the same machinery rather than
replacing it.

**The rule: a class is the WEAPON, a colour is the MAGIC.** A class decides the basic
attack, the defence, the body (health, speed) and a short track of class skills. The skill
tree's five colours and their spells stay exactly as they are and are open to every class -
an archer can play black, a mage can play green. Nothing in a colour may assume a class.

## The five classes

| Class | Role | Basic attack | Defence | Status |
|---|---|---|---|---|
| **Axe fighter** | Fast combo fighter with sustain | Light combo chain, charged spin (heavy), kick | Block | The current orc - exists |
| **Sword & shield** | Tank | One-handed chain + shield | Block that stops nearly everything | New |
| **Two-handed sword** | Area damage, slow and heavy | Wide slow cleaves, charged overhead | No block; cannot be interrupted mid heavy swing | New |
| **Archer** | Ranged damage, fragile | Hold to draw, release to shoot; tap for a quick shot | Dodge roll | New |
| **Mage** | Spell damage, fragile | A bolt in the colour of their path | Blink | New |

Axe fighter and two-hander are deliberately apart: the axe is quick and lives on its
combo chain, the two-hander is slow and lives on single huge hits (which is also where the
death launch and the ragdolls pay off most).

## Class skills

Four per class, colourless, on a short track at the centre of the skill tree - the hub
Blade Dance sits on today, which `docs/SKILL_DESIGN.md` already describes as the one
purchase that changes the basic attack. That is what class skills are.

**They unlock by team level, automatically.** No mana, no skill points: levels are shared
and simultaneous (`docs/ECONOMY.md`), so every player reaches their class's next skill at
the same moment, and a late joiner or a reconnect gets every skill their level already
covers. This is the mechanism Blade Dance already runs on - granted at
`Player.BLADE_DANCE_LEVEL`, derived from the level rather than saved in the build, and
re-applied by `RunState` for anyone who arrives after the level-up.

The ECONOMY target is roughly 15-18 levels across a 25-wave run, front-loaded, so the four
unlocks sit at **levels 3, 6, 10 and 14** - the capstone arriving in the last third of a
run with room to spare. One list in `GameSettings` (`class_skill_levels`), shared by every
class.

The shape is the same for every class: a basic-attack passive first, then an active (or
the defence the class most needs), then a second passive, then a capstone. Actives go on
the quick bar like spells; on unlock one is put in the first free quick slot.

Names follow the rest of the game - real Magic cards or keywords where one fits. All are
proposals.

### Axe fighter

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Bloodthirst** | Passive | Kills during a combo chain heal a little and speed up the next stage |
| 6 | **Hurl Axe** | Active | The axe is thrown through the enemies in front and comes back, hitting on both legs |
| 10 | **Blade Dance** | Passive | Third stage of the light chain, landing harder (exists - stays at level 10) |
| 14 | **Battle Frenzy** | Active, capstone | For a few seconds the chain does not end as long as every stage connects |

### Sword & shield

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **First Strike** | Passive | After a successful block the next attack comes out at once and harder - a riposte |
| 6 | **Shield Bash** | Active | Shield thrust in a cone: short stun and knockback |
| 10 | **Shield Wall** | Passive | A block raised just in time (a perfect block) staggers the attacker |
| 14 | **Phalanx** | Passive, capstone | While blocking, allies and myrs behind you take less damage, and enemies nearby turn on you |

### Two-handed sword

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Brute Force** | Passive | Heavy swings knock back further; what they kill is thrown hardest |
| 6 | **Whirlwind** | Active | Several turns on the move, hitting everything around |
| 10 | **Indomitable** | Passive | Nothing interrupts or flinches you during a heavy swing |
| 14 | **Berserk** | Active, capstone | A few seconds faster and harder-hitting, and no block at all |

### Archer

The defence comes before the big active: the archer is the most fragile class and needs
the way out sooner.

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Longshot** | Passive | Fully drawn shots pierce through several enemies |
| 6 | **Disengage** | Active | A roll backwards that leaves a slowing snare behind |
| 10 | **Arrow Volley Trap** | Active | A rain of arrows on a target area |
| 14 | **Deadeye** | Passive, capstone | Hits on weak points and heads deal much more damage |

### Mage

| Level | Skill | Kind | Effect |
|---|---|---|---|
| 3 | **Prowess** | Passive | After every spell the next basic bolt is empowered - rewards weaving spells and bolts |
| 6 | **Blink of an Eye** | Active | A short teleport that leaves a decoy behind for a moment |
| 10 | **Spell Mastery** | Passive | Shorter cooldowns on the colour spells |
| 14 | **Mana Surge** | Active, capstone | Resets the cooldown of the last spell cast |

Deliberately NOT a "Storm" effect (spells copying themselves): Jeskai already owns that in
Stage 2 of `docs/GUILD_PLAN.md`.

### What changes for Blade Dance

Today it is bought at the centre for `GameSettings.melee_combo_unlock_cost` mana of any
colour OR granted at level 10. Under this plan it is the axe fighter's level-10 class skill
and nothing else: the mana purchase goes, and so does Blade Dance for every other class.
The centre node becomes the class track - read-only, showing each skill and the level it
unlocks at.

## Architecture

**Classes as data.** A `CharacterClass` resource (or a `ClassDatabase` in the style of
`scripts/spell_database.gd`), one per class:

- the visual scene and its animation library
- a clip map from logical names to clips (`light_attack` -> `combo_3` for the axe fighter,
  `bow_shot` for the archer) - `PlayerAnimator` reads names from this instead of its own
  constants
- weapons and where they are held (right hand; left hand for the shield)
- health, move speed, armour
- which attack kit and which defence the class uses
- its four class skills

**Attacks as kits.** The melee logic in `scripts/player.gd` (light chain, heavy, block,
kick) moves into a melee kit; the archer and the mage get kits of their own. Aiming
through the crosshair already exists for spells, and so does `ProjectilePool`.

**The builder per class.** `tools/player_character_builder.gd` runs from a per-class
config (mesh, textures, clip table, weapon grips) and writes
`scenes/characters/<class>/visual.tscn` plus a library. Its measuring and trimming - travel
speed from root motion, hit ratios inside attack clips - stays as it is. Death and the
spellcasting poses are still borrowed from the enemy rig and shared.

**Choice and network.** The class is picked in the lobby, kept in the peer info and in
`PlayerRegistry`, and travels with the build (`export_build` / `apply_build`) so a
reconnect comes back as the same class. `Player._ready` loads that class's visual.

**"Melee" in existing skills becomes "basic attack".** Rubblebelt Rioters ("your next three
melee hits"), Executioner's Capsule (melee execute) and Blade Dance all say melee; anything
that is not the axe fighter's own should count any class's basic attack, or it is worth
nothing to an archer or a mage.

## Mixamo assets

- One character uploaded per class; every animation downloaded onto it - FBX, the first
  *with skin*, the rest *without skin*. Bone names then match by construction.
- Leave **In Place unticked** for locomotion: the builder measures travel speed from the
  root motion, as it does for the current set.
- One folder per class (`assets/player/<class>/`): file names such as `standing idle.fbx`
  recur in every pack.
- Each pack needs its own armed locomotion (a two-hander walks differently). Death and
  the casting poses can stay shared.

## Stages

1. **Refactor, no new content.** Class data, clip map, attack kits, class skill track.
   The axe fighter is the first class and plays exactly as now; Blade Dance moves onto the
   track at level 10. Tests prove nothing changed.
2. **Sword & shield** - closest to what exists: a shield mesh and its own animation set.
3. **Two-handed sword** - the melee kit with other clips and numbers.
4. **Archer** - the ranged kit, arrows, aiming.
5. **Mage** - the caster kit, and the spell balance that goes with it.
6. **Class choice in the lobby, balance, and tests per class.** `tools/tests/skill_roster`
   asserts every class skill has an observable effect, the way it already does for every
   spell.

## Open questions

1. **Models.** Its own Meshy model per class, or the same orc with other gear?
2. **Switching.** Is the class fixed for the whole run, or can it change (say, at Upkeep)?
3. **Two of a class.** Can two players on a team be the same class?
