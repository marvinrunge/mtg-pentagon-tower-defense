# Skill Design

The full skill roster, organised per colour. **Design only** — three of these thirty
exist in code today (marked ✅). Nothing here is implemented by writing it down.

## The shape

Each colour gets **five active spells plus one aura**, six entries, thirty total.
That is not an arbitrary split — it is what the codebase is already built for:

- `SpellDatabase.SPELLS_PER_COLOR` is already 5, and the skill tree already draws
  five spell nodes per branch outward from an affinity node.
- The aura maps onto the existing `Player.unlocked_capstone_aura` — one per colour,
  passive, always on.

### Ranks (the "max 5 stacks")

> **Ranks are bought with SKILL POINTS, not mana.** See `docs/ECONOMY.md`: XP is shared
> across the team, everyone levels together, and each level grants every player one
> point. Mana is a separate, shared resource spent only on team purchases at Upkeep.
> Nothing in this tree costs mana.

Every skill can be bought **five times**. A rank is a purchase in the skill tree, not
a stacking buff applied in combat. Rank 1 is the skill working; ranks 2–5 scale the
two or three numbers listed in its **Scales** column.

This is a change from how the tree works today, where a colour's five *tiers* are five
*different* spells. Under this model the tree holds six things per colour and each is
bought up to five times, so the same board expresses "wide and shallow" or "one skill
mastered" instead of a fixed unlock order.

Suggested curve: rank 1 is the baseline below, rank 5 is roughly **2× damage**,
**1.6× area/range**, **1.5× duration**. Cost rises per rank so a rank-5 skill is a
real commitment against spreading out.

### Legend

| Mark | Meaning |
|---|---|
| ✅ | Implemented and playable |
| 🆕 | Invented to fill the colour out — not from the original list |
| ✏️ | From the list, but I named it (it had none) |

---

## Blue — control

Blue never kills quickly. It decides *where* the fight happens and *who* is allowed to
participate. Every blue skill either moves enemies, stops them acting, or takes a
threat off the board.

| Skill | Kind | Effect | Scales with rank | Uses |
|---|---|---|---|---|
| **Frost Globe** | Placed | Spawns an ice sphere that **blocks enemy projectiles**. Ranged and mage enemies lose line of fire through it; melee walk around it. | Radius, duration | New static body on the projectile collision layer |
| **Unsummon** | Burst | Shoves every enemy in front far back and **stuns** them on landing. | Push distance, stun duration | `apply_knockback()`, `stun_timer` |
| **Suction** | Burst | **Pulls** nearby enemies into the centre, packing them for an area follow-up. | Radius (pull strength stays fixed — see note) | Inverse `apply_knockback()` |
| **Frostwave** | 360° burst | Freezes every enemy around the caster and deals moderate damage. **Bosses are slowed, never frozen.** | Radius, damage, freeze duration | `freeze_timer`, `frost_slow_timer` |
| **Phantasmal Decoy** 🆕 | Summon | Drops an illusion enemies retarget onto until it is destroyed or expires. | Decoy HP, duration | Enemy `evaluate_target()` — needs a targetable group |
| **Aura: Orb of Frost** | Aura | An orb orbits the caster, firing ice at nearby enemies for damage and **slow**. | Fire rate, damage, slow strength | `ProjectilePool`, `frost_slow_timer` |

> **Suction note.** Pull *strength* should not scale — a rank-5 pull that yanks
> everything instantly removes the counterplay of walking out of it. Scale the radius
> so it catches more, not so it catches harder.

---

## Red — aggression

Red is the damage colour and the only one with no defensive option at all. Two of the
three implemented spells are red.

| Skill | Kind | Effect | Scales with rank | Uses |
|---|---|---|---|---|
| **Fireball** ✅ | Projectile | Chargeable explosive bolt; charge raises blast radius and damage. | Damage, blast radius | `red_1`, `EmberFx.build_burst` |
| **Rain of Ember** ✅ | Placed zone | Ground-targeted firestorm burning everything beneath it. | Damage/sec, radius, duration | `red_2`, `DoTZone` |
| **Fire Cone** | Channelled | **Held**, not cast. Burns everything in a cone ahead for as long as it runs. **No movement while channelling.** | Damage/sec, cone length | New channel state; reuse the leap's movement suspension |
| **Lightning Bolt** | Targeted | Very high damage in a **small** area, called down from above. The precision option against a single big target. | Damage, radius (slightly) | `AttackIndicator` for the telegraph |
| **Fire Dash** | Movement | Dashes forward, leaving a **burning trail** behind. Escape and damage in one. | Distance, trail damage, trail duration | `DoTZone` spawned along the path |
| **Aura: Orb of Fire** | Aura | An orb orbits the caster, firing fireballs at nearby enemies for damage and **burn**. | Fire rate, damage, burn duration | `ProjectilePool`, `DoTZone` |

