# Spell Reference

This document describes the currently implemented player abilities. Runtime values in
`scripts/game_settings.gd`, `scripts/player.gd`, and `scripts/projectile.gd` take
precedence over older skill-tree tooltip text.

## General Rules

| Rule | Value |
|---|---:|
| Active spells per color | 5 |
| Infinite affinity nodes per color | 1 |
| Affinity rank cost | 1 matching mana |
| Active spell costs | 1, 3, 7, 15, 30 matching mana |
| Active spell affinity gates | Rank 1, 5, 10, 15, 25 |
| Maximum charge time | 2 seconds |
| Minimum released charge | 20% |
| Multicolor access | Any color can be ranked and unlocked |
| Active hotbar branch | Selected by clicking an unlocked spell or investing in its affinity |

## Color Affinities

Affinity ranks are unlimited and use diminishing returns. Ranks 1-10 grant 2% each,
ranks 11-20 grant 1% each, and ranks 21+ grant 0.5% each.

| Color | Card | Mana | Mechanic | Identity |
|---|---|---|---|---|
| White | Holy Strength | `{W}` | +% life regeneration | Protection, restoration, and enduring light. |
| Blue | Curiosity | `{U}` | +% cooldown recovery | Mind-speed, mental acuity, and tactical flow. |
| Black | Vampiric Link | `{B}` | +% lifesteal from actual enemy HP removed | Dark bargains, parasitic drain, and vital siphon. |
| Red | Reckless Charge | `{R}` | +% total player damage | Explosive aggression, raw power, and volatility. |
| Green | Wild Growth | `{G}` | +% maximum HP | Primal vitality, physical mass, and resilience. |

| Rank | Bonus gained in band | Total bonus at band end |
|---:|---:|---:|
| 1-10 | 2% per rank | 20% at rank 10 |
| 11-20 | 1% per rank | 30% at rank 20 |
| 21+ | 0.5% per rank | 32.5% at rank 25; unlimited thereafter |

## Basic Attack

| Ability | Cooldown | Range | Damage | Knockback | Details |
|---|---:|---:|---:|---:|---|
| Basic Attack | 0.5s | 3.5m | 20 | 6 | Hits the aimed enemy or one enemy in the forward cone. Holding the attack button repeats it for 40 base DPS. |

## Red - Aggression

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Shock / Lightning Bolt | 1 | 2.5s | No | 70 | Projectile | Fast projectile. After at least three path spells are unlocked, it launches a second projectile at another enemy for 60% damage (42). |
| 2 | Fireball | 3 | 5s | Yes | 50.4-108 | 2.82-4.5m blast | Projectile that explodes on contact. Both impact damage and blast radius scale with charge. |
| 3 | Rain of Ember | 7 | 9s | No | 25 DPS | 6m zone | Places a ground-targeted burning zone for 5s, dealing up to 125 damage to enemies that remain inside. |
| 4 | Act of Treason | 15 | 7s | No | 70 | 4m | Short-range strike with 12 knockback and a 2s stun. |
| 5 | Chandra's Ignition | 30 | 11s | No | 120 | 8m radius | Damages every nearby enemy and pushes each one outward with 15 force. |

## Blue - Control

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Unsummon | 1 | 3s | No | 35 | Projectile | Applies 14 knockback. Hitting a wall or obstacle during knockback deals 80 additional impact damage. |
| 2 | Aetherize | 3 | 7s | Yes | - | 12m frontal area | Pushes enemies in front of the player with 3.6-18 force. It can cause Unsummon-style impact damage when enemies collide with obstacles. |
| 3 | Psionic Blast | 7 | 6s | No | 100 | 30m ray | Damages one aimed enemy and costs the caster 10 HP. |
| 4 | Freeze Breath | 15 | 4.5s | No | 90 shatter | 10m cone / 4m shatter | Adds one Chill stack to enemies in the cone. At three stacks, the target freezes for 3s and creates a 90-damage Shatter explosion. |
| 5 | Counterspell | 30 | 14s | No | - | Self | Opens a 1.5s parry window. The first incoming hit is negated and all active spell cooldowns are cleared. |

