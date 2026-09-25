# Wave Design

How a wave is assembled, how it arrives, and where to change it.

## What a wave used to be

Five spawn queues. `WaveManager` flattened the wave into a list of individual enemies,
each with its own delay, and fed them out one at a time - colour after colour, with a pause
between colours. Three things followed from that, and all three were the problem:

- **A colour trickled.** Its melee walked in, then a few seconds later its archers, then its
  mages. The screen was dead before the thing it was screening existed, so the classes never
  interacted with each other and a mage was just a slow enemy standing in the open.
- **The player fought one colour at a time.** The delay between colours was longer than it
  took to kill what had already arrived, so a five-colour wave played as five small fights.
- **Nothing had an identity.** Every colour arrived in the same shape - a line of clusters -
  and differed only in its stat block.

## What a wave is now

A wave is an ordered list of **battle groups**. A battle group is one or more **adjacent**
colours; each colour in it fields one **squad**, and every squad in the group spawns at the
same instant, already standing in formation.

```
wave  ->  battle group  ->  squad   ->  melee screen / archer shell / mage core
                     (allied colours)   (one colour, one lane, one EnemySquad)
```

Adjacent means adjacent on the map, which on this map is the same thing as adjacent on the
MTG colour wheel: the five lanes are a pentagon in `WUBRG` order, so lane index +/-1 is both
the lane next door and the **allied** colour. White pairs with Blue and Green, never with
Black.

### The formation

Every squad is built out of the same three parts, and only their proportions change per
colour (`SquadDoctrine.DOCTRINES`):

```
        #  #  #  #  #  #        melee screen, closest to the crystal
             o     o
          o    M M    o         archers ring the mages
             o  o  o
```

Mages are what a squad is for - a White mage heals the rank in front of it, a Green one
pumps whatever it can reach - so they stand in the middle, archers ring them, and the melee
stand in front of both. Reaching a mage means going through everything the colour brought.

Per-colour differences are deliberately expressed as **geometry and speed**, never as extra
states in the squad brain. A doctrine that needs its own branch can deadlock; one that only
moves numbers around cannot.

| Colour | Shape | Reads as |
| --- | --- | --- |
| White | tight ranks, holds to 16 units from the crystal | a phalanx that is still a phalanx when it arrives |
| Blue | wide line, casters set back 9 extra units | a skirmish line; the casters are a long walk behind the screen |
| Black | narrow, very deep, ragged, slow | a column that keeps arriving |
| Red | no ranks at all, breaks at 90 units and on any damage | a mob that briefly left the lane together |
| Green | an arrowhead with the casters in the pocket | a stampede that punches a hole |

#### Nothing stands behind the anchor

A formation is laid out around its squad's **anchor**, which at spawn time is the lane's
`EnemySpawner` marker - and that marker sits at the very back of the map. There are about
four units of baked navmesh behind it and a hundred and forty in front, so squad-local
`z = 0` is a wall, not a centre line.

The primitives do not respect that on their own, and cannot: a mage core stacks its rows
*backward*, the archer shell is a ring *around* that core, and Red's mob biases its casters
backward - which is the right shape, casters belong behind the screen, it just cannot be
measured from a point with no map behind it. So `SquadDoctrine._anchor_at_rear` slides the
whole finished formation forward until its rearmost slot sits on the anchor. Every slot
moves by the same amount, so ranks, rings and gaps are untouched; the only cost is that a
big squad starts its march a few units further down its own lane.

This has bitten twice, the same way both times. An off-map slot is not an off-map *enemy* -
`WaveManager._spawn_unit` snaps the spawn position onto the mesh - but members path to their
**slot**, so whoever holds it walks backwards off the lane at a place that does not exist,
can never be reached or killed, and the wave can never finish.

- **Wave 3.** Blue's `caster_setback` pulled its casters back past the spawner. Fixed by
  applying the setback forwards, pushing the melee screen out instead.
- **Wave 13.** Head count, not one doctrine: the reach grows with the size of the squad.
  Wave 3 fields one mage and one archer, where a one-point core and a single archer in
  front of it reach nowhere backward at all - which is why the first fix looked complete.
  By wave 13 a colour fields twenty-odd units, and White, Blue and Red hung seven to nine
  units off the back of their lanes. Fixed by the guarantee above.

The moral is in where the guarantee lives: over the *finished* formation, not as a rule each
primitive has to remember, because the first fix was a rule and the next primitive to grow
broke it anyway.

### Marching

`EnemySquad` owns an invisible **anchor** that walks down the lane. Members navigate to
their own slot measured off that anchor rather than to the crystal, and move at exactly the
speed needed to stay on it - which in steady state is the squad's march speed, set by its
**slowest** member. Without that cap the melee outrun the mages within ten seconds and the
formation the wave spawned in never exists again.

