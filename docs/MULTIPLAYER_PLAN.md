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

## Phase 0 — Make single-player multiplayer-shaped

**Still single-player when done. Nothing networked yet.** This is the whole refactor
risk in one phase, done while the game is easy to test.

1. **Extract input from `Player`.** There are **19 `Input.` calls** in `player.gd`.
   Replace them with a small `PlayerInput` object the player reads from. Locally it
   polls `Input`; for a remote player it is fed by replication. One seam, nineteen call
   sites, no behaviour change.
2. **Gate the singleton grabs.** `Player._ready()` sets `Input.mouse_mode` globally and
   `setup_camera()` calls `camera.make_current()`. Both must happen only for the local
   player.
3. **"The local player", not "the first player".** `hud.gd`, `skill_tree.gd` and
   `base_ui.gd` all call `get_first_node_in_group("player")`. Add
   `PlayerRegistry.local_player` and use it everywhere.
4. **Let `main.gd` spawn N players.** Currently hardcoded to one. Take a list of
   (peer, colour) and spawn from it — with a list of length 1 the game is unchanged.
5. **Split `SignalBus`.** There are **63 emit sites**. Sort them into two groups:
   *local/cosmetic* (damage numbers, shake, sound, HUD) which stay as they are, and
   *world events* (crystal damaged, enemy died, wave started) which will become
   server-driven. Just annotate them in this phase; do not move them yet.

**Test:** the game plays exactly as it does now, but `main.gd` could spawn two players
sharing a keyboard and neither would crash.

## Phase 1 — Two players, moving and fighting

**Playable co-op, incomplete world.**

1. Lobby scene: host / join by IP, colour pick, ready-up, start.
2. `MultiplayerSpawner` for players; `set_multiplayer_authority(peer_id)` on each.
3. `MultiplayerSynchronizer` on the player: position, rotation, velocity, and the
   animation state `PlayerAnimator` needs (current clip, action shot, charge progress).
4. Enemies stay server-simulated; replicate their transforms only. Clients see them
   move; only the host's hits register at first.
5. Melee hit RPC: client → server, server applies damage, health replicates back.

**Test:** two players run around the same map and kill things together.

## Phase 2 — The whole world replicates

1. Enemy spawn/despawn through `MultiplayerSpawner`; health and status via synchroniser.
2. `WaveManager` runs server-only; wave state broadcast to clients for the HUD.
3. Crystal health server-authoritative; `crystal_damaged` becomes a server → client
   broadcast rather than a free-for-all signal.
4. Projectiles: the **pool stays local for cosmetics**, but a projectile that deals
   damage is spawned by the server. Split `Projectile` into "visual" and "authoritative"
   rather than trying to replicate a pool.
5. Boss specials: server decides and broadcasts; each client spawns its own
   `AttackIndicator` locally from the event.
6. DoT zones (Rain of Ember, Fog, Wall of Souls) — server owns damage ticks, clients
   spawn the `EmberFx` visuals locally.

**Test:** a full wave, including a boss, plays identically for all clients.

## Phase 3 — Economy and progression

1. Mana drops spawn server-side; pickup is an RPC so two players cannot claim the same
   drop.
2. **Per-player mana pools, not the shared one.** With five players and personal skill
   trees, a shared pot means the fastest clicker spends everyone's mana. Keep a small
   shared "war chest" for crystal repair only, where cooperation is the point.
3. Skill tree is per-player and entirely client-side except the purchase, which is an
   RPC so the server can keep the authoritative build (needed for damage numbers).
4. Guild camps: server-owned, cleared cooperatively, reward the two adjacent players.

## Phase 4 — Make it a five-player game rather than a co-op single-player game

1. **Rebalance `get_player_scaling_factor`.** It exists but has never been tested past
   one player. Five players against current wave sizes will trivialise everything.
2. Colour claiming in the lobby, so each player owns a lane.
3. Downed/revive already exists — surface it: teammate markers, a downed HUD, a
   respawn timer.
4. Reconnect, host migration or graceful "host left" handling, spectate on death.
5. Voice/ping/marker system. In a five-lane map with one player per lane, "help, blue
   lane" needs to be one keypress.

---

## The hard parts, honestly

| Risk | Why | Mitigation |
|---|---|---|
| **`player.gd` is 1500 lines** with 19 input polls and deep coupling to camera, HUD and mouse mode | Every one is a single-player assumption | Phase 0 does this *before* any networking, so failures are easy to diagnose |
| **Projectile pooling vs replication** | `ProjectilePool` recycles nodes; `MultiplayerSpawner` expects real spawn/despawn | Split cosmetic from authoritative rather than replicating the pool |
| **Navigation baking** | `main.gd` bakes the navmesh at runtime; enemies path server-side | Bake on the server only; clients never path |
| **Animation state is complex** | The `AnimationTree` one-shot, charge easing and combo windows are all local timing | Replicate *intent* (which action started, when) and let each client's `PlayerAnimator` run it — do not replicate bone poses |
| **63 SignalBus emit sites** | A global bus has no concept of "which peer" | Classify in Phase 0; only world events need to become RPCs |
| **Five-player balance is unknown territory** | The scaling factor has never run above 1 | Phase 4 is a real balancing pass, not a polish pass |

## What I would not do

- **Dedicated server.** Overkill for five-player co-op, and doubles the deployment work.
- **Full server authority over movement.** It buys anti-cheat nobody needs, and costs
  prediction and reconciliation code that would take longer than every other phase
  combined.
- **Replicating the animation tree.** Send the decision, not the pose.
- **Splitscreen.** Five viewports on one machine, on a project that already needed a
  graphics-options menu to run, is not the same feature.
