# Guild Plan

A staged plan for rewarding players who build into more than one colour. Every stage ships
something playable on its own; later stages extend the same machinery rather than replacing
it.

**The rule for every node here: it connects two (or three) colours' MECHANICS.** No plain
stats - those each have exactly one home in the tree (see *One number, one node* in
`docs/SKILL_DESIGN.md`). A guild node is worth having only if a player who owns both
colours plays differently because of it.

## Stage 0 - done: the gaps are free

The five keyword passives (Flying, Double Strike, Haste, Trample, Vigilance) used to sit on
the bisectors between the colour spokes. They were numbers that belonged to no colour and
are equipment now (`scripts/equipment_database.gd`, dropped by bosses, worn from the **I**
menu). The five spots between the colours are empty and waiting for Stage 1.

## Stage 1 - the five allied guilds ✅ all shipped

The pairs of colours that sit next to each other on the pentagon (and in the lane order
W-U-B-R-G) - Magic's allied guilds. One node each, on the bisector between the two spokes,
exactly where the old passives stood.

### Rules

| Rule | Proposal | Why |
|---|---|---|
| Reachable | Only when a node of BOTH neighbouring colours is owned (the old passives needed either one) | A guild is a two-colour reward; reachable from one side it was a free stat for everyone |
| Gate | 5 invested in each of the two colours (`Player.color_investment`) | Same ladder as everything else, so there is nothing new to learn |
| Ranks | 1, one skill point ✅ (proposed 1-3; shipped binary - a guild node is one passive, not a ladder) | Special enough to feel like a keystone, cheap enough that a two-colour build can afford it |
| Shape | Round, gold rim | Passive (round), and visibly neither colour |

### The five nodes

| Guild | Colours | Node | Effect |
|---|---|---|---|
| Azorius | W + U | **Azorius Justiciar** ✅ | Enemies you freeze, stun or knock back deal 30% less damage for 5s afterwards. Control that protects. |
| Dimir | U + B | **Dimir Guildmage** ✅ | Enemies that die frozen, stunned or cursed (Wall of Souls, Contagion) rise immediately as your own ghoul, exactly like one Zombify raised - control feeds the same graveyard black already works from. Not bosses - same rule Zombify's own cast follows. |
| Rakdos | B + R | **Mayhem Devil** ✅ | Zombify's raised ghouls explode for area damage when they reach an enemy or run out of time. Without this, a ghoul still runs in and still pops - it just does not hurt anything. |
| Gruul | R + G | **Rubblebelt Rioters** ✅ | After Titanic Brawl or Fire Dash, your next three melee hits deal +50% and knock back further. |
| Selesnya | G + W | **Trostani, Selesnya's Voice** ✅ | Every shield and heal you cast on yourself lands on your myrs within 10m as well. |

> **Checked against real two-colour cards, not just evocative words.** Detention Sphere,
> Mind Rot, Goblin Bombardment, Rampage and Conclave Tribunal/Naturalists are all real
> Magic cards or keywords, and every one of them is mono-coloured - wrong for a slot that
> is specifically "visibly neither one colour nor the other." Azorius Justiciar (hybrid
> W/U), Dimir Guildmage, Mayhem Devil (hybrid B/R), Rubblebelt Rioters and Trostani,
> Selesnya's Voice are the real two-colour cards for each pair. Dimir's EFFECT changed
> too, not just its name - raising the kill as a ghoul is black's own reanimation
> mechanic (Zombify, `TemporaryAlly`) rather than an unrelated mana payout, and it is what
> Dimir Guildmage's own ability (return a creature card from the graveyard) is actually
> about.

> **Rakdos shipped as Mayhem Devil, not Hellbent** - the burn-death-chain idea this
> row originally proposed. Nothing had coded Hellbent yet, and a player asked specifically
> for Zombify's ghoul burst to move off the base spell and behind its own passive, which
> needed exactly this slot (black+red, round, gated on both colours). Hellbent is free to
> become a different node if the gap is ever reused - the five-pair, one-node-each shape
> of Stage 1 does not have room for both under Rakdos.

### Implementation ✅ all five shipped

- `SkillTree`: a `KIND_GUILD` node per entry in `GUILD_NODES`, each drawn on the bisector
  between its two colours' axes (`GUILD_BRANCH`), reachable only once BOTH colours clear
  `GameSettings.guild_investment_requirement` (`_guild_reachable`). One branch index
  serves all five because no two pairs share a first colour - see the comment above
  `GUILD_NODES` in `scripts/skill_tree.gd`.
- `Player.guild_ranks: Dictionary` (id -> 0 or 1), carried in `build_snapshot` /
  `export_build` / `_build_fingerprint` like `aura_ranks`, so the server resolves a
  client's guild effects and a reconnect keeps them. `has_guild`, `get_guild_rank`,
  `grant_guild_rank`.