> **Fire Cone is the interesting one.** It is the only skill in the game whose value
> depends on the player choosing to stand still in a tower defence. Its damage should
> be the highest per second in the game to pay for that.

---

## Green — primal vitality

Green fights by being physically present: bigger, harder to ignore, and dangerous to
stand next to.

| Skill | Kind | Effect | Scales with rank | Uses |
|---|---|---|---|---|
| **Leap Slam** ✅ | Movement + burst | Leaps forward and slams down for heavy area damage and knockback. | **Damage, radius** | `green_1`, `EmberFx`, `heavy_landing` |
| **Fog** | Placed zone | An area where **enemies deal no damage**. Defensive ground rather than offensive. | Radius, duration | `damage_penalty` or a zone flag |
| **Roar** | Taunt | Nearby enemies **retarget onto you**, pulling them off the crystal and the myrs. | Radius, taunt duration | Enemy `evaluate_target()` override |
| **Giant Growth** | Self-buff | The player grows physically larger and gains maximum HP for a duration. | Size, bonus HP, duration | `is_giant` / `giant_timer` (already stubbed in `Player`) |
| **Ironbark** 🆕 | Self-buff | A short window of heavy damage reduction **and immunity to knockback, stun and freeze**. | Damage reduction, duration | `_stagger_timer`, knockback rejection |
| **Aura: Trample** | Aura | Enemies near the player take small continuous damage **while the player is moving**. | Damage/sec, radius | Per-frame proximity sweep gated on velocity |

> **Roar and Fog are the crystal-defence pair** — the only two skills in the game that
> protect the objective rather than kill things. Worth keeping both cheap at rank 1.

> **Ironbark replaced an earlier "Primal Rampage"** (attack and movement speed surge),
> which was a third self-buff in a colour that already has Giant Growth, and duplicated
> what the Fervor aura does passively. Ironbark is the only CC immunity in all thirty
> skills — without it, being stunned or frozen has no counter at all.

---

## Black — parasitic drain

Black trades its own resources for removal, and is the only colour that can delete a
target outright.

| Skill | Kind | Effect | Scales with rank | Uses |
|---|---|---|---|---|
| **Doom Blade** | Line | A black blade travels straight ahead, passing **through** enemies. High damage, but only what the blade actually touches is hit. | Damage, blade length, width (barely) | Thin `Area3D` sweep along a ray |
| **Fear** | Burst | Nearby enemies **flee** for a duration instead of fighting — the colour's answer to being surrounded. | Radius, flee duration | `pacified_timer` + an inverted nav target |
| **Kill** | Targeted | **Instantly kills** one non-boss enemy. Bosses are executed only **below 33% health**. | Cooldown, boss execute threshold | Direct `die()`; boss HP check |
| **Wall of Souls** | Placed | Enemies that pass through take **double damage from every source** while marked. | Wall length, mark duration, damage multiplier | `curse_timer` / `curse_mult` — already exists |
| **Zombify** 🆕 | Summon | Raises the corpses already lying on the field as temporary undead allies that fight for you. | Corpses raised, undead HP, duration | `EnemyBase._register_corpse` corpse registry |
| **Aura: Grave Pact** 🆕 | Aura | Every enemy that dies near the player leaves a soul wisp: a small heal, plus a **stacking damage bonus that decays** if you stop killing. | Heal per soul, bonus per stack, decay time | `SignalBus.enemy_died`, `heal()` |

> **Zombify replaced an earlier "Vampiric Drain"** (a held HP-draining beam), which
> overlapped the Grave Pact aura's healing-on-kill and gave black a second channelled
> skill next to nothing else. Zombify turns a system that already exists and does
> nothing — corpses are kept in the scene up to a cap and are pure decoration — into a
> resource, and gives black the only summon outside green.

