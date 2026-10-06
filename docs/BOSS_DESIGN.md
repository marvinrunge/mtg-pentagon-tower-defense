# Boss Design

Every fifth wave a boss leads alone down one lane. Each of the five colours has its own, and
each fights in **three phases** that change how it plays as it loses health. This document is
what each boss is meant to feel like and where every piece of that lives.

## What every boss shares

- **Only telegraphed attacks.** A boss has no ordinary swing. Everything it does draws a
  danger zone on the ground first, and the hit lands when the zone's fill completes. No tell
  is ever shorter than `boss_modifier_min_windup_seconds` (0.6 s), whatever shrank it.
- **One crystal-breaker.** Only the melee special (`hits_crystal`) can damage the crystal,
  because the crystal cannot dodge. It is in play in every phase.
- **Three phases**, split at 66 % and 33 % of maximum health (`boss_phase2_threshold`,
  `boss_phase3_threshold`). A phase change is one-way. A hit big enough to cross both lines
  goes straight to phase 3 with one transition.
- **The transition.** Once the special in flight finishes, the boss stops, roars (its own
  arrival sound), lets out a telegraphed shockwave (radius 8, x0.6 damage) and the HUD names
  the new phase. Whatever the new phase brings in is ready about two seconds later.
- **Phase 2 answers being kited.** Four of the five gain an attack that reaches a player who
  stands off. Black answers distance differently, by raising the dead.
- **Phase 3 turns a known attack into a new one.** The player has to unlearn something.
- **Exposed.** After its signature special each boss stands open for a moment, rooted and
  taking extra damage. What earns that window is different for every boss.

## The five bosses

Base numbers after the colour modifiers (`EnemyDatabase`): Red 480 HP / speed 1.56, Blue 800 /
1.2, Green 1200 / 0.96, White 960 / 1.2, Black 800 / 1.08. All scale with wave and party size.

### Red: Fire Giant, pressure and tempo

Never lets you stand still. Many small threats, short tells, the ground fills with fire.

| Phase | Kit |
| --- | --- |
| 1 | **Whirlwind** (circle 6.5), **Cleaving Blow** (cone 120°, melee) |
| 2 *KINDLED* | + **Meteor Strike**: a circle (r 3) under *every* player within 25, plus one beside a random one. 1.4 s tell, x1.4. Each leaves burning ground (r 2.5, 4 s). |
| 3 *UNBOUND* | Whirlwind becomes **Unbound Whirlwind**: walks at its target while spinning (x0.6 speed), three hits 0.5 s apart. Cleaving Blow every 1.6 s instead of 2.2 s. |

Exposed: 2 s, x1.5, after the Unbound Whirlwind.

### Blue: Frost Giant, control of space

Slow, heavy and readable, but it slows you and takes ground away.

| Phase | Kit |
| --- | --- |
| 1 | **Glacial Sweep** (circle 7, slows 2 s), **Rime Cleave** (melee) |
| 2 *WINTER'S GRIP* | + **Ice Lances**: three lines fanned at 0/±25° toward the nearest player, 14 x 1.6, 1.2 s tell. Glacial Sweep now leaves a frozen ring at its edge (6–7.5) that slows for 5 s. |
| 3 *ABSOLUTE ZERO* | + **Absolute Zero**: a ring from 3 to 12, 2 s tell. The middle is safe. A Rime Cleave follows at once on the nearest player. |

Exposed: 2.5 s, x1.6, after Absolute Zero.

### Green: Treant, unstoppable weight

The biggest and toughest. Long tells, huge damage, and it brings the forest.

| Phase | Kit |
| --- | --- |
| 1 | **Rooted Slam** (circle 5.5), **Bough Smash** (melee) |
| 2 *THE FOREST WAKES* | Rooted Slam becomes **Uprooting Leap**: jumps onto the *farthest* player within 20; the zone is drawn where it lands. Slows whoever it hits. Three **saplings** grow around it. |
| 3 *EARTHQUAKE* | Every landing sends two **aftershock** rings outward (5–8, then 8–11), 0.8 s apart. |

Saplings are stationary, smaller Green melee tagged SAPLING. Any still standing after 10 s
heals the treant by 5 % of its maximum health and withers (no rewards).
Exposed: 2 s, x1.5, after each leap.

### White: Paladin, discipline and duelling

The smallest and most precise. Lines and crosses, and a shield you have to walk around.

| Phase | Kit |
| --- | --- |
| 1 | **Radiant Slash** (cone 130°), **Consecrated Thrust** (melee) |
| 2 *SHIELD WALL* | **Shield Wall**: hits from inside his front 120° do 70 % less. + **Judgment**: a cross (16 x 2) centred on a random player within 20, 1.5 s tell. |
| 3 *CONSECRATED* | Radiant Slash becomes **Twin Slash**: forward, then straight back. + **Consecration**: kneels 4 s and heals 15 % at the end. 8 % of his maximum health in damage during the channel breaks it. |