- Each effect is a hook in code that already existed, checked against `has_guild` at the
  one or two places it needed to fire:
  - **Azorius** - `EnemyBase.apply_control_weaken(source)`, called from every place that
    already applies a freeze, stun or knockback (`SpellEffects.cast_green_titanic_leap`'s
    slam, `cast_blue_unsummon`, `cast_blue_frostwave`, `Player._rhystic_shatter`, the Icy
    Manipulator melee proc and its `request_freeze` RPC, and `Player.
    _apply_basic_attack_knockback`). Reuses `damage_penalty`/`penalty_timer`, the same
    flat reduction Pacifism already uses, rather than a weaken multiplier of its own.
  - **Dimir** - `EnemyBase.die()` snapshots `freeze_timer`/`stun_timer`/`curse_timer`/
    `contagion_timer` before any of them reset, then `_raise_as_dimir_ghoul()` finds a
    team-mate who owns the node and raises the kill through `request_effect("undead")` -
    the same networked spawn `SpellEffects.cast_black_zombify` uses, not a local
    `add_child` (see the corpse-collision fix this doc's git history grew out of for why
    that distinction matters online). Bosses excluded, matching Zombify's own exclusion.
  - **Rakdos** - `TemporaryAlly._explode`, gated on `owner_player.has_guild("guild_rakdos")`.
    A ghoul Dimir raised explodes too, if its raiser also owns Rakdos - the two nodes
    compose for free.
  - **Gruul** - `Player._start_rampage()` (called from the two charge-in spells' launch
    half) arms `_rampage_hits_left`; `_apply_melee_damage` spends one per impact FRAME,
    not per enemy a cleave connects with - the same unit Exalted Strike's own charge
    spends, for the same reason.
  - **Selesnya** - `Player._share_self_heal_with_myrs(amount)`, called after the two
    direct `caster.heal(...)` self-heals (Rally the Fallen, Giant Growth). Circle of
    Protection and Rally's ALLY half need nothing extra: both already loop over
    `_allies_in_radius`, which already includes the `"myrs"` group.
- `tools/tests/skill_roster.gd` still wants a GUILDS section: one observable consequence
  per node. Not added yet - everything above was verified by reading the call graph, not
  by running the five effects in the editor.

## Stage 2 - the five enemy guilds

The pairs that sit OPPOSITE each other on the pentagon - Magic's enemy guilds. Blue + red
(Izzet) is one of them.

### Where they live

The main board has no room for them: an enemy pair's line runs through the middle of the
pentagon, across a third colour's spoke. So the skill tree gets a second page, the **Guild
Web**: the five colours as the points of a pentagram. Its outer edges are the allied guilds
(the Stage 1 nodes, mirrored here so both pages agree), its diagonals are the enemy guilds,
and each point shows how much the player has invested in that colour.

Same rules as Stage 1: both colours owned, 5 invested in each, ranks 1-3.

### The five nodes

| Guild | Colours | Node | Effect |
|---|---|---|---|
| Izzet | U + R | **Thermal Shock** | Fire damage on a frozen or chilled enemy shatters the ice: +50% damage and a small burst of frost and fire around it. Blue sets up, red cashes in. |
| Orzhov | W + B | **Extort** | Every enemy you kill heals the most-hurt ally within 12m for a share of its maximum health. Death paid to the living. |
| Golgari | B + G | **Grave Vines** | Enemies killed by Contagion or Stampede leave corpses that sprout vines: enemies stepping over them are rooted for 1s (`root_timer`, which nothing sets today). |
| Boros | R + W | **Battle Cry** | Every spell you cast gives teammates and myrs within 12m +10% attack and movement speed for 4s. A triggered team buff, not a standing stat. |
| Simic | G + U | **Adapt** | When Giant Growth ends you keep 20% of its size and health bonus until the end of the wave, stacking to three. Growth that evolves. |

## Stage 3 - three colours

The ten three-colour combinations: the five **shards** (a colour and both neighbours) and
the five **wedges** (a colour and both enemies). One capstone node per combination on the
Guild Web - a triangle drawn between its three points - gated on 10 invested in each of the
three colours, so realistically one per run.

| Name | Colours | Direction |
|---|---|---|
| Bant | G W U | Protected ground: Fog also shields the allies standing in it |
| Esper | W U B | Myrs become fighters: they carry a small copy of your Soul Orb |
| Grixis | U B R | Frozen enemies that die burst into Contagion |
| Jund | B R G | Ghouls you raise inherit your Giant Growth and burn what they touch |
| Naya | R G W | Titanic Brawl heals every ally inside its landing |
| Abzan | W B G | Wall of Souls also roots |
| Jeskai | U R W | Every third spell cast in quick succession casts itself again at half power |
| Sultai | B G U | Suction also drags corpses in, and Zombify raises from the pile |
| Mardu | R W B | Kill also triggers a Wrath of God at a fifth of its power around the target |
| Temur | G U R | Displace leaves a Fire Dash trail and a frost patch behind |

These are directions, not specs - each needs its own design pass once Stages 1-2 have shown
how much a guild node should be worth.

## Stage 4 - guild camps and two-colour equipment

The map half, from *Guild camps* in `docs/SKILL_DESIGN.md`: a camp in each lane's back
corner, active between waves. What ties it to this plan is the equipment system that
already exists - camps drop **two-colour equipment**, and Magic has the perfect set for it:
the Swords of X and Y.

| Camp | Drops | Idea |
|---|---|---|
| Azorius | Sword of Truth and Justice | Melee hits add a stack to Rhystic Study's shield |
| Dimir | Sword of Once and Future | Kills with melee refresh a random spell's cooldown by a second |
| Rakdos | Sword of Sinew and Steel | Melee hits shred armour: the target takes more from burns |
| Gruul | Sword of War and Peace | Melee damage grows with the number of enemies around you |
| Selesnya | Sword of Hearth and Home | Melee hits heal the nearest myr |

The camps stay inert during waves (the player is already the jungler), and the equipment
goes into the same team stash and the same **I** menu as the boss drops.

## Order and size

| Stage | Size | Depends on |
|---|---|---|
| 1 - allied guilds | Small: 5 hooks, one node kind, tests | Nothing - the gaps are free |
| 2 - enemy guilds | Medium: the Guild Web page, 5 hooks | Stage 1's node kind and build sync |
| 3 - three colours | Large: 10 designs | Stage 2's page; a balancing pass on 1-2 first |
| 4 - camps + swords | Large: map camps, wave pacing, 5 items | The equipment system (done); camp spawning |

Open questions before Stage 1: the ranks (1-3 or a single purchase), and whether the Guild
Web should be a second page or the allied guilds should stay on the main board only.
