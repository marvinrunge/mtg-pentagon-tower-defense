# Boss Lords - The Second Boss Per Colour

A **Lord** is a new kind of boss: a tribal warchief that makes *the wave around it*
dangerous instead of being dangerous on its own. Every colour gets exactly one, so
after this the game has ten bosses - the five giants/champions that exist today
(`BossDatabase.VISUAL_SCENES`) and the five lords below.

Nothing here is implemented yet. This file is the *what* (cards, abilities, numbers),
the *how* (files, functions, settings, tests) and the *prompts* (asset generation).

Companion files:

- `scripts/boss_database.gd` - where the five giants live today; the lords go beside them
- `scripts/game_settings.gd` - every number below belongs in its own `Boss lords` block
- `docs/WAVE_DESIGN.md` - the wave shape a lord has to fit into
- `docs/AI_WORKSPACE.md` - the Meshy/Mixamo pipeline the image prompts feed

## Why a lord is a different boss, not a re-skin

The existing five bosses are **solo threats**. `WaveManager._plan_wave` deliberately
gives a boss its own battle group with no squad at all ("it is one unit, a formation of
one is a point"), and `EnemyBase`'s whole boss kit is two telegraphed specials. Kill it,
the wave is over.

A lord inverts that:

| | Giant (today) | Lord (new) |
|---|---|---|
| Arrives | alone, own battle group | inside its colour's squad, with an oversized escort |
| Threat | its own two specials | what it does to the 25 units around it |
| Model scale | 2.1-2.9 | 1.7-2.0 (a warchief among troops, not a colossus) |
| Health | `800 * colour` | `~0.7x` of that |
| Counterplay | dodge the telegraphs | **decide** whether to dig it out first or clear the escort |
| Failure state if ignored | takes crystal damage slowly | the lane's chaff becomes elite-grade and overruns you |

That last row is the design goal. The player already has a target-priority decision for
mages (heal/slow/revive/buff casters) - a lord is that decision at wave scale, with a
visible radius, a visible banner and an obvious "the glow went out" moment when it dies.

## The MTG cards

The user's memory of "a Goblin Warchief, and I think there's a Soldier Warchief too" is
correct and the cycle is real. **Legions** and **Scourge** printed a *Warchief* cycle of
tribal lords: **Goblin Warchief** (R), **Undead Warchief** (B), **Daru Warchief** (W,
Soldiers) and **Krosan Warchief** (G, Beasts). The cycle has **no blue member** - blue's
tribal lord role belongs to the Merfolk lords instead, headed by **Lord of Atlantis**.

Card text, as printed (the relevant lines only):

### Red - Goblins

| Card | Text |
|---|---|
| **Goblin Chieftain** | Haste. *Other Goblin creatures you control get +1/+1 and have haste.* |
| **Goblin Warchief** | Goblin spells you cast cost {1} less. *Goblins you control have haste.* |
| **Goblin King** | *Other Goblins get +1/+1 and have mountainwalk.* |
| **Krenko, Mob Boss** | {T}: *Create X 1/1 red Goblin tokens, where X is the number of Goblins you control.* |

This is exactly the ask: stronger, tougher, faster. **Goblin Chieftain** is the aura,
**Krenko** is the active ability, **Warchief** is the name the player will remember.

### White - Soldiers / the game's "Clerics"

| Card | Text |
|---|---|
| **Field Marshal** | First strike. *Other Soldier creatures you control get +1/+1 and have first strike.* |
| **Captain of the Watch** | Vigilance. *Other Soldiers get +1/+1 and have vigilance.* ETB: *create three 1/1 Soldier tokens with vigilance.* |
| **Daru Warchief** | Soldier spells cost {1} less. *Soldier creatures you control get +0/+2.* |
| **Benalish Marshal** | *Other creatures you control get +1/+1.* |

White's units are named "Cleric" in `EnemyDatabase` but wear the human melee/ranged
models, so a marshal reads correctly. First strike + vigilance + Daru's toughness bump
is a **defensive** aura, which is what white should feel like.

### Blue - Merfolk / the game's "Illusions"

| Card | Text |
|---|---|
| **Lord of Atlantis** | *Other Merfolk creatures get +1/+1 and have islandwalk.* |
| **Master of the Pearl Trident** | *Other Merfolk you control get +1/+1 and have islandwalk.* |
| **Merrow Reejerey** | *Other Merfolk get +1/+1.* Whenever you cast a Merfolk spell, *tap or untap target permanent*. |
| **Kumena, Tyrant of Orazca** | Tap Merfolk to make itself unblockable / draw / *put a +1/+1 counter on each Merfolk you control*. |

Islandwalk is *evasion* - "your blockers do not apply". Translated to a tower defense:
buffed illusions are **partly untouchable**, not tougher.

### Green - Beasts / Elves

| Card | Text |
|---|---|
| **Krosan Warchief** | Beast spells cost {1} less. *{2}: Regenerate target Beast.* |
| **Elvish Champion** | *Other Elves get +1/+1 and have forestwalk.* |
| **Imperious Perfect** | *Other Elf creatures get +1/+1.* {G},{T}: *create a 1/1 Elf Warrior token.* |
| **Ezuri, Renegade Leader** | {G}: Regenerate target Elf. {3}{G}{G}: *Elves you control get +3/+3 and gain trample until end of turn.* |

Ezuri's overrun is the single best boss button in this list: a **burst** aura on a
cooldown rather than a permanent one, which the player can see coming and retreat from.

### Black - Zombies / the game's "Undead"

| Card | Text |
|---|---|
| **Undead Warchief** | Zombie spells cost {1} less. *Zombie creatures you control get +2/+1.* |
| **Death Baron** | *Skeletons and other Zombies you control get +1/+1 and have deathtouch.* |
| **Lord of the Undead** | *Other Zombies get +1/+1.* {1}{B},{T}: *return a Zombie from your graveyard to your hand.* |
| **Cemetery Reaper** | *Other Zombies get +1/+1.* {2}{B},{T}, exile a creature from a graveyard: *create a 2/2 Zombie token.* |

`EnemyBase` already keeps a corpse registry (`EnemyBase.corpses()`, built for the
player's own Zombify) and the black mage already revives. A lord that raises *the wave's
own dead* is the one boss in the game that can make a lane's kill count go backwards.

> Naming: the existing black boss scene is already called `zombie_lord`. The black lord is
> therefore **Undead Warchief**, never "Zombie Lord", or two different bosses answer to
> the same word in the same lane.

## The five lords

Shared shape - every lord has **four** things:

1. a **passive aura** on every same-colour enemy inside `boss_lord_aura_radius`
2. one **command**: a telegraphed, cooldown ability aimed at its own troops, not at you
3. the standard **two specials** (big dodgeable one + short-range crystal-breaker), same
   contract as every existing boss - see `BossDatabase.SPECIALS`
4. a **visible radius**: a ground ring in the lane colour, and a shimmer on every unit
   inside it

The aura is **not additive across lords**: a unit takes the aura of the *nearest* lord
only. Call it the legend rule. Two lords in a late wave must not multiply into a 2.25x
goblin.

### Red - Goblin Warchief

*Sources: Goblin Chieftain (aura), Krenko Mob Boss (command), Goblin Warchief (name).*

- **Aura "Warband Frenzy"** - other Goblins get **+25% damage, +25% max health, +30%
  move speed, 20% faster swings**. Haste is the identity; red goblins already run at
  x1.3 and this is the one aura the player will *feel* before they see it.
- **Command "Mob Call"** (cd 14s) - spawns **4 goblin melee** at the lord, already inside
  the escort, on the same spawn path `WaveManager` uses. Capped by a live-adds budget so
  a stalled lane cannot be farmed into a soft-lock.
- **Specials** - `Warband Whirl` (circle r5.0, 1.6x) / `Cleaver Chop` (cone r3.8, 120deg,
  1.2x, crystal-breaker, cd 2.0)
- **Counterplay** - the fastest lane in the game gets faster; either kill the lord in the
  first seconds or give ground. Red AoE spells hit the lord *and* its adds, so the
  colour's own answer is already in the player's kit.

### White - Field Marshal

*Sources: Field Marshal (aura), Captain of the Watch + Daru Warchief (toughness, command).*

- **Aura "Hold the Line"** - other white units get **+25% damage, +40% max health** (Daru's
  +0/+2 is a *toughness* lord, so white leans further into health than the shared 25%) and
  a **25 HP damage shield** that refreshes every 6s while they stand in the radius. The
  shield is white's "first strike": trading with a shielded soldier costs you the first
  hit for nothing.
- **Command "Muster the Watch"** (cd 14s) - heals every buffed unit for **20% of max** and
  re-arms every shield at once.
- **Specials** - `Banner Sweep` (cone r6.5, 120deg, 1.8x) / `Marshal's Thrust` (cone r4.2,
  90deg, 1.3x, crystal-breaker, cd 2.0)
- **Counterplay** - the slowest fight of the five and the one that punishes chip damage.
  Burst beats it; sustained plinking never gets through a shield that re-arms.

### Blue - Tidewarden Sovereign (Lord of Atlantis)

*Sources: Lord of Atlantis / Master of the Pearl Trident (aura), Merrow Reejerey (command).*

- **Aura "Islandwalk"** - other blue units get **+25% damage, +25% max health** and **20%
  evasion**: one hit in five simply does not land, with a shimmer and a miss tick so it
  never reads as a bug. Blue is the range colour; making its archers *unhittable* rather
  than tanky keeps the colour honest.
- **Command "Tidal Command"** (cd 14s) - the tap/untap effect, pointed at the player:
  everyone the lord is buffing gets a **2s charge** (the squad charge channel already
  exists: `EnemyBase.apply_squad_charge`) while the player takes a **1.5s slow**. A wall
  of illusions arriving all at once, which is the closest thing to "your blockers do not
  apply" that a tower defense has.
  *Alternative, if a bigger set piece is wanted:* **Mirror Tide** - spawn two illusory
  copies of the lord itself at 15% health with no aura, so focus-fire has to pick.
- **Specials** - `Tidal Lash` (cone r6.5, 110deg, 1.7x) / `Trident Thrust` (cone r4.0,
  80deg, 1.3x, crystal-breaker, cd 2.0)
- **Counterplay** - evasion is a *rate*, so the answer is volume: hit the buffed ranks
  with zones (Rain of Ember, Fog) rather than single big shots, or break the radius.

### Green - Krosan Warchief

*Sources: Krosan Warchief (regeneration, name), Ezuri Renegade Leader (command), Elvish Champion (aura).*

- **Aura "Krosan Vigor"** - other green units get **+25% damage, +25% max health**,
  **regenerate 2% of max health per second** (the elite regeneration channel already
  exists) and **50% knockback/suction resistance**. Green is the colour that does not
  move when you push it.
- **Command "Overrun"** (cd 16s, 1.8s windup) - for **5 seconds**, every buffed unit gets
  **+50% damage and +50% speed**. This is the one command with a real telegraph on the
  *player's* side: a rising roar, a green ring pulse, five seconds to get behind the myrs.
- **Specials** - `Trampling Stomp` (circle r5.5, 2.0x, impact late in the leap) /
  `Antler Sweep` (cone r4.2, 140deg, 1.25x, crystal-breaker, cd 2.2)
- **Counterplay** - regeneration means damage has to *out-pace* it, so green is the lord
  that punishes splitting attention. Kill during Overrun's windup, or not during Overrun
  at all.

### Black - Undead Warchief

*Sources: Undead Warchief (aura), Death Baron (deathtouch), Cemetery Reaper / Lord of the Undead (command).*

- **Aura "Graveborn Command"** - other undead get **+40% damage, +15% max health**
  (Undead Warchief is +2/+1 - the aggressive lord, not the tanky one) and their hits apply
  **Wither**: 6 damage/second for 4s, stacking refresh, which is deathtouch expressed as
  something a player can survive but not ignore. The burn channel (`apply_burn`) already
  does exactly this shape.
- **Command "Raise Dead"** (cd 14s) - consumes up to **3 corpses** within the aura radius
  and raises them at **50% health**, in the lord's own colour. `EnemyBase.corpses()` and
  `consume_corpse()` already exist and already cap the corpse pool, so the ceiling is
  free: a lane the player has not cleaned up is a lane the lord farms.
- **Specials** - `Rot Burst` (circle r6.0, 1.7x) / `Bone Cleaver` (cone r4.0, 130deg,
  1.25x, crystal-breaker, cd 2.3)
- **Counterplay** - the only lord where *how* you killed things matters. Exile kills leave
  no corpse (`EnemyBase.exile()`), so the black lord is the first real argument for
  Exalted Strike and Kill over raw damage.

### Summary table

| Colour | Lord | Aura headline | Command | Scale |
|---|---|---|---|---|
| Red | Goblin Warchief | haste + stats | Mob Call: 4 adds | 1.75 |
| White | Field Marshal | health + 25 HP shield | Muster: heal 20%, re-shield | 1.7 |
| Blue | Tidewarden Sovereign | 20% evasion | Tidal Command: mass charge + player slow | 1.8 |
| Green | Krosan Warchief | regen + knockback resist | Overrun: +50%/+50% for 5s | 2.0 |
| Black | Undead Warchief | +40% damage + Wither | Raise Dead: 3 corpses | 1.8 |

## Implementation

Six phases, each one shippable on its own. Phase 1-2 is a playable lord with no art;
phase 5 is the art; phase 6 is the test that keeps it honest.

### Phase 1 - `BossDatabase` learns about variants

Today three colour-keyed dictionaries describe a boss (`VISUAL_SCENES`, `MODEL_SCALES`,
`SPECIALS`) and three static getters read them. Add a variant layer *above* the colour:

```gdscript
const VARIANT_GIANT := "giant"
const VARIANT_LORD := "lord"

const VARIANTS := {
    VARIANT_GIANT: {
        "Red": {"scene": "res://scenes/bosses/fire_giant.tscn", "model_scale": 2.4, "specials": [...]},
        ...
    },
    VARIANT_LORD: {
        "Red": {
            "scene": "res://scenes/bosses/goblin_warchief.tscn",
            "model_scale": 1.75,
            "display_name": "Goblin Warchief",
            "specials": [...],
            "aura": {...},      # see phase 2
            "command": {...},   # see phase 3
        },
        ...
    },
}
```

Keep the three getters' names and give them a `variant: String = VARIANT_GIANT` default
argument, so every existing call site (`EnemyDatabase.get_enemy_data`,
`EnemyBase.setup`, `tools/tests/boss_specials.gd`) keeps working unchanged. Add
`get_aura(color, variant)` and `get_command(color, variant)`.

The variant has to reach `EnemyDatabase.get_enemy_data` because that is where
`model_scale` is decided, so it grows a third parameter
(`boss_variant: String = ""`) and `EnemyBase._ready()` reads it from the spawn metadata
next to `enemy_color`/`enemy_type`. The chain is:

`WaveManager._spawn_unit` -> `MainController.request_enemy` info dict ->
`MainController._spawn_enemy` `set_meta("boss_variant", ...)` -> `EnemyBase._ready` ->
`EnemyDatabase.get_enemy_data(color, type, variant)`.

That is the same route `elite` / `miniboss` / `boss_modifier` already travel
(`scripts/main.gd:486`), which is what makes it safe in multiplayer: a client rebuilds the
enemy from the spawn argument, so the variant must be *in* that argument and never set on
the server's node afterwards.

> `MODEL_SCALES`' own comment says `boss_anim_reference_scale` is the smallest scale in the
> table so no boss animates faster than 1.0x. Lords are smaller than every giant, so that
> invariant breaks: at 1.75 vs a reference of 2.4 a lord animates at the clamp, 1.35x.
> **That is the right answer** for a warchief - keep the clamp, and correct the comment.
> Lowering the reference to 1.75 instead would slow all five existing bosses to 0.71x.

### Phase 2 - the aura (the actual feature)

The aura has one hard requirement: **it must be revocable**. If killing the lord does not
visibly de-buff the lane, the whole boss is pointless. That rules out the existing
pattern - `apply_elite_modifier`, `apply_miniboss` and `apply_green_mage_buff` all
multiply `enemy_data` *in place*, permanently. So the aura needs its own channel.

On the **buffed unit** (`EnemyBase`):

```gdscript
## Which lord is buffing this unit, or null. Exactly one - the nearest (the legend rule).
var aura_source: Node3D = null
var aura_damage_mult: float = 1.0
var aura_attack_speed_mult: float = 1.0
var aura_speed_mult: float = 1.0
var aura_health_mult: float = 1.0
var aura_shield: float = 0.0        # white
var aura_evasion: float = 0.0       # blue
var aura_regen_per_second: float = 0.0  # green
var aura_wither: Vector2 = Vector2.ZERO # black: (dps, duration)
## Replicated purely so a client can draw the shimmer; the server owns everything else.
var aura_buffed: bool = false
```

Max health is the one that cannot be a bare multiplier, because `enemy_data.health` *is*
the max everywhere (`health_bar.set_health(health, enemy_data.health)`, the flinch
threshold, `_check_boss_enrage`). Introduce one accessor and route those reads through it:

```gdscript
func max_health() -> float:
    return enemy_data.health * aura_health_mult
```

Granting the aura raises `health` by the same absolute amount it raised the max, so a full
unit stays full; revoking it clamps `health = minf(health, max_health())`, so a unit that
was kept alive purely by the lord's aura drops to a sliver rather than dying outright -
losing the buff should not silently kill 25 units and hand the player the wave.

`attack_damage` is read in seven places (`enemy_base.gd:950, 1146, 1253, 1256, 1291, 1304,
1352`). Add `effective_attack_damage()` returning `enemy_data.attack_damage *
aura_damage_mult` and route all seven through it; the same accessor is where a future buff
channel lands for free. `movement_speed_mult()` gains one `mult *= aura_speed_mult` line
(it is already the single place slows, frost and charge compose). `perform_attack()`
multiplies `attack_cooldown` by `aura_attack_speed_mult`.

On the **lord**, the aura is driven as a diff, server-side, on an interval:

```gdscript
## The lord OWNS its membership set, and that is the whole trick: revoking is a loop over
## a set we already have, not a search for everyone we might once have touched.
var _aura_members: Dictionary = {}   # EnemyBase -> true
var _aura_tick: float = 0.0
```

Every `boss_lord_aura_refresh` seconds (0.25s - four times a second is far below what a
player can see and 1/40th the cost of doing it per frame):

1. `_bodies_in_range(boss_lord_aura_radius, 4)` - the enemy collision layer. The helper
   already exists and is a physics broadphase query, not a scan of the `enemies` group.
2. Filter: same `color_identity`, not a Boss, not already claimed by a *closer* lord.
3. Cap at `boss_lord_aura_max_members` (24), nearest first, so a 60-unit late wave cannot
   turn one query into a frame spike.
4. Grant to newcomers, revoke from anyone who left the set, keep the rest untouched.

Revocation also has to happen on `die()`, `exile()` and `_notification(NOTIFICATION_EXIT_TREE)`
for the lord, and a unit's own `die()` must clear itself from its source's set (an
`is_instance_valid` sweep on each tick covers the races, since a queued_free node can sit
in the set for a frame).

**Multiplayer.** Everything above is server-authoritative, like every other enemy
behaviour in this project. `_build_synchronizer()` currently replicates
`[":position", ":rotation", ":health", ":velocity", ":is_dying"]`; add `":aura_buffed"`
and let clients draw the shimmer off that bool. Do not replicate the multipliers - a
client never computes damage.

**Visuals.**

- the lord: `_apply_miniboss_glow()`'s next_pass trick already exists and works on any
  skinned mesh; reuse it with the lane colour, plus a persistent ground ring built the way
  `AttackIndicator` builds its outline (`scripts/attack_indicator.gd` already draws
  circle/cone decals at a radius) but without the fill and without the resolve timer.
- buffed units: the same next_pass material, at lower intensity. It must be *removable*,
  so store the pre-aura surface materials on the unit and restore them on revoke rather
  than duplicating a material per grant.
- the lord's name goes in `health_bar.set_modifier_tag("GOBLIN WARCHIEF", tint)`, which
  already exists for boss modifiers and already shows from spawn.
- death: one announcement through `SignalBus` ("WARBAND FRENZY BROKEN") - the moment the
  ring goes out is the payoff for the whole fight and deserves to be stated.

### Phase 3 - commands

A command is deliberately *not* a third entry in the specials array: specials compete for
range and replace the boss's attack loop, and a command is a support action that should
fire while the lord keeps fighting. The precedent is the miniboss special, which for
exactly this reason keeps its own separate state (`_miniboss_special_windup` and friends,
`enemy_base.gd:83`).

```gdscript
var _command_timer: float = GameSettings.boss_lord_command_first_delay
var _command_windup: float = -1.0
var _command_indicator: AttackIndicator
```

Windup, then resolve, then reset - `_process_miniboss_special` is the shape to copy. The
telegraph is a ring in the lane colour at the aura radius (it is aimed at the lord's own
troops, so the player reads "something is about to happen to all of them", not "get out").

Animation: none of the four existing `ANIM_SETS` in `tools/boss_character_builder.gd` has
a shout/rally clip. Add **one** shared Mixamo clip,
`assets/animations/boss/common/command_shout.fbx` ("Standing Taunt Battlecry" is the right
one), register it as clip `"command"` in all sets, and have `EnemyBase` fall back to
`"special"` when a rig lacks it. One download, five lords.

Each command's payload is 10-30 lines against systems that already exist:

| Lord | Command reuses |
|---|---|
| Red | `MainController.request_enemy` (the same spawn path `WaveManager._spawn_unit` uses) |
| White | `heal()`, plus the new `aura_shield` field |
| Blue | `apply_squad_charge()` for the units, `player.apply_slow()` for the player |
| Green | a timed multiplier on the aura's own numbers - no new channel at all |
| Black | `EnemyBase.corpses()` / `consume_corpse()` and the black mage's existing revive block (`enemy_base.gd:1165`) |

Red's Mob Call needs a live-adds cap in `GameSettings` (and to count its spawns into
`WaveManager.active_enemies`, or the wave never ends).

### Phase 4 - waves: a lord marches with its tribe

This is the one structural change outside the boss scripts, and it is small.

1. **Pick the variant.** A new `_roll_boss_variant(wave_idx, rng)` in `WaveManager`,
   modelled line for line on the existing `_roll_boss_modifier` (`wave_manager.gd:472`):
   returns `"lord"` from `boss_lord_start_wave` (8) with `boss_lord_chance` (0.5),
   else `"giant"`. Rolled inside `_compose_wave`/`_plan_wave` with the wave's own seeded
   rng, so a wave plan stays reproducible end to end.
2. **Do not give a lord its own battle group.** `_plan_wave` currently lifts the boss out
   into a solo group with `wave_boss_delay`. For a lord, instead add a `Boss` unit to that
   colour's own composition (`per_color[color]["Boss"] += 1`) *before* `_partition_colors`
   runs, and add `boss_lord_escort_bonus` melee the same way `_roll_miniboss` adds its
   escort (`wave_manager.gd:367`) - and for the same reason: the extra bodies must exist
   before the wave is partitioned or they get no formation slots.
3. **Let a Boss unit join a squad.** `_deploy_squad` has `if unit_type == "Boss": continue`
   (`wave_manager.gd:177`). That becomes "continue only for the giant variant".
4. **Give it a slot.** `SquadDoctrine.build_formation` already returns
   `slots["Boss"]` (`squad_doctrine.gd:230`) - it is a grid on the squad origin, which is
   the mage core. That is the right *depth* for a warchief (behind the melee screen) but it
   overlaps the casters; offset it half a rank forward. One line.
5. **Announce it.** `_announce_group` (`wave_manager.gd:658`) has a boss branch and a
   miniboss suffix. A lord wants its own wording - `"RED WARCHIEF LEADS THE WARBAND"` -
   because the player's correct response is different from both.

A lord may still roll a `boss_modifier`; the two systems do not touch (modifiers reshape
specials, an aura does not). Riot on a Goblin Warchief is a fine late-wave nightmare.

### Phase 5 - assets

Per lord: a rigged mesh at `assets/enemies/bosses/<key>/<key>.fbx`, an entry in
`BossCharacterBuilder.BOSSES` naming its animation set, and a build run. No new animation
set is needed - all five reuse an existing one:

| Lord | key | anim set | scale |
|---|---|---|---|
| Goblin Warchief | `goblin_warchief` | `standing_melee` | 1.75 |
| Field Marshal | `field_marshal` | `sword_shield` | 1.7 |
| Tidewarden Sovereign | `tidewarden_sovereign` | `sword_shield` | 1.8 |
| Krosan Warchief | `krosan_warchief` | `mutant` | 2.0 |
| Undead Warchief | `undead_warchief` | `zombie` | 1.8 |

Then:

```powershell
"G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_boss_characters.gd
```

The builder normalizes every mesh to 1.7 units and re-grounds each clip per rig, so the
only thing a new mesh has to be is humanoid and Mixamo-rigged. Image prompts are in the
last section.

Sound: `SoundBank.play_at("boss_spawn_" + colour)` fires from `setup()` and needs no
change - a lord arrives in its colour's voice. A lord-specific line is a nice-to-have, not
a blocker.

### Phase 6 - the test that keeps it honest

`tools/tests/boss_lords.tscn` + `.gd`, in the shape of `boss_specials.gd`, run by
`tools/validate_godot.ps1`. Every assertion below is one the design can silently lose:

- every colour has a lord entry; its scene path resolves or degrades; **exactly one**
  crystal-breaker special (the same check `boss_specials.gd:90` makes for giants)
- every `aura` dictionary has every key the code reads - a missing key is a 1.0 multiplier
  and therefore an invisible no-op
- spawn a lord + 6 same-colour units: max health, damage, speed and swing cadence all
  moved by the configured factor, and a 7th unit outside the radius did not
- **revocation**: kill the lord, every buffed unit is back to base, current health clamped
  and never above max, and the lord's member set is empty
- **the legend rule**: two lords overlapping, no unit is buffed twice
- **no friendly fire on tribe lines**: a lord never buffs another colour, another boss, or
  itself
- a unit that dies while buffed leaves no stale entry in `_aura_members`
- each command actually does its thing within `boss_lord_command_cooldown +
  boss_lord_command_windup`: red's add count rose, white's shields re-armed, black
  consumed a corpse it was given, green's overrun window opened and *closed*
- the red add cap holds when the command fires repeatedly into a stalled lane

### Settings block (draft)

All of it belongs in `scripts/game_settings.gd` under a new `Boss lords` heading, next to
the existing `Boss modifiers` block - nothing below may be hardcoded in a feature script.

```gdscript
# --- Boss lords -----------------------------------------------------------------------
@export var boss_lord_start_wave: int = 8
@export var boss_lord_chance: float = 0.5
@export var boss_lord_escort_bonus: int = 6
@export var boss_lord_health_mult: float = 0.7
@export var boss_lord_damage_mult: float = 0.8
@export var boss_lord_speed_mult: float = 1.15
@export var boss_lord_xp_mult: float = 1.2

@export var boss_lord_aura_radius: float = 14.0
@export var boss_lord_aura_refresh: float = 0.25
@export var boss_lord_aura_max_members: int = 24
@export var boss_lord_aura_damage_mult: float = 1.25   # shared baseline
@export var boss_lord_aura_health_mult: float = 1.25

@export var boss_lord_red_speed_mult: float = 1.3
@export var boss_lord_red_attack_speed_mult: float = 0.8   # lower is faster
@export var boss_lord_white_health_mult: float = 1.4
@export var boss_lord_white_shield: float = 25.0
@export var boss_lord_white_shield_refresh: float = 6.0
@export var boss_lord_blue_evasion: float = 0.2
@export var boss_lord_green_regen_pct: float = 0.02
@export var boss_lord_green_knockback_resist: float = 0.5
@export var boss_lord_black_damage_mult: float = 1.4
@export var boss_lord_black_health_mult: float = 1.15
@export var boss_lord_black_wither_dps: float = 6.0
@export var boss_lord_black_wither_duration: float = 4.0

@export var boss_lord_command_cooldown: float = 14.0
@export var boss_lord_command_first_delay: float = 8.0
@export var boss_lord_command_windup: float = 1.6
@export var boss_lord_red_summon_count: int = 4
@export var boss_lord_red_summon_cap: int = 12
@export var boss_lord_white_heal_pct: float = 0.2
@export var boss_lord_blue_charge_duration: float = 2.0
@export var boss_lord_blue_player_slow: float = 1.5
@export var boss_lord_green_overrun_duration: float = 5.0
@export var boss_lord_green_overrun_mult: float = 1.5
@export var boss_lord_black_raise_count: int = 3
@export var boss_lord_black_raise_hp_mult: float = 0.5
```

### Two decisions worth making before writing code

1. **Is a lord immune to control?** `is_immune_to_control()` returns `is_boss()`
   (`enemy_base.gd:2089`), so a lord inherits full immunity to freeze, root, stun, fear and
   pacifism. A lord's whole point is that it hides behind its escort - if it also cannot be
   pulled, slowed or displaced, a melee player has no route to it at all and the answer
   collapses to "have ranged damage". Recommendation: a lord is **immune to hard control
   (freeze/stun) but not to displacement and taunt**, i.e. `is_immune_to_control()` gains a
   lord exemption for the pull effects. This is a balance call, not a technical one.
2. **Does the aura apply to elites and minibosses too?** It composes cleanly with both
   (different channels), but an aura'd miniboss is 4.0 x 1.25 health and 1.6 x 1.25 damage.
   Recommendation: yes, allow it - a wave that stacks a miniboss and a lord in one lane
   *should* be the hardest thing the game does at that point - but the test must assert the
   product, so the number is one somebody chose rather than one that happened.

## Image generation prompts

One prompt per lord. These feed the pipeline in `docs/AI_WORKSPACE.md`: generate the image,
run it through Meshy **image-to-3D** (or use the prompt directly as text-to-3D), auto-rig
the result in Mixamo, drop the FBX at `assets/enemies/bosses/<key>/<key>.fbx`, register it
in `BossCharacterBuilder.BOSSES` and run the builder.

### Shared constraints

Already embedded in every prompt below; repeated here so it can be re-attached if a prompt
is rewritten. Most of it exists to survive **auto-rigging**, which fails on crossed limbs,
fused silhouettes and floating props:

> Full-body character concept, head to toe, centred, feet flat on an invisible ground line.
> Standing symmetrical A-pose: arms held down and out at roughly 45 degrees, clearly
> separated from the torso with visible gaps at the armpits, legs shoulder-width apart,
> both hands open and away from the body, nothing crossing or overlapping the silhouette.
> Straight-on orthographic front view at chest height, no perspective distortion, no
> foreshortening. Plain flat neutral grey background, no scenery, no ground plane, no cast
> shadow, no vignette. Even diffuse studio lighting, no rim light, no dramatic key light,
> no lens flare. Stylized game-ready realism: readable at 30 metres, bold silhouette,
> chunky forms, no fine filigree. No motion blur, no depth of field, no glow, no particles,
> no text, no logos, no cropping.

Every lord additionally needs **one silhouette-defining rally element** - a banner, horn,
standard or totem - because that is what tells the player at a glance that this boss is the
one buffing the others. Keep it **attached to the body and inside the silhouette**: a
free-flying flag will not survive auto-rigging.

### Red - Goblin Warchief (`goblin_warchief`, scale 1.75, set `standing_melee`)

> Full-body character concept of a goblin warchief, a stocky green-skinned goblin warlord
> built broad rather than tall, hunched powerful shoulders, long pointed ears, a jutting
> underbite with iron-capped teeth, small furious yellow eyes. Scavenged plate scraps
> riveted over boiled leather, a spiked iron warboss helmet with a crest of red-dyed hair,
> one oversized pauldron made from a cooking pot. A short heavy cleaver held low in the
> right hand, a crude war horn of blackened brass lashed across his back, and a small
> tattered red banner on a stub pole strapped upright to his backpack bearing a crude
> goblin skull daubed in soot - banner furled tight against the pole, inside the
> silhouette. Bandoliers of nails, mismatched boots. Aggressive, fast, filthy, clearly the
> one giving the orders. Full-body character concept, head to toe, centred, feet flat on an
> invisible ground line. Standing symmetrical A-pose: arms held down and out at roughly 45
> degrees, clearly separated from the torso with visible gaps at the armpits, legs
> shoulder-width apart, both hands open and away from the body, nothing crossing or
> overlapping the silhouette. Straight-on orthographic front view at chest height, no
> perspective distortion. Plain flat neutral grey background, no scenery, no ground plane,
> no cast shadow. Even diffuse studio lighting, no rim light. Stylized game-ready realism:
> readable at 30 metres, bold silhouette, chunky forms, no fine filigree. No motion blur,
> no depth of field, no glow, no particles, no text, no logos, no cropping.

**Texture prompt:** Sickly yellow-green goblin skin with darker mottling, scorched
blackened iron and rust-pitted steel, oxblood-red cloth and hair crest, greasy brown
leather, soot smears. Saturated warm reds and iron greys, game-ready PBR, no baked
lighting.

```powershell
./tools/meshy_asset.ps1 -Name "boss-goblin-warchief" -Prompt "<prompt above>" -TexturePrompt "<texture prompt above>" -ModelType standard -TargetPolycount 12000 -DryRun
```

### White - Field Marshal (`field_marshal`, scale 1.7, set `sword_shield`)

> Full-body character concept of a human field marshal, an upright veteran knight-captain
> in gleaming ceremonial plate armour, broad-shouldered, disciplined bearing, weathered
> clean-shaven face with a scar across one cheek, short grey hair. Fluted white-enamelled
> plate with gold filigree edges at the pauldrons and greaves, a long white tabard bearing
> a stylized golden sun sigil, a plumed open-faced helm with a white crest. A straight
> broadsword held point-down in the right hand and a tall kite-shaped tower shield on the
> left arm, and a short command standard - a white pennant on a rigid gold-capped pole -
> socketed into his backplate and held tight against the body, inside the silhouette.
> Chain skirt, gauntlets, a horn at the belt. He looks like the reason the rank behind him
> is holding. Full-body character concept, head to toe, centred, feet flat on an invisible
> ground line. Standing symmetrical A-pose: arms held down and out at roughly 45 degrees,
> clearly separated from the torso with visible gaps at the armpits, legs shoulder-width
> apart, nothing crossing or overlapping the silhouette. Straight-on orthographic front
> view at chest height, no perspective distortion. Plain flat neutral grey background, no
> scenery, no ground plane, no cast shadow. Even diffuse studio lighting, no rim light.
> Stylized game-ready realism: readable at 30 metres, bold silhouette, chunky forms, no
> fine filigree. No motion blur, no depth of field, no glow, no particles, no text, no
> logos, no cropping.

**Texture prompt:** Polished white-enamelled steel with warm gold trim, clean ivory cloth
with a gold sun emblem, pale blue-grey chainmail, honest wear at the edges without grime.
High-key whites and golds, game-ready PBR, no baked lighting.

```powershell
./tools/meshy_asset.ps1 -Name "boss-field-marshal" -Prompt "<prompt above>" -TexturePrompt "<texture prompt above>" -ModelType standard -TargetPolycount 12000 -DryRun
```

### Blue - Tidewarden Sovereign (`tidewarden_sovereign`, scale 1.8, set `sword_shield`)

> Full-body character concept of a merfolk sovereign, a tall regal amphibious humanoid with
> smooth blue-teal skin, faint iridescent scales across the shoulders and forearms,
> webbed three-fingered hands, a translucent dorsal fin crest running over the skull in
> place of hair, large pale luminous eyes, gill slits at the neck. Armour of overlapping
> nacre plates and lashed coral, a high collar of fanned pearl-white shell, a crown of
> branching coral set with a single large pearl. A long ornate trident held upright in the
> right hand, a round shield of fused abalone shell on the left arm, and a rigid ceremonial
> standard of woven kelp and shell discs mounted on the back, held tight against the body
> and inside the silhouette. Trailing fin membranes along the calves and elbows, kept close
> to the limbs. Cold, imperious, unhurried. Full-body character concept, head to toe,
> centred, feet flat on an invisible ground line. Standing symmetrical A-pose: arms held
> down and out at roughly 45 degrees, clearly separated from the torso with visible gaps at
> the armpits, legs shoulder-width apart, nothing crossing or overlapping the silhouette.
> Straight-on orthographic front view at chest height, no perspective distortion. Plain
> flat neutral grey background, no scenery, no ground plane, no cast shadow. Even diffuse
> studio lighting, no rim light, no underwater caustics. Stylized game-ready realism:
> readable at 30 metres, bold silhouette, chunky forms, no fine filigree. No motion blur,
> no depth of field, no glow, no particles, no text, no logos, no cropping.

**Texture prompt:** Deep teal and cobalt skin with subtle iridescent scale sheen,
pearlescent nacre armour with cool violet shifts, pale coral pink accents, dark kelp-green
leather bindings. Cold saturated blues, game-ready PBR, no baked lighting, no emissive
glow.

```powershell
./tools/meshy_asset.ps1 -Name "boss-tidewarden-sovereign" -Prompt "<prompt above>" -TexturePrompt "<texture prompt above>" -ModelType standard -TargetPolycount 12000 -DryRun
```

### Green - Krosan Warchief (`krosan_warchief`, scale 2.0, set `mutant`)

> Full-body character concept of a beast warchief, a huge hunched hybrid of elk and ogre:
> heavy digitigrade legs, a barrel chest wrapped in coarse moss-green fur, thick bark-like
> plating across the shoulders and forearms, enormous branching antlers hung with bone
> charms and braided vine. A broad flat-nosed animal face with amber eyes and tusks, heavy
> brows, moss growing in the hollows of the shoulders. Armour of lashed timber, hide straps
> and river stones; a gnarled totem club in the right hand, its head a knot of living wood
> sprouting real leaves; and a short totem standard of stacked animal skulls and antler
> bound upright to his back, held tight against the body and inside the silhouette.
> Immovable, territorial, overgrown - something the forest promoted. Full-body character
> concept, head to toe, centred, feet flat on an invisible ground line. Standing
> symmetrical A-pose: arms held down and out at roughly 45 degrees, clearly separated from
> the torso with visible gaps at the armpits, legs shoulder-width apart, nothing crossing
> or overlapping the silhouette. Straight-on orthographic front view at chest height, no
> perspective distortion. Plain flat neutral grey background, no scenery, no ground plane,
> no cast shadow. Even diffuse studio lighting, no rim light. Stylized game-ready realism:
> readable at 30 metres, bold silhouette, chunky forms, no fine filigree. No motion blur,
> no depth of field, no glow, no particles, no text, no logos, no cropping.

**Texture prompt:** Deep moss-green fur over grey-brown bark plating, wet dark earth
tones, pale bone and antler, lichen blooms in sage and ochre, fresh green leaf accents.
Saturated forest greens with warm brown support, game-ready PBR, no baked lighting.

```powershell
./tools/meshy_asset.ps1 -Name "boss-krosan-warchief" -Prompt "<prompt above>" -TexturePrompt "<texture prompt above>" -ModelType standard -TargetPolycount 12000 -DryRun
```

### Black - Undead Warchief (`undead_warchief`, scale 1.8, set `zombie`)

> Full-body character concept of an undead warchief, a tall armoured zombie warlord,
> desiccated grey-violet flesh stretched over a heavy frame, one side of the ribcage
> exposed through broken plate, a lower jaw wired shut with iron, sunken sockets lit with
> cold pale light, patchy long black hair. Corroded funeral armour: a pitted blackened
> breastplate, an asymmetric spiked pauldron, a crown of fused finger bones and rusted
> iron. A heavy notched grave-cleaver in the right hand; a grim standard - a crossbar of
> bone hung with three shrunken skulls and strips of burial shroud - bound upright to the
> spine, held tight against the body and inside the silhouette. Dangling chains, dried
> grave soil, shroud wrappings at the forearms. Slow, certain, in command of the dead.
> Full-body character concept, head to toe, centred, feet flat on an invisible ground line.
> Standing symmetrical A-pose: arms held down and out at roughly 45 degrees, clearly
> separated from the torso with visible gaps at the armpits, legs shoulder-width apart,
> nothing crossing or overlapping the silhouette. Straight-on orthographic front view at
> chest height, no perspective distortion. Plain flat neutral grey background, no scenery,
> no ground plane, no cast shadow. Even diffuse studio lighting, no rim light. Stylized
> game-ready realism: readable at 30 metres, bold silhouette, chunky forms, no fine
> filigree. No motion blur, no depth of field, no glow, no particles, no text, no logos,
> no cropping.

**Texture prompt:** Grey-violet desiccated skin with dark necrotic mottling, blackened
pitted iron with orange rust bleed, bleached bone, dirty grey burial linen, dried earth.
Desaturated purples and near-blacks with one cold pale accent in the eye sockets,
game-ready PBR, no baked lighting.

```powershell
./tools/meshy_asset.ps1 -Name "boss-undead-warchief" -Prompt "<prompt above>" -TexturePrompt "<texture prompt above>" -ModelType standard -TargetPolycount 12000 -DryRun
```

### Notes on the generation step

- `-ModelType standard -TargetPolycount 12000` rather than the `smart-topology` default the
  prop pipeline uses: these are hero assets that will be seen at 2 metres during a boss
  fight, and `docs/AI_WORKSPACE.md` names that combination for exactly this case.
- Always `-DryRun` first, and never spend credits unless the request was explicit - see
  `.agents/AGENTS.md`.
- Auto-rig rejects models whose limbs fuse into the torso. If a generated mesh comes back
  with the arms welded to the sides, regenerate with the armpit-gap clause emphasised
  rather than trying to fix it in the rigger.
- Check each result against the existing bosses for *scale consistency* before committing:
  the builder normalizes height to 1.7 units, so a mesh whose proportions read as
  3 metres tall will look wrong at `model_scale` 1.75, however good the model is.
