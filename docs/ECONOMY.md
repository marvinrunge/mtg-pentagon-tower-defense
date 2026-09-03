# Economy — XP, Skill Points and Mana

Three currencies with three different owners. This supersedes the earlier per-player
mana design, which tried to make one currency serve both personal builds and team
purchases and produced a division problem it could not solve.

| Currency | Owner | Earned by | Spent on |
|---|---|---|---|
| **XP** | Team, shared | Every kill, by anyone, anywhere | Nothing — it produces levels |
| **Skill points** | **Personal** | Levelling up · bought at Upkeep | Your own skill tree |
| **Mana** | **Team, shared** | Kills, coloured by the enemy | Team purchases, at Upkeep only |

The split is the whole design: **skill points answer "what do I want to play", mana
answers "what do we need to survive".** They never compete, so no player ever has to
choose between their own build and the team's.

---

## XP and levels

**All XP is shared.** Every kill by any player adds to one team pool, and **everyone
levels at the same moment.** No last-hit, no kill-stealing, no contested pickup, and no
reason to care who landed the blow.

| Source | XP |
|---|---|
| Basic enemy | 10 |
| Elite | 40 |
| Boss | 250 |
| Guild camp cleared | 120 |

**Each level grants every player one skill point.** Levels are simultaneous; what each
player spends the point on is entirely their own.

Target curve: roughly **15–18 levels across a 25-wave run**, front-loaded so early levels
arrive every wave or two and late ones take three or four. With points also purchasable
at Upkeep, a player should finish with around **25 skill points** — a main colour built
deep plus one splash, matching the tree in `docs/SKILL_DESIGN.md`.

> Shared, simultaneous levels mean a player who joins late or dies repeatedly is never
> left behind. In five-player co-op that matters more than any individual reward would.

## Mana

**A single shared team pool, still coloured.** An enemy's death banks mana of its own
colour — `EnemyData.color_identity` already exists — so which lanes the team spends time
in still decides what it can afford. That is what keeps the pentagon meaningful now that
personal builds no longer depend on it.

| Source | Colour | Amount |
|---|---|---|
| Basic enemy | its own | 1 |
| Elite | its own | 4 |
| Boss | its own | 25 |
| Guild camp | **both** adjacent colours | 12 each |
| Myr well trip | its assigned lane's | 1 |

### Collection: automatic

**No pickup, no carrying, no deposit trip.** The pool is shared, so there is nobody for a
drop to belong to and no reason to make anyone walk to it. Mana banks the instant the
enemy dies.

Keep the visual — spawn a mote at the corpse that flies to the crystal. All the feedback,
none of the friction.

---

## Upkeep

**30 seconds between waves, at the base. Skippable when every player readies up.** This
replaces `wave_rest_period`, currently 3 seconds — long enough for nothing.

Upkeep is the only time mana can be spent, and it is the one moment each wave when the
whole team is in the same place. That is deliberate: team purchases should be made by a
team standing together, and the argument about what to buy is a feature.

Guild camps are only active during Upkeep, so clearing one costs shopping time.

### What the team can buy

| Purchase | Cost | Effect | Consensus needed |
|---|---|---|---|
| **Build a myr** | 2 colourless | A worker: harvests a lane, sweeps drops. Compounds, so worth most early | **Any player** |
| **Skill point for everyone** | 10 colourless | +1 point to *every* player | **Any player** |
| **Enchantment** | its colour, rising per stack | A permanent global buff | **Majority vote** |

Colourless costs are paid from any colour, so myrs and points are affordable if the team
has fought anywhere at all. Enchantments demand their own colour, which is what makes
lane choice strategic rather than only tactical.

---

## The Upkeep vote

Shared mana with five owners needs a way to decide. The rule is simple:

> **The bar rises with how permanent the purchase is.**

Nobody objects to a myr or to free skill points — those go through on one click, from any
player. Enchantments are permanent, colour-locked and shape the whole run, so they need
the team to agree.

### The panel

Opens automatically when Upkeep starts. Four regions:

1. **The pool**, across the top — five colour totals and the colourless equivalent, with
   income from the wave just finished shown as a delta so the team can see what the last
   wave earned them.
2. **The shop**, on the left — every purchase, its cost, and whether the pool covers it.
   Unaffordable items stay visible and greyed, with the missing colour called out
   (*"needs 6 more black"*), because knowing what you *cannot* buy is what drives the
   decision to go fight in a different lane next wave.
3. **The proposal queue**, in the middle — pending votes with live tallies.
4. **Ready checks**, along the bottom — five slots, one per player, and the countdown.

### How a vote runs

1. Any player clicks an enchantment. That **proposes** it; the mana is reserved, not
   spent, so two proposals cannot overdraw the pool.
2. Everyone gets a yes/no. The proposer counts as yes automatically.
3. **Majority of connected players passes it** — 3 of 5, 2 of 3, and with two players
   both must agree. It resolves the moment the majority is reached, without waiting.
4. A proposal that fails, or is still open when the timer ends, refunds its reservation.
5. The proposer can withdraw at any point.

Several proposals can be open at once; they resolve independently as votes land.

### Rules that keep it from being annoying

- **No vote can be re-proposed twice in one Upkeep** after failing, so one player cannot
  spam the same enchantment until people click yes to make it stop.
- **The timer is the backstop.** A team that cannot agree simply keeps its mana and moves
  on — indecision costs a wave of compounding, which is punishment enough.
- **Every resolved purchase is logged** in the panel and stays visible for the rest of
  Upkeep, so nobody has to ask what just happened to the mana.
- **Readying up is per-player and reversible.** All five ready ends Upkeep immediately.
  A player who unreadies stops the skip — useful when someone is mid-camp.
