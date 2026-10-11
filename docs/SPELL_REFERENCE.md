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
| Active spell rank cost | 1 skill point per rank |
| Active spell level gates | Team levels 1, 3, 5, 7, 9 |
| Maximum charge time | 3 seconds (`GameSettings.spell_charge_max_time`) |
| Minimum released charge | 20% |
| Multicolor access | Any color can be ranked and unlocked |
| Active hotbar branch | Selected by clicking an unlocked spell or binding it from the skill tree |

## Color Affinities

Affinity ranks are unlimited and use diminishing returns towards a ceiling per colour
(`GameSettings.affinity_first_rank` / `affinity_cap`): the first rank gives the first value,
and every rank after closes the same share of the remaining gap to the ceiling.

| Color | Card | Mana | Mechanic | Identity |
|---|---|---|---|---|
| White | Holy Strength | `{W}` | +% of max HP regenerated per second | Protection, restoration, and enduring light. |
| Blue | Curiosity | `{U}` | +% cooldown recovery | Mind-speed, mental acuity, and tactical flow. |
| Black | Vampiric Link | `{B}` | +% lifesteal from basic attacks (swings and kick) | Dark bargains, parasitic drain, and vital siphon. |
| Red | Reckless Charge | `{R}` | +% total player damage | Explosive aggression, raw power, and volatility. |
| Green | Wild Growth | `{G}` | +% maximum HP | Primal vitality, physical mass, and resilience. |

| Colour | Rank 1 | Rank 5 | Rank 10 | Ceiling |
|---|---:|---:|---:|---:|
| White (max HP / s) | 0.6% | 2.0% | 2.7% | 3% |
| Blue (cooldown recovery) | 8% | 27% | 36% | 40% |
| Black (lifesteal, basic attacks) | 5% | 18% | 25% | 30% |
| Red (damage) | 10% | 34% | 45% | 50% |
| Green (max HP) | 10% | 34% | 45% | 50% |

## Basic Attack

| Ability | Cooldown | Range | Damage | Knockback | Details |
|---|---:|---:|---:|---:|---|
| Basic Attack | 0.5s | 3.5m | 20 | 6 | Hits the aimed enemy or one enemy in the forward cone. Holding the attack button repeats it for 40 base DPS. |

## Red - Aggression

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Fireball | 1 | 5s | Yes | Charged | Blast radius | Charged explosive projectile with a scaling blast radius. |
| 2 | Fire Dash | 1 | 8s | No | Trail damage | Dash | Dashes forward and leaves a burning trail. |
| 3 | Rain of Ember | 1 | 9s | No | 40 DPS for 5s | Ground zone | Creates a burning zone that damages enemies inside it. |
| 4 | Fire Cone | 1 | Refill | No | 55 DPS / slow | Frontal cone | Hold to burn and slow enemies while moving. The meter lasts up to 5s and then refills. |
| 5 | Lightning Bolt | 1 | 12s | No | Single-target damage | Aimed area | Calls lightning down on a precisely aimed target area. Bosses and elites take roughly double. |

## Blue - Control

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Unsummon | 1 | 9s | No | Wall impact only | Cone | Applies 21 knockback plus 7.5 of upward lift, so enemies are thrown off the ground and land stunned. No damage of its own: an enemy thrown into a wall or obstacle takes 80 impact damage (120 more against Wall of Frost). |
| 2 | Frost Breath | 1 | 12s | No | Damage / slow | Area | Freezes nearby enemies and damages them; bosses are briefly slowed instead. |
| 3 | Suction | 1 | 11s | No | Pull | Area | Pulls nearby enemies into one location for 6s (10s at rank 5) - always shorter than the cooldown. Overlapping vortexes cover more ground but never pull one enemy harder. |
| 4 | Wall of Frost | 1 | 16s | No | Projectile block / combo | Placed wall | Raises an ice wall. Unsummon deals bonus damage when it slams enemies into it. |
| 5 | Displace | 1 | 10s | No | Mobility | Blink | Blink a short distance to the aimed ground point; 0.6s of invulnerability on arrival. |

## Green - Strength

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Titanic Brawl | 1 | 8s | No | Landing damage | Leap | Leaps forward and slams the ground on landing. |
| 2 | Giant Growth | 1 | 22s | No | Maximum HP | Self | Grows the player temporarily and increases maximum health. |
| 3 | Fog | 1 | 18s | No | Damage suppression / slow | Ground zone | Creates fog where enemies deal no damage and wade rather than walk. Prevented damage is shown over each attacker. |
| 4 | Roar | 1 | 16s | No | Taunt | Area | Forces nearby enemies to target the player. |
| 5 | Ironbark | 1 | 20s | No | Damage reduction | Self | Reduces damage and prevents knockback, stun, and freeze. |

## White - Protection

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Exalted Strike | 1 | 8s | No | Melee buff | Self | The next 2 melee hits (3 at rank 5) deal x4 and reach further; kills are exiled. |
| 2 | Circle of Protection | 1 | 18s | No | Temporary shield | Ally area | Shields every nearby ally for 8s, a little more per ally present. Recasting refreshes rather than stacks. |
| 3 | Reprisal Ward | 1 | 16s | No | Reflect / block | Self | Reflects damage and grants a chance to block attacks. |
| 4 | Wrath of God | 1 | 20s | No | Area damage | Area | Deals heavy damage to nearby enemies. |
| 5 | Rally the Fallen | 1 | 45s | No | Revive / heal | Ally area | Revives downed teammates and heals surviving allies and myrs. |

## Black - Death as a Resource

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Doom Blade | 1 | 7s | No | Line damage | 20m line, 36m at rank 5 | Sends a black blade along the camera aim line through enemies. Rank buys reach, not width. |
| 2 | Contagion | 1 | 12s | No | Damage over time, spreading | Aimed target, 4.5m jumps | Plagues the enemy in the sights; every second it jumps to the nearest uninfected enemy, up to 8 victims (12 at rank 5). Replaced Fear. |
| 3 | Kill | 1 | 40s (24s at rank 5) | No | Execute | Single target | Instantly kills an enemy; bosses and minibosses must be below 25% health (35% at rank 5). |
| 4 | Wall of Souls | 1 | 20s | No | Damage amplifier | Wall | Enemies crossing the wall take increased damage. |
| 5 | Zombify | 1 | 30s | No | Melee damage | Corpse area | Raises corpses as ghouls that sprint at the nearest enemy and fight it (22 damage per swing every 1.2s at rank 1). With Mayhem Devil they also burst when killed or on expiry (90 damage in 3.5m). |

## Charge Formulas

Currently, only Fireball is chargeable. Its charge multiplier ranges from `0.2` to
`1.0` when the cast is released - a full-power Fireball therefore takes the whole
3-second window, and the charge fires by itself once it closes.

The caster is not idle while it builds: the cast clip's lead-in is stretched across the
charge window, so the wind-up is visibly held for as long as the button is down, and the
release continues that same animation into the cast (`Player._begin_spell_windup`).

| Spell | Formula |
|---|---|
| Fireball damage | `base damage x (0.6 + 1.2 x charge) x rank multiplier` |
| Fireball radius | `base radius x (0.8 + 0.7 x charge) x rank area multiplier` |