# Five-Player Multiplayer Plan

A phased plan for turning the game into five-player co-op. Each phase ends somewhere
playable — no phase leaves the game broken while the next one is built.

## Where the project actually stands

**There is no networking code at all** — no `multiplayer`, no `@rpc`, no peer setup,
nothing in `project.godot`. But the *gameplay* was already written for more than one
player, which is a far better starting point than it sounds:

| Already multi-player aware | Where |6
|---|---|
| Enemy damage scales with player count | `GameSettings.get_player_scaling_factor()` |
| Enemies pick targets from the whole player group | `EnemyBase.evaluate_target()` |
| Downed players and teammate revive | `Player.is_downed`, `down_timer`, `revive()` |
| Myrs react to every player | `myr.gd` |
| Minimap draws every player | `minimap.gd` |
| Shared mana pool | `MainController.mana_pool` |

So the design is co-op already. What is missing is plumbing, plus roughly a dozen
places that quietly assume "the player" is singular.

### The five-lane coincidence is not a coincidence

Five players, five lanes, five colours. One player per colour, defending their own lane
and farming their own mana, is the natural configuration — and the **guild camps sit on
the boundaries between adjacent lanes**, which means each camp is shared between exactly
two neighbouring players. Cooperation is built into the map's geometry before a line of
netcode is written.

---

## Architecture: host-authoritative, client-owned avatars

One player hosts and also plays (`ENetMultiplayerPeer.create_server`); the rest join.
No dedicated server — this is co-op PvE, and a lobby host is what players expect.

**Split authority, which is the decision that saves the most work:**

| Owned by the SERVER | Owned by EACH CLIENT |
|---|---|
| Enemies: spawning, AI, health, death | Its own player's position and rotation |
| Waves, bosses, boss specials | Its own player's animation state |
| Crystal health | Its own input, entirely |
| Mana drops and pickups | Its own camera, HUD, skill tree UI |
| Myrs | Cosmetics: sound, particles, damage numbers, screen shake |
| Guild camps | |

Client-authoritative movement means **no prediction and no reconciliation code**. In a
competitive game that would be unacceptable; in co-op PvE nobody is cheating, and the
payoff is that every player's own movement and melee feel exactly as they do today.

**Melee and spells** use the split: the client detects its own hit locally and plays the
sound, VFX and screen shake immediately, then RPCs the server, which range-checks it
loosely and applies the real damage. Enemy health is replicated back. Players see their
own hits instantly and other players' hits a ping late, which nobody notices.

### Godot 4 pieces to use

- `MultiplayerSpawner` — players, enemies, projectiles, myrs, DoT zones
- `MultiplayerSynchronizer` — transforms, health, animation state
- `@rpc("any_peer", "call_local", "reliable")` — discrete events (cast, hit, death)
- `set_multiplayer_authority(peer_id)` on each player node

---

## Phase 0 — Make single-player multiplayer-shaped ✅ DONE

No networking. The whole refactor risk in one phase, done while the game was easy to
test.

- `scripts/player_registry.gd` answers "whose screen is this". Every UI that called
  `get_first_node_in_group("player")` now asks `PlayerRegistry.get_local()`.
- `Player.is_local` gates the keyboard, the mouse capture and `camera.make_current()`.
  A remote player still runs its own timers and cooldowns but reads no input.
- `MainController.spawn_players(count)` rings N players around the crystal.
- `RunState` and the Upkeep panel were built as autoload/scene singletons rather than
  `MainController` state, precisely so they can become server-authoritative later.

**Verified in the running editor** at `player_count = 3`: three players at distinct
positions, exactly one current camera, remotes with `is_local = false`, difficulty
scaling at 0.60, and a clean output panel.

## Phase 1 — Connection and avatars ✅ DONE

Playable co-op with a shared world that only the host really simulates.

1. `scripts/net.gd`: host/join over `ENetMultiplayerPeer`, peer bookkeeping, and a
   `is_active()` that keeps every single-player path exactly as it is today.
2. A lobby: host or join by address, see who is connected, start.
3. `MultiplayerSpawner` for players; `set_multiplayer_authority(peer_id)` on each.
4. `MultiplayerSynchronizer` on the player: position, rotation and **velocity**.
   Velocity is the important one — `PlayerAnimator.update_locomotion()` already picks
   walk/run/strafe/idle from it, so replicating velocity gets every locomotion
   animation for free without replicating a single bone.