> **Kill needs the harshest cooldown in the game.** An instant-delete with a short
> cooldown invalidates every other black skill, and the boss clause is what stops it
> trivialising the wave-boss fights entirely.

---

## White — protection and restoration

White is the only colour built around the myrs and the crystal rather than the player,
and the only one whose power goes **up** with more allies alive.

| Skill | Kind | Effect | Scales with rank | Uses |
|---|---|---|---|---|
| **Circle of Protection** | Support | A pool of shield is **divided between nearby allies**. With nobody in range the caster takes all of it. | Total shield, radius | Existing shield fields (`glorious_anthem_shield` pattern) |
| **Reprisal Ward** ✏️ | Self-buff | Reflects a **percentage of damage taken** back at the attacker, and grants a **passive chance to block** outright. | Reflect %, block chance | The old briar-patch reflect path |
| **Exalted Strike** | Buff | The **next attack** gets bonus damage and extra reach. Anything killed by it leaves **no corpse** and is exiled. | Bonus damage, reach, charges | `Player._apply_melee_damage`, corpse registry |
| **Wrath of God** 🆕 | 360° burst | Heavy damage to every enemy in a large radius around the caster. White's one panic button. | Damage, radius | Straight proximity sweep |
| **Rally the Fallen** 🆕 | Support | Instantly **revives every downed teammate** in range and heals surviving allies — myrs included — back to full. | Radius, heal amount, revive count | `Player.revive()`, `is_downed`, `heal()`, myr group |
| **Aura: Healing Orb** | Aura | An orb heals the caster and allies every 2s, always picking the **lowest-health** target in range. | Heal amount, radius, tick rate | `heal()`, myr/player group scan |

> **Exalted Strike's exile clause matters mechanically**, not just for flavour: corpses
> are kept in the scene up to a cap (`EnemyBase._register_corpse`), so exiling is a
> real performance benefit as well as a black-magic-proofing.

> **Rally the Fallen replaced an earlier "Pacifism"** (one enemy stops attacking),
> which was too close to black's Fear — both were "this enemy is not a threat for a
> while", differing only in whether it walked away. Rally is the only skill in all
> thirty that *undoes* a loss rather than preventing one, which is about as white as a
> mechanic gets, and it is the only one that touches the co-op revive system.

---

## Passives already in the game

Two passive layers exist in code today and are **not** part of the six-skills-per-colour
roster above. Any rework has to say what happens to them, because the tree is currently
built around both.

### Affinity ranks — the stat line ✅

Each colour's centre node is bought repeatedly (`GameSettings.affinity_rank_mana_cost`,
1 mana per rank) and grants a stacking percentage. This is the only progression in the
game that is currently uncapped.

| Colour | Name | Grants | Applied in |
|---|---|---|---|
| White | Holy Strength | +% health regeneration | `Player._physics_process` regen tick |
| Blue | Curiosity | +% cooldown recovery | `spell_cooldown_timers` decay |
| Black | Vampiric Link | +% lifesteal | `Player` melee/spell damage |
| Red | Reckless Charge | +% total damage | `get_spell_damage_multiplier()` |
| Green | Wild Growth | +% maximum HP | `_sync_capstone_aura()` |

Ranks have **diminishing returns**: +2% per rank for the first 10, +1% for ranks 11–20,
+0.5% beyond (`affinity_rank_bonus_early` / `_mid` / `_late`). They also **gate the
spells**: `affinity_spell_rank_requirements` is `[1, 5, 10, 15, 25]`, so a colour's fifth
spell needs 25 ranks in it.

> **This is the open question from the rank model.** If every skill becomes rankable
> 1–5, affinity ranks are a second, parallel progression that also gates them. Either
> affinity stays as the pure stat line and skill ranks are gated by it, or the gate goes
> and affinity becomes just another purchase competing with skills.

### Capstone auras — one per colour ✅

`Player.unlocked_capstone_aura` holds exactly one, chosen by colour path. These are the
auras that **exist**; the "Aura:" rows in the roster above are the *planned* replacements.

| Colour | Current aura | What it does |
|---|---|---|
| White | **Glorious Anthem** | 35 permanent shield, ×1.15 damage |
| Blue | **Rhystic Study** | ×0.7 cooldowns, and every cast grants 15 shield up to 45 |
| Black | **Phyrexian Arena** | ×1.25 damage and ×1.15 speed, paid for by draining 1.5% max HP per second |
| Red | **Fervor** | ×1.15 attack and movement speed |
| Green | **Sylvan Library** | ×1.35 maximum HP, +3 HP/sec regeneration |

