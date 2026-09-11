# Skill Unlocking Rework

A plan for replacing the tree's level gates with **connectivity**: a skill is reachable
because you own something next to it, not because the team hit a number.

Written against the branching layout added in `SkillTree.BRANCH_LAYOUT` / `BRANCH_EDGES` —
that layout is what makes this possible, because the tree now *has* edges to walk.

## Status: built

Decided and implemented, in this order:

| Decision | What was chosen |
|---|---|
| Blade Dance | Not a node at all. Granted at team level 10 (`Player.BLADE_DANCE_LEVEL`) |
| Unlock gate | Connectivity **and** colour investment, ladder `1/2/5/7/10` |
| What "investment" counts | `Player.color_investment` - the colour's affinity ranks plus every rank in its five spells |
| Rank gate | The same ladder. Team level no longer gates a rank at all |
| Unreachable nodes | Mana symbol only, no name, no description, no cost. Committed, no switch |
| Trample collision | The aura is now **Stampede**; the Gruul passive keeps "Trample" |

Auras and guild passives were deliberately left on their existing rules: the aura
fork stays visible so the choice between the two halves remains legible all run, and the
passives sit between colours rather than inside one, so a colour's edges say nothing about
them.

## Where it stood

| Rule today | Where |
|---|---|
| A spell's first purchase needs `team_level >= rank_requirement` | `SkillTree._gate_met` |
| Those requirements are 1 / 5 / 10 / 15 / 25 by branch | `GameSettings.affinity_spell_rank_requirements` |
| Ranks 2-5 need team level 1 / 3 / 5 / 7 / 9 | `GameSettings.spell_rank_level_requirements`, `Player.spell_rank_blocker` |
| Nothing checks whether a *neighbouring* node is owned | — there is no such check anywhere |
| Every node shows its real icon at all times, dimmed when locked | `SkillTree.update_ui`, `_icon_modulate` |
| The hub is Blade Dance, a colourless melee purchase | `CENTER_INFO`, `_on_node_pressed`'s `is_center` branch |

So the tree is a **shape** today, not a structure: a player at team level 25 can buy any
red node in any order, and a player at level 4 cannot buy the fifth one no matter what
they own. The fan layout says "these three grow out of those two" and the rules say
nothing of the kind.

---

## 1. Connectivity replaces the unlock gate

**Rule:** a spell can be bought when **any node joined to it by an edge is already
owned** — and the colour's affinity node is joined to the hub, so every colour opens the
same way it does now: buy the affinity, then its two openers become reachable, then the
three beyond them.

`BRANCH_EDGES` already describes exactly this graph, so the check is a lookup rather than
a new data structure:

```
[CENTER, 0]   affinity is always reachable
[0, 1] [0, 2] the two openers need the affinity
[1, 3] [1, 4] [2, 4] [2, 5]   the finishers need an opener
[4, cap0] [4, cap1]           the fork needs the middle finisher
```

Two consequences worth deciding on now:

- **The middle finisher has two parents.** Either opener unlocks it. That is the diamond
  the layout already draws, and it is what stops one opener being mandatory.
- **`affinity_spell_rank_requirements` stops gating unlocks.** It should not simply be
  deleted: it is still the natural home for "how much of this colour do you need", and the
  cleanest replacement is to keep it as an **affinity-rank** requirement (own N ranks of
  the colour's affinity) rather than a team-level one. That keeps a colour's depth
  meaningful without freezing the player out on a clock.

**Balance note, stated plainly:** removing the level gate means a player who funnels
everything into one colour can hold that colour's tier-5 spell far earlier than today.
That is the point of the change, but it is a real shift — Lightning Bolt at team level 3
is a different game. The affinity-rank requirement above is the dial that controls it.

## 2. Three visual states, and the hidden one is new

| State | Icon | Detail panel |
|---|---|---|
| **Unreachable** — no owned neighbour | the colour's **mana symbol**, heavily greyed | nothing: name, description and cost all withheld |
| **Reachable** — a neighbour is owned, not bought yet | the spell's **real icon**, still dimmed | full details |
| **Owned** | the real icon, full brightness | full details, plus rank |

The mana symbols already exist and are already loaded by `SpellDatabase.get_icon_path`
(the HUD's mana row and the base screen's lane buttons both draw them), so the unreachable
state costs no new art.

This is the part that changes how the screen *reads*: a colour you have not touched is
five identical grey pips, and the tree tells you where you can go rather than showing you
everything you cannot have. It is also the part most worth playing before committing to —
hiding names removes information a planning-minded player currently uses. Worth building
behind a switch so it can be compared both ways.

## 3. The hub shows the level

Blade Dance comes off the centre and the team level goes there — the number every gate in
the tree used to reference, in the middle of the board.

**Blade Dance needs somewhere to live.** It is colourless, which is why it was in the
middle. Three options, in the order I would pick them:

1. **The Gruul passive slot's neighbour** — it is a melee extension, and the red/green gap
   is already where the melee passives sit. Concretely: make it a sixth guild node.
2. **A red or white opener** — it fits red (aggression) or white (discipline) thematically,
   at the cost of making a colourless mechanic colour-locked.
3. **Cut it** — fold the third combo stage into a Trample or Haste rank.

This is a design call, not a technical one, and it is the only part of this plan I would
not start without an answer.

## 4. Softer rank gates

Ranks 2-5 currently need team level 3 / 5 / 7 / 9. Softening options, cheapest first:

- **Lower the ladder** to 2 / 3 / 5 / 7 — keeps the shape, removes the late-game wall.
- **Gate on the colour instead**: rank N needs N ranks of that colour's affinity. Ties
  depth to investment rather than to the clock, and matches §1's replacement.
- **Drop the gate entirely** and let skill points be the only cost. Simplest; makes the
  first hour considerably swingier.

Recommendation: the second, so unlocking and ranking are governed by the *same* idea
(affinity investment) rather than two unrelated ones.

## 5. Trample is two different things

`trample_strike` (Gruul passive — melee hits add a fraction of max HP) and `aura_trample`
(green's Manifestation aura — damage to nearby enemies while moving) both display as
**"Trample"**. In a tree where both are visible at once, that is simply a bug in the
naming.

Rename the **aura**, since the passive is the one that matches the MTG keyword:
`aura_trample` → **"Stampede"**, which keeps the moving-damage idea and is unambiguous.
One string in `SpellDatabase` plus the `docs/SKILL_DESIGN.md` row; the id stays.

---

## Order of work

1. **Trample rename** — isolated, five minutes, removes a live ambiguity.
2. **Connectivity gate** (§1) with the old level gate behind `debug_free_skills`, so both
   rules can be exercised from the same build.
3. **Node states** (§2) — the visual half, once the reachability query exists to drive it.
4. **Hub becomes the level readout** (§3) — needs the Blade Dance answer first.
5. **Rank gate softening** (§4) — last, because it is a tuning pass and wants the rest
   already in place to judge against.

## What to assert

`tools/tests/skill_purchase.gd` already drives the board the way a player does. Extend it
with: an unreachable node refuses purchase; buying the affinity makes exactly the two
openers reachable; buying one opener makes its finishers reachable and leaves the other
opener's exclusive finisher unreachable; and an unreachable node exposes no name in the
detail panel. That last one is the only assertion that catches §2 regressing, and it is
the part most likely to be quietly undone by a later change.