A member stops following the anchor the moment the anchor stops being the right answer: it
saw a player, it was taunted or feared, it was shoved further from its slot than the leash
allows, its colour breaks on damage, or the squad reached the crystal and dissolved.
Breaking ranks is **one-way** - re-forming mid-fight would mean walking back out of a fight
it is already in. Formation is a way of *arriving*, not a way of fighting.

### Alliances

A battle group of two or three colours does not walk straight in. Each squad marches to a
**hold line** at `wave_rally_radius` from the crystal - just inside the mana wells - stands
formed until the rest of the warband arrives, and then the whole group **charges** together
with a speed bonus that outlasts the formation dissolving. The banner says so twice: once
when the alliance masses, once when it charges.

The hold point is per squad, not one shared spot. Two neighbouring lanes are 72 degrees
apart, so meeting exactly in the middle costs each squad a sideways detour about as long as
the lane itself, spent crossing ground with nothing on it. Instead each squad converges
`wave_rally_convergence` of the way towards its group's centre: at 0.75 two neighbours end up
roughly thirty units apart, which reads as one army massing, and the lanes close the rest of
the gap during the charge.

Groups of four or five get no rendezvous. The average direction of most of a pentagon points
nowhere useful, and a rally that drags two squads across a third's lane is a worse fight than
four lanes arriving at once - which is what a wave that big should feel like anyway.

A lone squad has nobody to meet, so it charges on its own at `wave_squad_charge_lead` short
of the distance where it dissolves. No formation in the game walks into contact at marching
pace.

### Escalation

How many colours may share a battle group *is* the difficulty curve now. The same enemies
arriving in two pushes are a completely different fight from the same enemies arriving in
five separate ones.

| From wave | Largest group | Feels like |
| --- | --- | --- |
| 1 | 1 colour | one lane at a time; learning the map |
| `wave_alliance_start_wave` (4) | 2 allied colours | neighbours converge and charge together |
| `wave_shard_start_wave` (9) | 3 adjacent colours | a shard of the wheel at once |
| `wave_grand_alliance_start_wave` (16) | all 5 | the whole wheel |

The wave gets **harder** for that reason, deliberately. The enemies are the same and there
are the same number of them; they used to arrive spread over more than a minute of
deployment and be fought a colour at a time, and now a late wave is two or three groups that
are all on the map inside twenty seconds. If that turns out to be too much, the knob is
`wave_delay_between_groups`, not the head count.

Head counts did not move. `_compose_wave` uses the same base difficulty, the same growth per
wave, the same player-count factor and the same cost per draw the queue-based planner used;
all that changed is that a colour's draws are merged into one composition instead of becoming
several separate spawn entries. Waves 1 and 2 are the exact head counts they always were.
Wave 3 was re-authored - it used to be four lone mages plus ten Black melee, which was both
*smaller* than wave 2 and impossible to read as a formation.

## Minibosses