> **The planned auras are a different design.** The current five are flat stat
> multipliers; the roster's are active effects (orbiting orbs, trample damage, souls on
> kill). Worth deciding whether they **replace** these or sit alongside them as a sixth
> purchase — Phyrexian Arena's HP-drain-for-power in particular is a real design that
> nothing in the new roster reproduces.

### Colourless — Blade Dance ✅

The hub at the centre of the pentagon, bought once for
`GameSettings.melee_combo_unlock_cost` mana of any colour. Extends the light attack
chain from two stages to three, the third landing at ×1.5 damage. Belongs to no colour
and is the only purchase that changes basic melee.

### Wave rewards — temporary run modifiers ✅

Not bought in the tree at all; offered between waves and multiplied into the run.

| Reward | Effect |
|---|---|
| Power Surge | `run_damage_multiplier` × reward value |
| Arcane Tempo | `run_cooldown_recovery_multiplier` × reward value |
| Crystal Repair | Restores crystal integrity |

## Mechanics already in the engine

Most of this roster can be built on status fields `EnemyBase` already carries, which is
worth knowing before inventing new ones:

| Field | Meaning | Used by |
|---|---|---|
| `freeze_timer` | Cannot act or move | Frostwave |
| `frost_slow_timer` / `chill_stacks` | Slowed movement and attack rate | Orb of Frost, Frostwave (bosses) |
| `root_timer` | Cannot move, can still attack | — (available) |
| `stun_timer` | Cannot act | Unsummon |
| `blind_timer` | Cannot attack | — (available) |
| `pacified_timer` | Will not attack | Fear (as one way to build it) |
| `curse_timer` / `curse_mult` | Takes multiplied damage | Wall of Souls |
| `damage_penalty` | Deals reduced damage | Fog |
| `apply_knockback()` | Impulse away from a point | Unsummon, Suction (inverted), Leap Slam |

Also already present: `DoTZone` (ground zones), `ProjectilePool`, `AttackIndicator`
(telegraphs), `EmberFx` (fire visuals — see `docs/VFX_TEXTURES.md`), `SoundBank`.

## Balance sketch

Roughly where each colour should sit, so ranks can be tuned against something:

| Colour | Single target | Area | Control | Defence | Support |
|---|---|---|---|---|---|
| Blue | low | medium | **highest** | medium | low |
| Red | high | **highest** | low | none | none |
| Green | medium | medium | medium | **high** | medium |
| Black | **highest** | low | medium | low (self-heal) | none |
| White | low | medium | medium | **highest** | **highest** |

## Resolutions

Recommended answers to the two structural questions, chosen for what makes a purchase
feel good to make rather than for what is easiest to build.

### 1. Affinity — every rank you buy IS an affinity rank

**The problem is not that there are two progressions. It is that one of them is a toll
booth.** Nobody buys rank 17 of Reckless Charge because they want +1% damage; they buy
it because the fifth red spell is sitting behind rank 25. Twenty-five mandatory,
identical, incremental purchases to reach a thing you already decided you wanted is the
least satisfying shape a progression system can have — it is not a choice, it is a wait.

**Fix: delete affinity as a separate purchase.** Skill ranks become the only thing you
buy, and **every skill rank bought in a colour grants one affinity rank in that
colour**. Affinity stops being something you shop for and becomes the *measure of your
commitment* to a colour — automatically, as a consequence of playing the way you wanted
to play.

The gates then read off that same number:

| Colour ranks spent | Unlocks |
|---|---|
| 0 | Skill slot 1 |
| 2 | Skill slot 2 |
| 5 | Skill slot 3 |
| 9 | Skill slot 4 |
| 14 | Skill slot 5 |
| 15 | The colour's capstone |

Keep the existing diminishing returns (+2% per rank for the first 10, +1% to 20, +0.5%
beyond), because they are what stops five-colour spreading from being strictly better.

**Why players like this better:**

- **Every mana does two things.** A rank makes a skill you chose stronger *and* moves
  you toward the next slot. There is no purchase whose only purpose is to be a
  prerequisite.
