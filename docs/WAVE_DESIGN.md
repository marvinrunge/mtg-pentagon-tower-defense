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
archer ring, archers actually *ringing* rather than queuing, melee ahead of both), the
battle-group partition (contiguous runs of neighbours, every colour used exactly once, group
size within the wave's cap) and the wave plans (squads in their own lane, the authored
opening intact, bosses leading alone, plans reproducible). It needs no map and finishes
instantly.

`tools/tests/wave_squads.tscn` boots the real map and watches a wave walk down a lane: the
whole group landing in one step, members still in their slots half a minute later, casters
still behind the melee screen, and an allied pair reaching its hold line and charging. It is
measured in **game seconds**, not frames - headless renders as fast as the CPU allows while
physics still steps at its fixed rate, so a frame counter samples a couple of seconds into a
march that takes a minute. `Engine.time_scale` buys that back: about forty seconds on the
wall.

```
godot --headless --path . res://tools/tests/wave_formations.tscn
godot --headless --path . res://tools/tests/wave_squads.tscn
```