## Green - Strength

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Titanic Growth | 1 | 2s | No | `20 + 35% max HP` | 4m cone | Damages every enemy in the frontal cone. It deals 55 damage at the default 100 maximum HP. |
| 2 | Hurricane / Entangle | 3 | 8s | Yes | 20 DPS | 1.4-7m radius | Roots enemies for 3s and creates a poison zone for 3s. Charge changes radius, not damage or duration. |
| 3 | Overrun | 7 | 7s | No | 60 | Approx. 12m dash | Dashes at 20m/s for 0.6s. Each contacted enemy is hit once and receives 10 forward knockback. |
| 4 | Rabid Bite | 15 | 6s | No | 75 | 4m ray | If the target is rooted, heals the player for 50% of damage dealt (normally 37.5 HP). |
| 5 | Briar Patch | 30 | 16s | No | 30% reflection | Self | For 10s, reflects 30% of incoming melee damage to its attacker. The player still receives the original damage. |

## White - Protection

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Swords to Plowshares | 1 | 4.5s | No | 50% enemy max HP, cap 120 / heal 60 | Projectile | Damages enemies based on maximum HP. If it hits a healable ally, it restores 60 HP instead. |
| 2 | Path to Exile | 3 | 8s | Yes | `(40 + 50% missing HP) x charge` | Projectile / 3m trail | Execute projectile whose damage scales with missing HP and charge. Leaves a holy zone dealing 15 DPS for 4s. |
| 3 | Wrath of God | 7 | 18s | Yes | 5%-25% enemy max HP / heal 15-75 | 2-10m radius | Heals the player, crystal, and nearby allies. Damages and blinds nearby enemies for 3s. All values scale with charge. |
| 4 | Pacifism | 15 | 10s | No | - | 25m ray | Reduces target attack damage by 50% for 6s, clears player and Myr aggro, and redirects the enemy toward the crystal. |
| 5 | Gideon's Reproach | 30 | 14s | No | 40% reflection | Self | For 8s, reflects 40% of incoming damage when the attacker is known. Works against melee and ranged attacks. |

## Black - Sacrifice

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Drain Life | 1 | 4s | No | 70 / heal 45.5 | Projectile | Heals the caster for 65% of damage dealt. |
| 2 | Toxic Deluge | 3 | 10s | Yes | 6-30 DPS | 7m zone | Costs 4%-20% of current HP and creates a poison zone for 5s. Deals 30-150 total damage at minimum-to-full charge. |
| 3 | Doom Blade | 7 | 7s | No | 80 | 5m ray | Curses the target for 6s, increasing subsequent damage taken by 30%. |
| 4 | Tendrils of Agony | 15 | 8s | No | 45 per target / heal 22.5 per target | 15m radius | Normally hits one target. If another spell was cast within the previous 3s, it hits up to three targets. |
| 5 | Sign in Blood | 30 | 20s | No | Costs 15% current HP | Self | Clears every active skill cooldown, then starts its own 20s cooldown. |

## Charge Formulas

Charged spells use a charge multiplier between `0.2` and `1.0`.

| Spell | Formula |
|---|---|
| Fireball damage | `60 x (0.6 + 1.2 x charge)` |
| Fireball radius | `3 x (0.8 + 0.7 x charge)` |
| Aetherize force | `18 x charge` |
| Hurricane radius | `7 x charge` |
| Path to Exile damage | `(40 + 0.5 x missing HP) x charge` |
| Wrath of God radius | `10 x charge` |
| Wrath of God healing | `75 x charge` |
| Wrath of God damage | `25% enemy max HP x charge` |
| Toxic Deluge HP cost | `20% current HP x charge` |
| Toxic Deluge DPS | `30 x charge` |