- **The build decision becomes legible.** Full commitment to one colour is 25 ranks —
  every skill maxed, +32.5% affinity, and the capstone. Spreading evenly across five
  colours is 5 ranks each — ten different skills at rank 1–2, +10% in each, and no
  capstone at all. Breadth versus depth, stated in one number.
- **Nothing is grindy, because nothing is mandatory.** You reach slot 5 by ranking up
  the skills you actually use, in any order you like.

> Implementation is small: `Player.affinity_ranks[colour]` stops being incremented by
> its own node and starts being incremented by `SignalBus.spell_unlocked`.
> `affinity_spell_rank_requirements` keeps its job, just with the numbers above.

### 2. Auras — keep all ten, and make choosing one the point

**Do not replace the existing five.** They are not placeholders; Phyrexian Arena in
particular (×1.25 damage and ×1.15 speed, paid for by draining 1.5% max HP per second)
is a genuine risk/reward design that nothing in the new roster reproduces. Deleting
working content to make room for planned content is how a game ends up with the same
amount of content forever.

**Fix: the capstone is one slot with two options per colour.** The tension identified
earlier — that the old auras are *numbers* and the new ones are *presence* — is not a
problem to resolve. It is the most interesting fork in the tree, so make it the fork.

| Colour | Attunement — the stat line | Manifestation — the visible one |
|---|---|---|
| White | **Glorious Anthem** · 35 shield, ×1.15 damage | **Healing Orb** · heals the lowest-health ally every 2s |
| Blue | **Rhystic Study** · ×0.7 cooldowns, 15 shield per cast | **Orb of Frost** · orbits and fires ice, damage + slow |
| Black | **Phyrexian Arena** · ×1.25 damage, ×1.15 speed, −1.5% HP/s | **Grave Pact** · kills leave souls that heal and stack damage |
| Red | **Fervor** · ×1.15 attack and movement speed | **Orb of Fire** · orbits and fires bolts, damage + burn |
| Green | **Sylvan Library** · ×1.35 max HP, +3 HP/s | **Trample** · enemies near you take damage while you move |

One capstone per run, as today — `Player.unlocked_capstone_aura` is already a single
string, so this costs almost nothing to build.

**Why players like this better:**

- **Ten capstones instead of five**, with no new colour design and nothing deleted.
- **The choice is legible without a spreadsheet.** "Do I want to be stronger, or do I
  want something fighting alongside me?" is a question a player can answer on instinct
  the first time they see it, and second-guess happily on the tenth run.
- **It is an identity, not an optimisation.** Capstones should be the thing you name
  your build after. "Orb of Fire red" and "Fervor red" are two different builds; ×1.15
  attack speed is not a build.
- **Both halves stay honest.** Attunements are stronger on paper; Manifestations do
  work while you are somewhere else — which, in a five-lane tower defence where you can
  only stand in one lane, is worth more than it looks.

> **Keep the capstone un-ranked.** One purchase, expensive, permanent for the run. The
> moment it becomes rankable it turns back into a stat slider, and the fork stops being
> a decision.

### What this does to the roster

Each colour becomes **five rankable skills plus one capstone chosen from two**. The
"Aura:" rows in the tables above are the Manifestation column here, not a sixth
rankable skill — which also resolves the orbiting-orb duplication, since all three orbs
are now one shared implementation used by exactly one capstone each.

## Guild camps — the unused back corners

Each lane is a trapezoid, not a circular sector, so its far edge is a straight chord.
That leaves the two back corners sticking out well past where anything happens:

| Point | Radius from crystal |
|---|---|
| Far-edge midpoint — where enemies march | 184.5 |
| Enemy spawner | 179.5 |
| **Far-edge corner** | **228.0** — 43.5 further out, 134 units to the side |

Each corner sits **exactly 36° off its lane's centreline**, which is precisely the wedge
boundary — so **adjacent lanes share their back corners**. Five outer corners, and each
one belongs to two neighbouring colours at once.

Because the lane order is WUBRG, those pairs are the five **allied guilds**:

| Corner | Guild | Camp reward |
|---|---|---|
| White \| Blue | **Azorius** | Both colours' mana, plus a wave-long order buff |
| Blue \| Black | **Dimir** | Both colours' mana, plus a wave-long stealth/vision buff |
| Black \| Red | **Rakdos** | Both colours' mana, plus a wave-long damage buff |
| Red \| Green | **Gruul** | Both colours' mana, plus a wave-long speed buff |
| Green \| White | **Selesnya** | Both colours' mana, plus a wave-long myr buff |