A rung above Elite, and deliberately its own separate system rather than a bigger Elite tier
(see `GameSettings`' Minibosses block): Elite only ever changes numbers, and a miniboss is
meant to be *seen* before it's felt - visibly larger, glowing in its colour, and the one
member of its squad the melee screen is actually built around.

**At most one per wave** (`wave_miniboss_chance`, from `wave_miniboss_start_wave`), so it
reads as a notable arrival rather than a stat roll. `WaveManager._roll_miniboss` picks a
colour and class during composition - before the wave is partitioned into squads - and bumps
that colour's own Melee count by `wave_miniboss_escort_bonus`. Nothing new was needed in
`SquadDoctrine` for the escort itself: a denser melee screen in front of the mage core (or
in front of the miniboss itself, if it's the melee) falls out of the formation everyone
already stands in.

The unit gets flagged later, once squads exist (`WaveManager._assign_miniboss`) - specifically
the **first** unit of the chosen class in its squad's list, which `_deploy_squad` also hands
the first formation slot for that class. That's what puts the miniboss front-and-centre in its
own rank without any geometry change: `_units_of` already orders a squad class-by-class, so
"first of its class" and "the formation's most prominent slot for that class" are the same
unit. It is deliberately excluded from `_assign_elites`'s candidate pool - the two are
*independent* systems, and a miniboss that also rolled Juggernaut by coincidence would quietly
become a second boss in the same wave.

`EnemyBase.apply_miniboss()` does the rest: health, damage and model scale multiplied, speed
traded down a little (the same bargain Elite's own Juggernaut makes), and a rim-light glow in
the enemy's lane colour layered onto its mesh as a `next_pass` on a *duplicated* surface
material - never `material_override`, which would replace the base skin's real texture with a
flat colour, and never the shared material in place, which would glow every ordinary enemy
wearing that model.

**Only a Mage miniboss gets a special.** A Melee or Ranged one is a stat-scaled version of the
attack it already throws - same swing, same bow, nothing new to build. A Mage's special
(`EnemyBase._perform_miniboss_special` and friends) runs on its own long cooldown *alongside*
its ordinary casting in `perform_mage_spell`, telegraphed with the same `AttackIndicator`
bosses use, and reuses the exact effect its colour's ordinary cast already throws - just
bigger, and for Red/Blue, reaching every player in range rather than only the first one found.
It is not driven off an animation clip length the way a boss's is: the ordinary Melee/Ranged/
Mage rigs were never built with a dedicated cast clip to time against, so the windup is a
fixed, tunable duration (`wave_miniboss_special_windup`) instead.

## Where to change things

| I want to change | Look in |
| --- | --- |
| a colour's shape, discipline, or when it breaks | `SquadDoctrine.DOCTRINES` |
| the formation primitives (ranks, rings, wedge, mob) | `SquadDoctrine._ranks` and friends |
| marching, rallying, charging, disbanding | `scripts/enemy_squad.gd` |
| what a wave is made of, and who allies with whom | `WaveManager._plan_wave` / `_compose_wave` |
| the authored opening (waves 1-3) | `WaveManager.OPENING_WAVES` |
| pacing, rally distance, escalation thresholds | `GameSettings`, the `WAVES` block |
| what a member does once it has broken ranks | `EnemyBase`, ordinary AI - nothing squad-specific |
| miniboss stats, cadence, or the escort bonus | `GameSettings`' Minibosses block |
| which colour/class gets picked as the miniboss | `WaveManager._roll_miniboss` / `_assign_miniboss` |
| the glow, or a Mage miniboss's special | `EnemyBase.apply_miniboss` / `_perform_miniboss_special` |

## Multiplayer

Squads are **server-only**, for the same reason enemy AI already is: a second brain on a
client would only burn frames disagreeing with the server's. Clients see the result in the
replicated transforms.

Two things that used to be planned locally on every peer now travel instead, because a
client planning its own wave from its own random numbers agreed with the server about
nothing:

- **Warning banners** are raised by the server, when the thing they describe actually
  happens, and relayed (`_net_announce`). A client used to be warned about lanes that were
  never coming.
- **The wave number** arrives with the wave (`_net_wave_started`). Nothing ever advanced it
  on a client, and `EnemyBase` scales maximum health off it on every peer - so a client was
  drawing wave-1 health bars over wave-20 enemies for the whole run.

The enemy count on the HUD travels too (`_net_wave_state`): deaths resolve on the server, so
a client's own count could only ever drift upwards.

## Tests

`tools/tests/wave_formations.tscn` is the offline half: formation geometry (mages inside the
archer ring, archers actually *ringing* rather than queuing, melee ahead of both), formation
reach (no slot behind the anchor, at the real composition of every wave out to 40 - see
*Nothing stands behind the anchor*), the battle-group partition (contiguous runs of neighbours, every colour used exactly once, group
size within the wave's cap) and the wave plans (squads in their own lane, the authored
opening intact, bosses leading alone, plans reproducible). It needs no map and finishes
instantly.

`tools/tests/wave_squads.tscn` boots the real map and watches a wave walk down a lane: the
whole group landing in one step, members still in their slots half a minute later, casters
still behind the melee screen, and an allied pair reaching its hold line and charging. It
also re-checks formation reach against the **real baked navmesh** rather than against
squad-local z, sampled across the wave curve, which is the check that reproduces the wave-13
report exactly: green at 3, 7, then failing from 13 on. It is
measured in **game seconds**, not frames - headless renders as fast as the CPU allows while
physics still steps at its fixed rate, so a frame counter samples a couple of seconds into a
march that takes a minute. `Engine.time_scale` buys that back: about forty seconds on the
wall.

`tools/tests/minibosses.tscn` covers both halves for the miniboss layer specifically: the
planning claims (never before the start wave, at most one per wave, never also an Elite, the
escort bonus lands on the right colour, the flagged unit is the front-of-its-class slot) and
the live ones (a spawned miniboss is bigger and tankier by exactly the configured multipliers,
carries the glow, and - for a Mage - actually fires its special and its effect lands). The
special's own timers are advanced by calling the spawned enemy's `_physics_process` directly
rather than through the engine's own tick or `Engine.time_scale`: unlike the march test, this
one only needs a single enemy's internal state to advance, not the whole scene's physics.

```
godot --headless --path . res://tools/tests/wave_formations.tscn
godot --headless --path . res://tools/tests/wave_squads.tscn
godot --headless --path . res://tools/tests/minibosses.tscn
```