5. Enemies stay host-simulated and unreplicated for now; clients will see them stand
   still. That is the seam Phase 2 closes.

**Ends at:** two to five players run around the same map and see each other move
correctly.

## Phase 2 — The world replicates ✅ DONE

1. Enemies through `MultiplayerSpawner`; health, status and target via synchroniser.
2. `WaveManager` server-only, wave state broadcast for the HUD.
3. Crystal health server-authoritative; `crystal_damaged` becomes a server → client
   broadcast rather than a free-for-all signal.
4. **Melee hit RPC.** The client plays its own sound, VFX and shake immediately, then
   RPCs the server, which range-checks loosely and applies the real damage. This is
   also where attack ANIMATIONS replicate: send which action started and when, never
   the pose — `PlayerAnimator` reconstructs the rest locally.
5. Projectiles: the pool stays local for cosmetics; a projectile that deals damage is
   spawned by the server.
6. Boss specials and DoT zones: server decides, clients spawn their own
   `AttackIndicator` and `EmberFx` from the broadcast.

**Ends at:** a full wave, boss included, plays identically for every client.

### Phase 2b — Spell effects reach the other four screens ✅ DONE

Items 5 and 6 above were marked done and were not. Enemies, waves, the crystal and
attack animations all replicated; the effect layer did not. `Player.execute_spell`
hands a client's cast to the host and returns, so every visual inside
`_run_spell_effect` — ring, beam, decal, flash, sound, shake, zone, wall, summon,
telegraph, projectile — existed on the host and nowhere else. The client cast a spell,
the damage happened, and their own screen showed the arm animation and nothing more.

Closed by three mechanisms, one per kind of effect:

- **`NetFx` (`scripts/net_fx.gd`, autoload).** One-shot cosmetics. The shapes stay in
  `SpellFx`/`EmberFx`; what crosses the wire is which shape, where, what colour and how
  big, and each peer rebuilds it locally. Server → everyone for spell effects;
  client → server → everyone else for a client's own melee impacts, which stay
  immediate on the machine that swung. Camera shake is full strength for whoever caused
  it and distance-gated for everybody else.
- **`EffectNetSpawner` (`MainController._spawn_effect`).** The persistent half — DoT
  zones, both walls, Zombify's undead, Lightning Bolt's telegraph. A real
  `MultiplayerSpawner` alongside the enemy and myr ones, so the arguments travel and
  every peer builds its own copy. Gameplay inside them is server-only; the client
  copies exist to be looked at and to run their own lifetime.
- **`ProjectilePool.fire()`.** Broadcasts the activation parameters and lets each peer
  draw its own bolt from its own pool. `Projectile._on_body_entered` already refused to
  damage on a client — that guard was written for this and had nothing to guard.

Two things the same pass had to fix to make the above true:

- **A second synchroniser on `Player` (`VitalsSync`), authored by the host.** `hp`,
  `max_hp` and the three shields were on nothing. Enemies only think on the server, so
  the host was the only machine that knew a client had been hurt.
- **Fire Cone worked on the host alone.** The channel was started inside
  `_run_spell_effect` (server) but ticked in `_physics_process` under `is_local`
  (caster), so for a client neither machine ever ran it. The state is now server-side
  and ticked there, `_channel_id` replicates, every peer builds its own flames from it,
  and the caster's own keyboard reports the button coming up — the host cannot read it.

**Verified by** `tools/tests/net_effects.tscn`, which is cross-process on purpose: a
single-process test takes the `Net.is_server()` branch and passes with all of this
reverted. The client casts, looks at its own scene, and reports what it saw.

### Phase 2c — The skill build reaches the host ✅ DONE

Making a client's spells visible exposed the next layer down: they were visible and
**wrong**. `spell_ranks`, `aura_ranks`, `affinity_ranks` and `passive_ranks` were never
sent anywhere, so the host — which is where every spell is resolved — resolved a
client's cast against a freshly spawned, empty build. `_casting_rank` fell back to 1,
`has_aura()` answered false for everything, `get_spell_damage_multiplier()` found no
affinity, and `_update_shields()` had no Glorious Anthem to recharge. A client with a
maxed tree cast rank-1 spells with nothing behind them.