- **Single-player skips the whole system.** With one player there is no vote; everything
  is any-player, and the panel is a shop.

---

## Enchantments

Permanent, stackable, global. One per colour, each doing a job no other colour does, so
the team's enchantment spread becomes a visible statement of how they intend to win.

| Colour | Enchantment | Effect | Per stack |
|---|---|---|---|
| **Red** | **Furnace of Rath** | Every player deals more damage | +8% damage |
| **Blue** | **Propaganda** | All enemies attack and cast more slowly | −6% enemy attack speed |
| **Black** | **Exquisite Blood** | Every player heals for a share of the damage they deal | +3% of damage dealt |
| **White** | **Sphere of Safety** | Enemies near the crystal are slowed and deal reduced damage to it | +2 radius, +8% reduction |
| **Green** | **Overgrowth** | All mana income increases. Compounds | +12% mana |

**Costs rise per stack:** 8 for the first, then +6 each (8, 14, 20, 26, 32…), paid in
that colour.

### Why these five

Each sits in a different place in the team's decision-making, so the choice is never
obvious:

- **Green is the early buy.** It compounds, so its value is highest at wave 3 and near
  zero at wave 22 — exactly like the myrs it sits beside. Buying it is a bet on a long run.
- **Red is the honest buy.** More damage, always useful, never exciting. The benchmark
  every other enchantment is measured against.
- **Blue is the scaling buy.** Slowing enemy attacks is worth little against wave 3 and
  enormous against a boss that one-shots people.
- **Black is the sustain buy.** It keeps the *players* alive, where white keeps the
  *crystal* alive — different targets, so the two defensive colours never compete for the
  same slot. It is worth most to a team that is fighting well and dying anyway.
- **White is the insurance buy.** It does nothing while the team is winning and saves the
  run when they are not.

> **An earlier draft had Bitterblossom here** — free undead spawning each wave. It was
> wrong on three counts, worth recording so a replacement does not repeat them:
> it duplicated **Zombify**, black's own ring-2 skill; it was the only enchantment that
> spawned *entities* rather than modifying a global number, which is a much heavier build
> and a real performance risk in a game already spawning waves; and it did not match the
> brief of a global buff to all players.
>
> Exquisite Blood also costs almost nothing to build: `Player.on_damage_dealt()` already
> applies black-affinity lifesteal, so the enchantment is one more term in that same
> line.
>
> **The alternative, if sustain feels too safe:** *Culling the Weak* — every enemy below
> a health threshold dies instantly (+3% threshold per stack, bosses excluded, matching
> the boss clause on black's Kill skill). It is a genuinely different axis from flat
> damage and scales against high-HP late waves. It loses on *felt* impact, though: an
> execute threshold is invisible, where healing as you fight is not.

None of them is a damage number pretending to be a choice, and no ordering is correct for
every run.

Note that an enchantment **deliberately echoes its colour's affinity**: red's affinity is
damage and its enchantment is damage; black's affinity is lifesteal and its enchantment is
lifesteal. That repetition is the point — a colour should mean the same thing at every
layer of the game, so a player who likes what black does personally also knows what black
does for the team.

---

## Costs and pacing

Starting numbers, to be playtested rather than trusted.

| Wave | Enemies | Mana income | Team can afford |
|---|---|---|---|
| 3 | ~10 | ~12 | A myr, or start an enchantment |
| 5 | ~15 + boss | ~45 | Two enchantment stacks, or a point for everyone |
| 10 | ~25 + elites | ~40 | One good stack, plus a myr |
| 15 | ~35 | ~55 | A late enchantment stack |
| 25 | ~55 + boss | ~90 | Deep stacks, points for everyone |

The shape to protect: **at Upkeep the team should be able to afford roughly two of the
three things they want.** Afford everything and there is no decision; afford nothing and
Upkeep is a loading screen.

---

## What this fixes

Every problem the earlier drafts ran into disappears rather than being solved:

| Problem | Why it is gone |
|---|---|
| "Your lane dictates your build" | Builds cost skill points, which are colourless and shared |
| Contested drops, kill-stealing | Nothing is picked up; XP and mana pool on death |
| One player spending the team's mana | Mana buys only team things, by vote, with everyone present |
| A quiet lane starving a player | XP and levels are shared and simultaneous |
| 40-second harvest round trips | There is no pickup at all |
| Nothing to do in the rest period | Upkeep is 30 seconds of real decisions |

And the pentagon still matters: **enchantments need their own colour**, so a team that
never fights in the black lane never gets Exquisite Blood.

## What to delete

- The player's hold-E harvest, the carry-back trip, and the deposit-at-base flow.
- `Player.carried_color`, `player_carry_speed_penalty`, `player_mana_harvest_time`.
- Per-player mana pools, focus colours and wave grants from the previous draft — none of
  it is needed once mana is a team resource.

The mana wells stay: they are the myrs' passive job, and the reason assigning a myr to a
lane is still a decision.

## Open questions

1. **Does mana carry over between Upkeeps, or expire?** Carrying over allows saving for a
   deep stack; expiring forces a decision every wave. Carrying over is friendlier, and
   rising stack costs already discourage hoarding.
2. **Should enchantments be losable?** A boss that strips a stack would make them tense
   rather than monotonic, but it punishes the team for the thing they invested in.
   Probably not — worth remembering.
3. **How many skill points should a run give?** ~25 is the target. If levels alone give
   18, buying points at Upkeep needs to be attractive enough to happen ~7 times, which
   sets the 10-colourless price against everything else on the list.
4. **What happens to a disconnected player's vote?** Majority should count *connected*
   players, or one drop-out deadlocks every enchantment for the rest of the run.
