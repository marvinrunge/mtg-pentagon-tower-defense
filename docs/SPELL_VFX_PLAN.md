# Spell VFX Plan

A phased plan for making the 25 spells look authored rather than placeheld. Each phase
ships something visible on its own — no phase leaves the game half-dressed while the next
one is built.

The target is not "more particles". It is that a player who has never read the skill tree
can tell, from one second of footage, **which colour cast it, how big it was, and whether
it hit** — and that the same effect still runs on the integrated GPU the graphics presets
in `scripts/graphics_settings.gd` exist for.

## Where the project actually stands

The foundation is better than the output suggests. One system is genuinely good and the
rest of the spells never got past their placeholder.

| Already here | Where |
|---|---|
| A real fire VFX system: body + sparks, white textures tinted by gradients | `scripts/ember_fx.gd` |
| Pooled projectiles with a trail and a moving light | `scripts/projectile.gd`, `scripts/projectile_pool.gd` |
| Persistent zone effects (rain, ground fire, souls, frost globe) | `dot_zone.gd`, `soul_wall.gd`, `frost_globe.gd` |
| Camera shake as a signal any spell can raise | `SignalBus.camera_shake_requested` |
| Per-spell sound, already tied to the cast | `SoundBank`, `SpellDatabase` rows |
| Effects fired on the animation's own release frame, not on the keypress | `Player._begin_cast`, `PlayerAnimator.release_time` |
| Quality presets, including a Compatibility-renderer tier | `GraphicsSettings.apply_preset` |
| A sourcing guide for white-on-transparent textures | `docs/VFX_TEXTURES.md` |

And three problems, in the order they hurt:

**1. Nineteen of the twenty-five spells are drawn with three generic primitives.**
`Player._spawn_ring` (a torus), `_spawn_beam` (a cylinder) and `_spawn_cast_flash` (an
omni light) account for 21 call sites. They are honest placeholders — the comment above
them says so — and they are why Wrath of God, Fear, Roar and Ironbark are all "a coloured
ring that grows and fades". Unsummon draws *nothing at all*: it shoves and shakes the
camera and that is the whole effect.

**2. There is no shader work anywhere.** Every effect is untextured emissive geometry with
`BLEND_MODE_ADD` and a tween on its alpha. That ceiling is low and the whole game hits it
at once: no soft particles, no distortion, no dissolve, no scrolling, no ground decals.
`assets/vfx/` holds exactly two placeholder textures.

**3. Nothing a client casts is visible to anyone.** `Player.execute_spell` forwards to the
server and returns, so on a client the spell's own visuals never run locally; on the host
they run at the client's position. Projectiles and VFX have no `MultiplayerSpawner`, unlike
players, enemies and myrs. In co-op today, four of five players see almost no magic.

---

## Visual language: one grammar, five dialects

Decide this before building anything, because it is what stops 25 effects from being 25
unrelated ideas. Every spell is built from the same four beats, and only the *material*
changes per colour.

**The four beats** (they map onto timings the code already has):

| Beat | When | What it does |
|---|---|---|
| Charge | the cast clip's lead-in, `_begin_spell_windup` | light gathers at the hand; tells other players what is coming |
| Release | the clip's measured release frame | the loud frame: flash, shockwave, sound, shake |
| Body | 0.2–1.5s after release | the thing itself — the bolt, the wave, the zone |
| Settle | 0.5–3s | what it leaves behind: scorch, frost, ash, motes |

Skipping "settle" is the single biggest reason effects read as cheap. A fireball that
leaves a scorch decal for three seconds is worth more than one with twice the particles.

**The five dialects** — colour, motion and material per MTG colour, so the palette is a
rule rather than a per-spell choice:

| Colour | Palette | Motion | Material |
|---|---|---|---|
| White | warm ivory → gold, high value, low saturation | outward, symmetrical, slow rise | volumetric light shafts, lens-flare glints |
| Blue | pale cyan → deep indigo | inward, precise, snapping | refraction, crystalline shards, hard edges |
| Black | violet → near-black, low value | falling, curling, sucking | smoke that eats light, negative-space voids |
| Red | white-hot → orange → cooling grey (already built) | explosive, asymmetric, fast decay | fire body + sparks + heat haze |
| Green | spring green → deep forest, earth browns | growing, springing, settling | pollen motes, leaves, dust, root geometry |

Two rules that keep it coherent: **saturation is intensity, not colour** (a rank-5 spell is
brighter and lasts longer, never a different hue), and **every effect gets exactly one
bright core** — overlapping additive blobs with no dark anywhere is what makes hobby VFX
read as hobby VFX. `ember_fx.gd`'s header already argues this for fire; the rule is general.

---

## Phase 1 — Replace the three primitives with a real effect layer

**Status: done, bar polish.** `scripts/spell_fx.gd` exists with `shockwave`, `beam`,
`sparks`, `impact`, `cast_glow` and `ground_decal`; the three old helpers are forwarders
into it, so all 21 call sites moved at once. The settle beat is wired for four spells
(Fireball scorch, Frost Breath frost, Fear blight, Wall of Souls footprint). The five dialect
colours are constants in `Player` (`FX_WHITE` … `FX_GREEN`) rather than literals typed per
call site, which is how white had ended up with four different whites.

**The aura orbs were the last holdout** and were caught on 2026-09-10. `OrbitingOrb`
predates the effect layer and never moved onto it: its bolts were still built as emissive
CYLINDERS, the exact thing `energy_beam.gdshader`'s own header says it exists to replace,
which is why the orbs' shots looked untouched while every spell's beam had been redone. They
go through `SpellFx.beam` now, and each shot LANDS - a flash and a scatter of points, in the
mode's own texture slot (shard / spark / mote). Two of the three orb BODIES were in the same
state: only the Winter Orb had a real material, a shell and orbiting particles, while Orb of
Fire and Healing Orb were unshaded emissive spheres - flat circles with no rim and no light
falling across them, which is the whole reason they read as placeholder next to the blue one.

**Every one of the 25 now draws something**, which was not true before: Giant Growth had no
effect of any kind, and Fireball, Rain of Ember, Fire Dash and Titanic Brawl had no moment
at the CASTER — their visuals lived entirely in the projectile, zone or trail they created,
so the caster played a full cast animation with nothing happening near them.

What remains here is taste, not coverage: the spells that share `shockwave` could each have
a shape of their own, and Wall of Souls is the model for what that looks like (its own
shader, its own particle set, its own ground strip — see `scripts/soul_wall.gd`).

The highest return in the plan, and it touches no gameplay code.

Build `scripts/spell_fx.gd` as a sibling of `EmberFx`: same shape (a `RefCounted` of
static builders), same "white texture, colour from the gradient" rule, but covering the
shapes the other four colours need.

| Builder | Replaces | Shape |
|---|---|---|
| `shockwave(radius, colour)` | `_spawn_ring` | expanding ring on a scrolling-UV shader, thin leading edge, ground-hugging, fades by distance rather than by a flat alpha tween |
| `beam(from, to, colour)` | `_spawn_beam` | a quad billboard with a soft-edged gradient and a bright core, not a cylinder |
| `cast_glow(colour)` | `_spawn_cast_flash` | the light, plus motes converging on the hand during the charge beat |
| `impact(point, normal, colour)` | *(nothing today)* | the release beat: flash quad, radial sparks, one decal |
| `ground_decal(radius, texture)` | *(nothing today)* | the settle beat: scorch, frost, blight, growth |

Keep the three old helpers as thin forwarders during the phase so all 21 call sites keep
working, then delete them once every spell has moved.

**Then go spell by spell, worst first.** Unsummon (no visual at all), Wrath of God, Fear,
Roar, Ironbark, Circle of Protection — the ones that currently share one ring.

## Phase 2 — Textures and shaders