`Player.build_snapshot()` / `_apply_build()` carry it, broadcast by the owner rather
than sent to the host alone, because the aura ORBS come out of the same state and a
teammate's orbiting frost orb is theirs to show. `_publish_build()` is a dirty check
against the last JSON sent rather than a notification from each of the six places that
can change a build — a notification is something a future skill-tree change can forget
to send. `MainController._on_peer_entered_match` forwards every build to a player who
joins mid-match, since by then all the changes have already happened.

One thing had to be fixed alongside it: `SignalBus.player_health_changed` was emitted
unguarded from ten places in `Player`, so any avatar's health moved the local bar. It
goes through `_emit_health_changed()` now, which checks `is_local` the way
`emit_shield_changed()` always has.

### Phase 2d — What the first real two-player session found ✅ DONE

The first session with two people on one machine turned up four things no test had been
able to see, all of the same shape: something that only ever runs on the server, whose
RESULT nobody else was told about.

- **A teammate walked the map in a mid-air pose.** `CharacterBody3D.is_on_floor()` is
  only updated inside `move_and_slide()`, and a puppet never calls it — its position
  arrives over the wire — so on anyone else's avatar it is false forever.
  `PlayerAnimator.update_locomotion` checks it before anything else and plays the jump
  clip, returning before it ever reaches a gait. Attacks looked fine throughout, because
  `_net_play_action` drives the action layer and skips locomotion entirely. Fixed with a
  replicated `is_grounded` (and `is_blocking`, which had never travelled either).
- **Enemies slid down the lanes without animating.** `_update_visual_animation` picks
  walk-or-stand off `velocity`, and the enemy synchroniser carried `position`, `rotation`
  and `health` only. The comment claimed clients animate "from the replicated transform";
  the transform was replicated and the velocity the decision is made from was not.
- **A client could not visibly hurt anything.** Three holes behind one symptom: the health
  BAR is only updated from inside `take_damage`/`heal` (server-only) though `health`
  itself replicated; damage numbers were emitted from server-only code in five scripts;
  and `is_dying` never crossed, so an enemy stood at full health until the host freed it
  and it blinked out mid-stride. The damage had been landing the whole time.

`EnemyBase._update_puppet()` now owns all three of the client's jobs, and damage numbers
go through `NetFx.damage_number()` like every other cosmetic.

`tools/tests/net_effects.tscn` grew a section for each. The host drives an enemy through
spawn, damage and death one step at a time over RPC, and the client reports what it saw
at each; motion is compared against the host's own copy rather than a fixed number, since
whether an enemy happens to be walking depends on the navigation mesh. With the fixes
reverted the failures read `host 3.25, client 0.00` and `loco 'jump'` — the playtest
report, reproduced.

## Phase 3 — RunState becomes server-authoritative ✅ DONE

The economy was rebuilt since this plan was written, so this phase replaces the old
"mana drops and per-player pools" one entirely. There are no drops to claim and no
pools to divide — but there is now a singleton holding the whole run.

1. `RunState.on_enemy_killed()` runs **only on the server**. XP, levels and the mana
   pool are the server's.
2. `team_xp`, `team_level`, `mana_pool` and `enchantments` replicate to clients — a
   `MultiplayerSynchronizer` on the autoload, or explicit broadcasts on change.
3. `grant_skill_points()` becomes an RPC to every peer, so levels still land on
   everyone simultaneously.
4. Skill-point **spending** stays client-side and is simply mirrored to the server.
   It is co-op; validating a build against cheating buys nothing.
5. `PlayerRegistry.count()` already drives difficulty scaling and the Upkeep vote
   threshold, so both start working the moment peers exist.

**Ends at:** the team levels together and shares one mana pool across the network.

## Phase 4 — Upkeep over the network ✅ DONE

Entirely new work — the old plan had no vote to network.

1. `upkeep_started` / `upkeep_finished` become server broadcasts. Only the server may
   end Upkeep, because `upkeep_finished` is what starts the next wave.
2. Proposals, votes and withdrawals are RPCs. The **server** holds the proposal state
   and the mana reservations; clients render what it tells them.
3. Ready checks are per peer. `_all_ready()` currently returns `_local_ready` — it
   becomes a tally across connected peers, and `_vote_threshold()` already counts
   players correctly.