No geometry change is needed. The camps go at world radius ~215 on the five boundary
angles — inside the existing navmesh, in space nothing currently uses.

### Active between waves, not during

This is the one place to diverge hard from the MOBA original. LoL's jungle exists
because five players share three lanes, so it creates a *role*. Here there is one player
and five lanes — **the player is already the jungler**, and adding a sixth concurrent
demand during a wave only guarantees they fail something.

`GameSettings.wave_rest_period` is currently dead time. Put the camps there:

- **During a wave** — camps are inert. Defend.
- **Between waves** — camps are up. Clearing them is the income and upgrade window.

That converts a hole in the pacing into the most interesting decision of the loop, and
costs the defence nothing. It also gives a natural difficulty dial: clear all five and
start the next wave late but stronger; skip them and start on time but poorer.

> **Do not give camps independent respawn timers.** That is a MOBA idiom and it fights a
> wave-paced game. Tie them to the wave counter.

> **Do not add a Baron.** The centre of this map is already the crystal — the most
> contested point in the game. A second central objective would compete with it.

---

## Skill tree — choice at every step

The tree today is five linear chains: a colour's spells unlock at affinity ranks
1 / 5 / 10 / 15 / 25, in a fixed order. You never choose *which* spell, only when. The
goal here is that **every purchase presents at least two real options, and no skill is
ever a prerequisite for another.**

### The rule that makes it non-linear

**Gates are on total investment in a colour, never on a specific skill.** You can reach
anything in ring 2 without owning any particular ring 1 skill — you just have to have
spent enough in that colour, on whatever you liked.

### Per colour: two rings and a fork

| Ring | Contains | Opens at | Choice |
|---|---|---|---|
| **1 — Core** | 2 skills | immediately | which to start with, and which to deepen |
| **2 — Specialist** | 3 skills | 3 ranks in this colour | three-way, and against ring 1 |
| **3 — Capstone** | 2 options | 12 ranks in this colour | **exclusive — pick one, permanently** |

Ring 1 holds the skills that work with no setup and read instantly at rank 1. Ring 2
holds the ones that need positioning or are situationally stronger.

| Colour | Ring 1 — Core | Ring 2 — Specialist | Ring 3 — Capstone fork |
|---|---|---|---|
| **White** | Exalted Strike · Circle of Protection | Reprisal Ward · Wrath of God · Rally the Fallen | Glorious Anthem **or** Healing Orb |
| **Blue** | Unsummon · Frostwave | Frost Globe · Suction · Phantasmal Decoy | Rhystic Study **or** Orb of Frost |
| **Black** | Doom Blade · Fear | Kill · Wall of Souls · Zombify | Phyrexian Arena **or** Grave Pact |
| **Red** | Fireball · Fire Dash | Rain of Ember · Fire Cone · Lightning Bolt | Fervor **or** Orb of Fire |
| **Green** | Leap Slam · Giant Growth | Fog · Roar · Ironbark | Sylvan Library **or** Trample |

The capstone is the **only** exclusive choice in the tree. That is deliberate: one
permanent, irreversible fork per colour is memorable, and ten of them would be paralysing.

### Guild nodes — the tree mirrors the map

Five extra nodes sit **on the boundaries between adjacent branches**, in the same
positions as the guild camps on the map. Each needs **5 ranks in both** of its
neighbouring colours, so only a genuine two-colour build can reach one.

| Node | Colours | Effect |
|---|---|---|
| **Azorius** | W + U | Enemies affected by your freeze, stun or root also take reduced damage output |
| **Dimir** | U + B | Enemies killed while frozen or stunned drop double mana |
| **Rakdos** | B + R | Your burn and drain effects heal you for a share of the damage |
| **Gruul** | R + G | After a Leap Slam or Fire Dash, your next melee hit is empowered |
| **Selesnya** | G + W | Your myrs receive every shield and heal you cast on yourself |

These are the payoff for the multicolour discussion: a two-colour build gets a node no
mono-colour build can reach, in the tree *and* a camp on the map, both named for the
same guild.

### What the player actually faces