Exposed: 3 s, x1.5, only when a Consecration is broken. The shield is down while exposed.

### Black: Zombie Lord, attrition and the hunt

Gets stronger the longer the fight lasts. Hunts the weakest and raises the dead.

| Phase | Kit |
| --- | --- |
| 1 | **Charging Headbutt**: a real charge along a 10 x 2.5 line; it runs the line after it strikes. **Grave Maul** (melee) |
| 2 *THE DEAD RISE* | + **Raise Dead**: up to 4 corpses within 12 get back up as Black melee at half health, with a 2 s tell on each corpse. Every hit on a player heals him 20 % of the damage. |
| 3 *THE HUNT* | Headbutt becomes **The Hunt**: charges the player with the lowest health share, turns and charges them again. |

Kill and Exalted Strike leave no corpse, which gives them a real job against him. His lane's
fog thickens for 6 s at each phase change. Exposed: 2 s, x1.5, after the Hunt.

### Enrage

With phases everywhere, Enrage is now a boss that reaches them early (75 % and 45 %) and
hits x1.25 harder once in phase 3. The other modifiers are unchanged. Cataclysm and
Bloodthirst treat every phase special as "big".

## How a special is built

A special in `BossDatabase.SPECIALS` is a **timeline of strikes**: the main one plus any
`followups`. Each strike draws its own telegraph when it starts and lands when that telegraph
fills, so every hit in a combo has a tell. The full list of keys is documented above
`SPECIALS`. In short:

- **shape**: `circle`, `cone`, `ring` (safe middle), `line` (fan with `lines`), `cross`
- **target**: `current`, `nearest_player`, `farthest_player`, `weakest_player`,
  `random_player`, `each_player`
- **anchor**: `self`, `target` (centred where the target stands), `follow` (rides on the
  boss); followups also take `same` and `retarget`
- **move**: `charge`, `leap`, `follow`
- **slow**, **hazard** (`BossHazard`), **exhaust**, **kind** (`raise_dead`, `consecrate`)
- **phases**, **priority**, **cooldown_by_phase**

What a strike draws is exactly what it hits: `EnemyBase._offset_in_shape` and
`AttackIndicator` describe the same geometry.

## Where to change things

| I want to change | Look in |
| --- | --- |
| a boss's attacks, their numbers, which phase has them | `BossDatabase.SPECIALS` |
| phase names, shockwave tint, lifelink, shield, saplings, fog | `BossDatabase.PHASES` |
| phase thresholds, transition, shield, saplings, raise dead | `GameSettings`' Boss phases block |
| modifiers (Riot, Enrage, ...) | `GameSettings`' Boss modifiers block, `EnemyBase.apply_boss_modifier` |
| how a special plays out | `EnemyBase`, the BOSS SPECIAL ATTACK section |
| how a telegraph looks | `AttackIndicator` |
| burning / frozen ground | `BossHazard` |

## Multiplayer

The boss AI runs on the server only. Everything a player has to **see** travels:

- **Telegraphs and clips** go through `EnemyBase._emit_boss_fx`: shown on the host and sent
  to every client as plain data (`_net_boss_fx`). Each client draws its own telegraphs, which
  resolve themselves when their fill completes, and holds the boss's clip instead of falling
  back to walk-or-stand. A cancel (death, broken Consecration) travels too.
- **Phase banners and the fog surge** travel with `_net_phase_banner`.
- **Hazards, saplings and raised dead** are spawned through the existing `request_effect` /
  `request_enemy` spawners.
- **Slows** on a remote player are handed to the peer that drives that player
  (`Player._net_apply_slow`). Before this, a slow on a client's avatar did nothing.
- **Sounds and camera shake** go through `NetFx`.

## Tests

```
godot --headless --path . res://tools/tests/boss_specials.tscn
godot --headless --path . res://tools/tests/boss_modifiers.tscn
godot --headless --path . res://tools/tests/boss_phases.tscn
godot --headless --path . res://tools/tests/boss_soak.tscn
```

- `boss_specials`: the phase-1 pair, one crystal-breaker, every clip exists on its rig.
- `boss_modifiers`: the six modifiers, including Enrage's earlier phases.
- `boss_phases`: every shape's hit test, phase thresholds and transitions, and each colour's
  mechanic driven by hand.
- `boss_soak`: each boss fights two stand-in players through all three phases in the real
  game loop at 3x speed. It checks that every boss reaches phase 3, uses a phase special by
  itself, roars, gets exposed and (Red, Green, White) reaches the player standing off. Read
  the log for script errors too, not only the verdict.

Headless runs that load `main.tscn` crash on exit after printing their verdict. Read the
`TEST RESULT` line, not the exit code.