4. Purchases execute on the server: it spends the mana, spawns the myr, grants the
   points, applies the enchantment, and broadcasts the result to the log.
5. A disconnect mid-Upkeep must not deadlock a vote — the threshold counts *connected*
   peers, recomputed when someone drops.

**Ends at:** five players argue about Furnace of Rath and the majority wins.

## Phase 5 — Actually a five-player game — PARTLY DONE

1. ✅ **Wave size now scales with head count.** Enemy *damage* already did
   (`get_player_scaling_factor`), but wave *size* never had - five players met a
   solo-sized wave, shredded it without the crystal ever being threatened, and earned
   solo-sized income doing it. `get_wave_size_factor()` multiplies the wave's enemy
   budget: 1.45x at two players, 2.8x at five.
   **Still open:** the income curve in `docs/ECONOMY.md` was written for one player and
   needs a real playtest at five.
2. ✅ **A main menu in front of the game.** `res://scenes/ui/main_menu.tscn` is the
   startup scene: Host a game, Join a game, Play solo, Quit. Hosting opens a lobby with
   a per-peer ready check that the host cannot start without; joining opens a server
   browser whose Scan button broadcasts on UDP `27016` and lists the LAN hosts that
   answer, with a password prompt for the ones that need one. The map is loaded only
   once a choice is made, by the same call for one player as for five, so Play solo is
   still exactly the old startup path. The in-map F9 lobby stays for a session already
   under way.
3. Downed and revive already exist — surface them: teammate markers, a downed HUD, a
   respawn timer.
4. **Reconnect — done.** A host keeps advertising while a match runs and reports it as
   in progress with the number of free seats, so a dropped player can find the run
   again in the browser or press RECONNECT, which remembers the address for them. The
   seat is held by NAME for the rest of the match (peer ids change on reconnect, so
   nothing else about the returning player is the same), and the map spawns them back
   into it and pushes the crystal and the economy, which otherwise only travel when
   they change. A rejoining client loads the map BEFORE opening the connection: Godot
   pushes every already-spawned node at the instant a peer connects, and a spawn whose
   spawner is not in the tree yet is discarded rather than queued. Builds are spent
   client-side and the host never had a copy, so the returning client re-applies its
   own — which covers a dropped connection, but not a client that was closed. Losing
   the host drops the map back to the menu with the reconnect offer showing.
5. A ping or marker system. In a five-lane map, "help, blue lane" needs to be one
   keypress.

---

## The hard parts, honestly

| Risk | Why | Mitigation |
|---|---|---|
| **`player.gd` is 1500 lines** with 19 input polls and deep coupling to camera, HUD and mouse mode | Every one is a single-player assumption | Phase 0 does this *before* any networking, so failures are easy to diagnose |
| **Projectile pooling vs replication** | `ProjectilePool` recycles nodes; `MultiplayerSpawner` expects real spawn/despawn | Split cosmetic from authoritative rather than replicating the pool |
| **Navigation baking** | `main.gd` bakes the navmesh at runtime; enemies path server-side | Bake on the server only; clients never path |
| **Animation state is complex** | The `AnimationTree` one-shot, charge easing and combo windows are all local timing | Replicate *intent* (which action started, when) and let each client's `PlayerAnimator` run it — do not replicate bone poses |
| **63 SignalBus emit sites** | A global bus has no concept of "which peer" | Classify in Phase 0; only world events need to become RPCs |
| **The economy changed under this plan** | It was written for per-player mana drops; the game now has shared XP, personal skill points and one team mana pool spent by vote | Phase 3 and Phase 4 were rewritten against what exists. `RunState` and `UpkeepPanel` were deliberately built as singletons so they can take server authority |
| **Five-player balance is unknown territory** | The scaling factor has never run above 1 | Phase 4 is a real balancing pass, not a polish pass |

## What I would not do

- **Dedicated server.** Overkill for five-player co-op, and doubles the deployment work.
- **Full server authority over movement.** It buys anti-cheat nobody needs, and costs
  prediction and reconciliation code that would take longer than every other phase
  combined.
- **Replicating the animation tree.** Send the decision, not the pose.
- **Splitscreen.** Five viewports on one machine, on a project that already needed a
  graphics-options menu to run, is not the same feature.