- **First purchase of the run:** 2 core skills × 5 colours = **10 options**.
- **After 3 ranks in a colour:** that colour offers 5 skills to deepen.
- **After 5 ranks in two adjacent colours:** a guild node appears that mono-colour
  players never see.
- **At 12 ranks:** one irreversible fork.

At no point is there a single "next" node to click.

### Respec

Choice-heavy trees need an undo, or players stop experimenting by wave 10 and just copy
whatever worked once. Cheapest version that stays honest: **refund at a loss** — sell a
rank back for half its mana, capstone excluded. The capstone stays permanent, which is
what keeps it feeling like a decision rather than a setting.

## Open questions

The two structural ones are answered under *Resolutions* above. What is left is
implementation:

1. **Frost Globe and Wall of Souls need placement UI.** Rain of Ember aims with a
   raycast from the camera; a wall needs an orientation too.
2. **Fear needs a flee behaviour** the navigation can express — enemies currently only
   path *toward* a target.
3. **Zombify, Call of the Herd and Phantasmal Decoy all need a friendly combatant** —
   something that fights, takes damage and expires. The myrs are close but harvest
   rather than fight. One shared "temporary ally" base would cover all three.
4. **Camp rewards need balancing against wave pacing.** Clearing all five guild camps
   delays the next wave; that has to be a real trade, not a free upgrade.

---

# Idea backlog — MOBA-inspired

Twenty-five candidates, five per colour, adapted from MOBA ability design. **None of
these are in the roster above** — each was picked specifically because it fills a
mechanical gap the current thirty do not cover. They are a menu to pull from, not a
second roster.

The **Gap** column is the point of the list: it says what the game currently *cannot
do*, which is the only reason to add a skill rather than rank up an existing one.

## Blue — control

Blue's gap is **space and time**. It can push, pull and freeze, but it cannot
reposition the caster, reshape the battlefield, or undo anything.

| Skill | Inspired by | Effect | Gap it fills |
|---|---|---|---|
| **Blink** | Flash / Kassadin's Riftwalk | Instantly reposition a short distance, straight through enemies and terrain. | **No instant reposition.** Red's Fire Dash travels; nothing teleports. |
| **Wall of Frost** | Anivia's Crystallize / Trundle's Pillar | Raises an impassable wall of ice for a few seconds. Enemies must path around it. | **No terrain creation** — and this is the single most valuable thing in a lane-based tower defence. Ranks widen the wall. |
| **Time Warp** | Ekko's Chronobreak / Zilean's Chronoshift | Snaps the player back to where they stood 3s ago, restoring the health they had then. | **Nothing undoes damage after the fact.** Every defensive skill has to be pre-emptive. |
| **Control Magic** | Mordekaiser's Realm of Death / Ahri's Charm | Takes over one enemy; it fights for you until the duration ends, then dies. | **No mind control.** Green's Roar redirects aggro; this changes sides outright. |
| **Cyclonic Rift** | Global ultimates (Ashe, Ezreal) | Every enemy on the map is shoved a fixed distance back down its lane. | **No global reach.** A pure panic button for a wave that got away from you. |

## Red — aggression

Red's gap is **persistence and reach**. Everything it has is one instant, in front of
the caster, that the player must aim personally.

| Skill | Inspired by | Effect | Gap it fills |
|---|---|---|---|
| **Arc Lightning** | Ryze's Spell Flux / Brand's spread | A bolt that jumps between enemies, losing damage per jump. | **Nothing chains.** All red area damage is a fixed shape; this scales with how packed the lane is. |
| **Powder Keg** | Ziggs / Zilean's Time Bomb | Sticks a bomb to an enemy that detonates after 3s — **immediately** if that enemy dies first. | **No delayed damage**, and no reward for killing the right target. |
| **Goblin Sharpshooter** | Heimerdinger's turrets | Deploys a small flame turret that fires on its own for a duration. | **Nothing fights without the player.** The one skill that keeps working while you defend another lane. |
| **Seismic Rupture** | Malphite's Unstoppable Force | Launches enemies in a line **upward**; they land stunned. | **No knock-up.** The roster has knockback only, which pushes enemies *toward* the crystal as often as away. |
| **Blood Frenzy** | Tryndamere / Aatrox | Damage scales up as the player's own health falls. | **No risk/reward axis.** Every other buff is unconditional. |

## Green — primal vitality

Green's gap is **bodies on the field**. It buffs the player and denies ground, but the
player is always the only thing fighting.

