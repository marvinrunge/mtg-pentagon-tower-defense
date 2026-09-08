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
| Maximum charge time | 5 seconds (`GameSettings.spell_charge_max_time`) |
| Minimum released charge | 20% |
| Multicolor access | Any color can be ranked and unlocked |
| Active hotbar branch | Selected by clicking an unlocked spell or binding it from the skill tree |

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
| 1 | Fireball | 1 | 5s | Yes | Charged | Blast radius | Charged explosive projectile with a scaling blast radius. |
| 2 | Fire Dash | 1 | 8s | No | Trail damage | Dash | Dashes forward and leaves a burning trail. |
| 3 | Rain of Ember | 1 | 9s | No | Zone DPS | Ground zone | Creates a burning zone that damages enemies inside it. |
| 4 | Fire Cone | 1 | 10s | No | Channel DPS | Frontal cone | Held channel that burns enemies in front of the player. |
| 5 | Lightning Bolt | 1 | 12s | No | Target damage | Aimed area | Calls lightning down on a precisely aimed target area. |

## Blue - Control

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Unsummon | 1 | 3s | No | 35 | Cone | Applies 21 knockback plus 7.5 of upward lift, so enemies are thrown off the ground and land stunned. Hitting a wall or obstacle during knockback deals 80 additional impact damage. |
| 2 | Frostwave | 1 | 12s | No | Damage / slow | Area | Freezes nearby enemies and damages them; bosses are slowed instead. |
| 3 | Frost Globe | 1 | 16s | No | Projectile block | Placed sphere | Places an ice sphere that blocks enemy projectiles. |
| 4 | Suction | 1 | 11s | No | Pull | Area | Pulls nearby enemies into one location. |
| 5 | Phantasmal Decoy | 1 | 24s | No | Taunt | Placed decoy | Creates an illusion enemies attack instead of the player. |

## Green - Strength

| Tier | Spell | Cost | Cooldown | Charge | Damage | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Titanic Leap | 1 | 8s | No | Landing damage | Leap | Leaps forward and slams the ground on landing. |
| 2 | Giant Growth | 1 | 22s | No | Maximum HP | Self | Grows the player temporarily and increases maximum health. |
| 3 | Fog | 1 | 18s | No | Damage suppression | Ground zone | Creates fog where enemies deal no damage. |
| 4 | Roar | 1 | 16s | No | Taunt | Area | Forces nearby enemies to target the player. |
| 5 | Ironbark | 1 | 20s | No | Damage reduction | Self | Reduces damage and prevents knockback, stun, and freeze. |

## White - Protection

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Exalted Strike | 1 | 8s | No | Melee buff | Self | Strengthens and extends the next melee hit; kills are exiled. |
| 2 | Circle of Protection | 1 | 18s | No | Shield pool | Ally area | Divides a shield pool among nearby allies. |
| 3 | Reprisal Ward | 1 | 16s | No | Reflect / block | Self | Reflects damage and grants a chance to block attacks. |
| 4 | Wrath of God | 1 | 20s | No | Area damage | Area | Deals heavy damage to nearby enemies. |
| 5 | Rally the Fallen | 1 | 45s | No | Revive / heal | Ally area | Revives downed teammates and heals surviving allies and myrs. |

## Black - Sacrifice

| Tier | Spell | Cost | Cooldown | Charge | Damage / Healing | Range / Radius | Details |
|---:|---|---:|---:|:---:|---:|---:|---|
| 1 | Doom Blade | 1 | 7s | No | Line damage | 5m line | Sends a black blade along the camera aim line through enemies. |
| 2 | Fear | 1 | 14s | No | Flee | Area | Nearby enemies flee instead of fighting. |
| 3 | Kill | 1 | 60s | No | Execute | Single target | Instantly kills an enemy; bosses must be below one third health. |
| 4 | Wall of Souls | 1 | 20s | No | Damage amplifier | Wall | Enemies crossing the wall take increased damage. |
| 5 | Zombify | 1 | 30s | No | Summon | Corpse area | Raises corpses as temporary undead allies. |

## Charge Formulas

Currently, only Fireball is chargeable. Its charge multiplier ranges from `0.2` to
`1.0` when the cast is released - a full-power Fireball therefore takes the whole
5-second window, and the charge fires by itself once it closes.

The caster is not idle while it builds: the cast clip's lead-in is stretched across the
charge window, so the wind-up is visibly held for as long as the button is down, and the
release continues that same animation into the cast (`Player._begin_spell_windup`).

| Spell | Formula |
|---|---|
| Fireball damage | `base damage x (0.6 + 1.2 x charge) x rank multiplier` |
| Fireball radius | `base radius x (0.8 + 0.7 x charge) x rank area multiplier` |