Phase 1's builders are only as good as what they draw with. From `docs/VFX_TEXTURES.md`'s
source list, take white-on-transparent: a **shockwave crescent**, a **branching arc** (blue
and white), a **soft smoke wisp** (black), a **leaf/pollen speck** (green), a **star glint**,
and 3–4 **decal masks** (scorch, frost, blight, cracked earth).

Four shaders carry almost all of it, none of them large:

1. **Soft particles** — fade a particle where it intersects geometry, using the depth
   texture. Kills the hard cut where every current effect meets the ground.
2. **Scrolling dissolve** — one noise texture and a threshold. Turns a ring into a
   shockwave and a decal into something that burns away instead of blinking off.
3. **Heat haze / refraction** — screen-space UV offset on a quad. One shader that serves
   red's fire, blue's ice and the boss telegraphs.
4. **Additive beam** — soft radial falloff plus a scrolling core, so beams stop being
   cylinders.

Rendering-wise, the Compatibility tier in `GraphicsSettings.apply_preset` cannot run the
depth-texture and screen-texture ones. Gate those two on the preset and let the effect fall
back to its unshaded form — that is a build-time decision, so plan it now rather than
discovering it at the preset switch.

## Phase 3 — Impact, weight and feedback

Visuals that do not confirm a hit read as decoration. Every damaging spell needs, in order:
a **flash on the target** (2–3 frames, white, on the enemy's own material), the existing
**damage number**, a **hit-reaction or knockback** already supported by `EnemyBase`, and a
**shake scaled to the spell's actual damage** rather than a hand-typed constant per cast.

Two cheap additions that buy the most:

- **Hit-stop.** 40–80ms of `Engine.time_scale` dip on a heavy impact, only for the local
  player and never in multiplayer, where it would desync the feel from the simulation.
- **A charge tell.** The wind-up beat now exists in code (`_begin_spell_windup`) and draws
  nothing. Light gathering at the hand for the length of a Fireball hold is free drama and
  reads to *other* players as "get clear".

## Phase 4 — Make it visible to everyone

Purely a multiplayer correctness fix, but it is the difference between four of five players
seeing magic and not.

Split the effect from its authority the way melee already is: `Player._begin_action`
RPCs *what started* and lets each peer's own code draw it. Casts need the same — an
`@rpc("call_local")` carrying `(spell_id, position, aim, rank)` — while damage stays
server-authoritative. Projectiles then need either a `MultiplayerSpawner` beside the three
in `main.tscn`, or the same treatment: replicate the shot, simulate the visual locally.

Once that exists, the charge tell from Phase 3 becomes information other players can act
on, which is the point at which the VFX are doing something for the co-op design.

## Phase 5 — Budget and polish

- **Pool the VFX nodes** the way `projectile_pool.gd` pools bolts. A late wave with a
  firestorm burning and five players casting currently allocates a `MeshInstance3D`, a
  material and a `Tween` per effect and frees them a second later.
- **Cap concurrent effects** — a hard ceiling per category, oldest recycled first. A
  screen with 40 overlapping additive rings is both slower and less readable than one with
  eight.
- **Drive particle counts from the graphics preset**, one multiplier, applied in the
  builders rather than at each call site.
- **Bloom is a budget, not a switch.** Emission energies were tuned per spell in isolation
  (3.5 for a ring, 6.0 for a beam); pick one HDR range and normalise every effect to it.

---

## How to know it worked

Build `tools/tests/spell_showcase.tscn` — the same idea as `skill_roster.tscn`, but for
looking rather than asserting: cast all 25 in sequence at a fixed camera, at rank 1 and
rank 5. It is the only way to see the palette as a set, and it is what makes an
inconsistency obvious instead of arguable.

Two checks worth automating alongside it: that every spell spawns at least one visual node
(the roster test's existing shape), and that no effect outlives its cap.

**Order, if the whole plan is too much at once:** Phase 1 for the four colours that have no
identity yet, then Phase 3's impact flash and hit-stop, then Phase 4. Phase 2's shaders are
the largest and least urgent — good textures in the Phase 1 builders already get most of
the way there.