| Skill | Inspired by | Effect | Gap it fills |
|---|---|---|---|
| **Call of the Herd** | Annie's Tibbers / Ivern's Daisy | Summons a beast that fights alongside you for a duration. | **No combat summon.** Myrs harvest mana; nothing of yours attacks. |
| **Tanglevine** | Zyra / Maokai roots | Roots enemies in an area — they can still attack, but cannot advance. | Uses `root_timer`, **which nothing currently sets.** Distinct from freeze: rooted enemies still fight. |
| **Feast** | Cho'Gath's Feast | Devours an enemy below a health threshold, killing it and granting a **permanent** stack of max HP. | **Nothing persists across a wave.** The only permanent progression outside the tree. |
| **Wurmcoil Vigor** | Warwick / Aatrox lifesteal | Regeneration plus melee lifesteal for a duration. | **Green has no sustain**, despite being the vitality colour — all healing is white's. |

> **Ironbark** was here and has been **promoted into the roster** above, replacing
> Primal Rampage.

## Black — parasitic drain

Black's gap is **the aftermath**. It kills efficiently but nothing happens as a result
of a death, and corpses already sit in the scene doing nothing.

| Skill | Inspired by | Effect | Gap it fills |
|---|---|---|---|
| **Contagion** | Twitch's Deadly Venom / Malzahar's Void Swarm | A poison that **spreads to nearby enemies when the infected one dies**. | **Nothing chain-reacts.** Scales with density instead of with aim. |
| **Death Mark** | Zed's Death Mark | Marks an enemy; after 3s it takes a **second copy** of all damage dealt to it while marked. | Wall of Souls multiplies damage passively in a zone; this rewards **dumping everything into one target on a timer**. |
| **Sanguine Pool** | Vladimir's Sanguine Pool / Zhonya's | The player sinks into blood: **untargetable** for ~2s while draining everything standing over them. | **No invulnerability window.** The only true escape in the game. |
| **Damnation** | Karthus's Requiem / Fiddlesticks' Crowstorm | After a visible wind-up, every enemy **on the map** takes heavy damage. | Black's only answer to a wave it has already lost track of, paid for with a long telegraph. |

> **Zombify** was here and has been **promoted into the roster** above, replacing
> Vampiric Drain.

## White — protection and restoration

White's gap is **the crystal and the myrs**. It shields and heals the player well, but
the thing you actually lose the run to is barely protected at all.

| Skill | Inspired by | Effect | Gap it fills |
|---|---|---|---|
| **Angel's Grace** | Kayle's Intervention / Zhonya's | One target — player, ally, **or the crystal** — becomes fully invulnerable for ~2.5s. | **Nothing can protect the crystal outright.** The single highest-value skill in the list for a tower defence. |
| **Benediction** | Lulu's Wild Growth / Taric | Buffs one ally or myr: bonus HP, damage and speed for a duration. | **No ally-targeted buff.** Circle of Protection only shields; nothing makes an ally *better*. |
| **Rule of Law** | Soraka's Equinox (silence) | Enemies in an area cannot use special abilities — **including boss specials** — for a duration. | **No silence.** Boss specials are telegraphed and dodgeable but never preventable. |
| **Word of Recall** | Recall / Bard's Magical Journey | Returns the player, and nearby myrs, instantly to the crystal. | **No long-range travel.** The map is five lanes; crossing it is pure walking time. |
| **Martyr's Bond** | Taric's link / Kindred | Redirects a share of the damage nearby allies take **onto the player instead**, where block and reflect apply to it. | **No damage redirection.** Turns white's personal defences into team defences. |

## Reading the list

If only five of these ever get built, these are the five that change the game most,
because each one makes the map itself part of the fight:

1. **Wall of Frost** — the only skill that reshapes where enemies can walk.
2. **Angel's Grace** — the only skill that can save the crystal outright.
3. **Goblin Sharpshooter** — the only thing that fights while the player is elsewhere.
4. **Control Magic** — the only skill that removes an enemy by making it yours.
5. **Seismic Rupture** — knock-*up* rather than knockback, which is the difference
   between buying time and shoving an enemy closer to the crystal.

Several also unlock unused engine state for free: `root_timer` (Tanglevine) and
`blind_timer` (still unclaimed) are already ticked down every frame by `EnemyBase` and
set by nothing.
