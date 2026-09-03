# Five-Player Multiplayer Plan

A phased plan for turning the game into five-player co-op. Each phase ends somewhere
playable — no phase leaves the game broken while the next one is built.

## Where the project actually stands

**There is no networking code at all** — no `multiplayer`, no `@rpc`, no peer setup,
nothing in `project.godot`. But the *gameplay* was already written for more than one
player, which is a far better starting point than it sounds:

| Already multi-player aware | Where |
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
2. Downed and revive already exist — surface them: teammate markers, a downed HUD, a
   respawn timer.
3. Reconnect, and graceful "host left" handling.
4. A ping or marker system. In a five-lane map, "help, blue lane" needs to be one
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
