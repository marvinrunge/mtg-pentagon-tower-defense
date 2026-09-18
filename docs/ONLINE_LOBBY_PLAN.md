# Online Lobbies — Firebase finds the game, WebRTC carries it

Phase 6 of `docs/MULTIPLAYER_PLAN.md`. The co-op game works over ENet on a local
network; this makes it work over the internet without renting a server to play on.

## The idea in one paragraph

Firebase is a **noticeboard and a post box**, never a game server. It lists who is
hosting, and it passes the four or five short messages two machines need in order to
find a route to each other. The moment they have one, the connection is **direct between
the players** and Firebase carries nothing else — no game traffic, no cost per player,
no latency added. The host is still authoritative and still plays; the topology is
exactly the one Phases 1–5 were built for.

```
       ┌──────────────┐  1. "I am hosting"          ┌──────────────┐
       │              │  2. "here is my offer"      │              │
       │   HOST       │ ◄────── Firebase RTDB ─────► │   CLIENT     │
       │  (peer 1)    │  3. "here is my answer"      │  (peer N)    │
       │              │  4. addresses (ICE)          │              │
       └──────┬───────┘                              └──────┬───────┘
              │                                             │
              └───────── 5. direct WebRTC, no relay ────────┘
                         (all game traffic, forever)
```

## Why this barely touches the netcode

`WebRTCMultiplayerPeer` is a `MultiplayerPeer` exactly like `ENetMultiplayerPeer`, and it
has a **server/client mode** rather than only a mesh — so the host is peer 1 and everyone
else talks to it and to nobody else, which is the topology `net.gd` already assumes.

Unchanged: every `@rpc`, every `MultiplayerSpawner`, every `MultiplayerSynchronizer`,
`NetFx`, `EffectNetSpawner`, the authority split, seats, the ready check, the Upkeep vote,
reconnect. What changes is **which object is assigned to `multiplayer.multiplayer_peer`**,
and nothing else.

## Why not the alternatives

| Approach | Why not |
|---|---|
| **UPnP + ENet + a public IP in the list** | Simpler, and it was the first plan. It fails outright behind CGNAT (most mobile and some fibre providers), needs a port forwarded when UPnP is off, and publishes every host's home IP address in a world-readable list. |
| **Firestore instead of the Realtime Database** | Firestore's live updates are gRPC only; over REST it can be polled and nothing else — and its free tier is priced per document read, which a refreshing lobby browser is very good at spending. |
| **Server-sent events instead of polling** | The RTDB stream answers with a 307 to a different host that `HTTPRequest` will not follow for a streaming body, and the free tier allows **100 simultaneous connections** — one held open per player browsing would cap the game at a hundred people looking at a menu. Polling holds nothing open and only runs while a list or a handshake is on screen. |
| **A relay / dedicated server** | The thing the whole design is avoiding. |

## What it costs

Nothing, on the Spark (free) tier, by a wide margin. A lobby record is ~200 bytes; a
handshake is a few kilobytes of SDP and candidates and then stops forever. The free tier
is 1 GB stored and 10 GB/month transferred. Game traffic never touches it at all.

## Files

| File | What it is |
|---|---|
| `scripts/online_config.gd` | Where the Firebase coordinates are read from. Absent ⇒ online play is hidden, not broken. |
| `scripts/firebase_rtdb.gd` | The Realtime Database over REST, plus anonymous sign-in and token refresh. |
| `scripts/net_online.gd` | Autoload `NetOnline`. The lobby directory, the signalling, and the WebRTC peers. |
| `scripts/net.gd` | Gains `host_online()`, `join_online()`, `begin_join_online()`. Everything else untouched. |
| `scripts/main_menu.gd` | A "List this game online" switch when hosting, a "Search online" switch when browsing. |

The browser rows from both sources are **the same dictionaries** — `NetOnline` answers
what `Net.found_servers()` answers, plus `online` and `lobby` — so one renderer draws a
LAN game and an online game, and the two lists cannot drift apart.

## Data model

```
lobbies/{lobbyId}
    name         string     what the browser shows
    host_uid     string     the anonymous uid that owns this entry
    players      int
    max          int
    free         int        seats left, held seats subtracted
    has_password bool       whether, never what
    in_progress  bool       a running match a dropped player can come back to
    version      int        PROTOCOL_VERSION; the browser hides mismatches
    created_at   timestamp  server-set
    heartbeat    timestamp  server-set, every 20s

tickets/{lobbyId}/{ticketId}
    client_uid   string
    peer_id      int        the id the client intends to use
    offer        string     SDP, written by the client
    answer       string     SDP, written by the host
    ice_client   array      candidates, appended by the client
    ice_host     array      candidates, appended by the host
    rejected     string     set by the host when the ticket cannot be served
```

**Tickets are a sibling of lobbies, not a child of one.** A RTDB read is deep: a browser
fetching `/lobbies` would otherwise download every in-flight SDP blob in the game along
with it.

**The password is not checked here.** It travels over the connection, in
`Net._submit_identity`, exactly as it does on the LAN — so there is one answer to "why
was I turned away" rather than two, and the password never reaches Firebase.

**Each ICE list has exactly one writer**, so each side publishes its whole list on every
flush rather than pushing entries one at a time: one request per poll no matter how many
candidates turned up, and nothing to race with.

## Security rules

Paste these into **Realtime Database → Rules**. A fresh database starts either wide open
(a 30-day test-mode timer) or locked; neither is what this wants.

```json
{
  "rules": {
    "lobbies": {
      ".read": "auth != null",
      "$lobby": {
        ".write": "auth != null && ((!data.exists() && newData.child('host_uid').val() === auth.uid) || (data.exists() && data.child('host_uid').val() === auth.uid) || (data.exists() && !newData.exists() && data.child('heartbeat').val() < (now - 150000)))",
        ".validate": "newData.hasChildren(['name','host_uid','players','max','version','heartbeat'])",
        "name": { ".validate": "newData.isString() && newData.val().length <= 40" },
        "host_uid": { ".validate": "newData.val() === auth.uid" },
        "players": { ".validate": "newData.isNumber()" },
        "max": { ".validate": "newData.isNumber() && newData.val() <= 5" },
        "version": { ".validate": "newData.isNumber()" },
        "$other": { ".validate": true }
      }
    },
    "tickets": {
      "$lobby": {
        ".read": "auth != null && root.child('lobbies').child($lobby).child('host_uid').val() === auth.uid",
        ".write": "auth != null && root.child('lobbies').child($lobby).child('host_uid').val() === auth.uid",
        "$ticket": {
          ".read": "auth != null && (data.child('client_uid').val() === auth.uid || root.child('lobbies').child($lobby).child('host_uid').val() === auth.uid)",
          ".write": "auth != null && ((!data.exists() && newData.child('client_uid').val() === auth.uid) || data.child('client_uid').val() === auth.uid || root.child('lobbies').child($lobby).child('host_uid').val() === auth.uid)",
          "$field": { ".validate": true }
        }
      }
    }
  }
}
```

What each clause is for:

- **A lobby is writable by its host and by nobody else.** The uid comes from anonymous
  sign-in and is cached in `user://online_auth.json`, so a host whose game crashed comes
  back as the *same* uid and can therefore still delete the entry it left behind.
- **A stale lobby is deletable by anyone** (`heartbeat` older than 150s, and only as a
  delete). Nobody owns the job of sweeping up, so whoever notices does it. A live lobby
  is never deletable this way, so it cannot be used to close somebody's game.
- **A ticket is readable by its client and by the host, and by nobody else.** The whole
  handshake for one join is private to the two machines doing it.
- **Only the host can list the tickets** of its own lobby. A client can reach its own
  ticket by key, and the keys are server-generated and unguessable.

Known and accepted: a client can overwrite fields in **its own** ticket, including the
host's answer. The blast radius is that its own join fails.

## What is still not solved

**Symmetric NAT on both ends.** STUN cannot punch through it; this needs TURN, which is a
relay, which costs bandwidth — the one thing this design is avoiding. Expect this to be a
minority of players. It fails cleanly: the handshake times out after 25 seconds and the
menu says so.

If it turns out to matter, `online_config.json` already takes TURN entries in
`ice_servers` — a `coturn` on a small VPS, or a paid ICE provider — and nothing else in
the code has to change.

## Phases

### Phase 6a — The directory and the handshake ✅ CODE WRITTEN, UNTESTED

Everything above. Not yet run against a real Firebase project (see **Before this can be
trusted**).

### Phase 6b — What a real two-machine session finds

Phase 2d is the precedent: the first session with real people on real machines found four
things no test could. Expect the same here. The candidates:

- A client whose handshake completes but whose identity RPC arrives before the host's
  data channels are all open.
- Reconnect into a running online match — the path is wired (`begin_join_online`) and has
  never been walked.
- A host that closes the game without `leave()` running (alt-F4), leaving the lobby up
  for up to 150 seconds.

### Phase 6c — Cross-process tests

`tools/tests/net_effects.gd` and `tools/tests/lan_reconnect.gd` drive two Godot processes
through a real session. Neither knows about the online transport yet, and
`--autohost` / `--autojoin` are LAN-only. Extending them means a scratch Firebase project
and a CI secret, which is why it is its own phase.

## Before this can be trusted

This code has **never been executed**. There is no Godot binary in the environment it was
written in, no Firebase project behind it, and no WebRTC extension installed. It compiles
in the author's head and nowhere else. Treat Phase 6a as a first draft to debug, not as a
working feature — the setup steps in the section below are the first half of that job.

---

# Setup — the parts that cannot be done from inside the repository

Five jobs. None of them is code, and nothing online works until all five are done.

## 1. The Firebase project

1. <https://console.firebase.google.com> → **Add project**. Google Analytics can be
   declined; it is not used.
2. **Build → Realtime Database → Create Database.** Pick a region close to the players
   (`europe-west1` for Europe). Start in **locked mode** — the rules above replace
   whatever it starts with.
3. **Realtime Database → Rules** → paste the JSON from *Security rules* → **Publish**.
4. **Build → Authentication → Get started → Sign-in method → Anonymous → Enable.**
   Missing this is the single most likely reason nothing works; the game reports it in
   as many words ("Anonymous sign-in is switched off in the Firebase console").
5. **Project settings → General → Your apps → Web app** (`</>`). Register one, and copy
   the `apiKey` and `databaseURL` out of the snippet it shows.

Stay on the **Spark (free)** plan. Nothing here needs Blaze — there are no Cloud
Functions, which is why stale lobbies are swept by the clients instead.

## 2. `online_config.json`

Copy `online_config.example.json` to `online_config.json` in the project root and fill in
the two values:

```json
{
  "api_key": "AIzaSy...",
  "database_url": "https://your-project-default-rtdb.europe-west1.firebasedatabase.app",
  "ice_servers": []
}
```

The URL shape differs by region — `...firebasedatabase.app` outside `us-central1`,
`https://your-project.firebaseio.com` inside it. Copy it from the console rather than
constructing it.

The file is **gitignored**. That is not because the API key is secret — it is not, it
ships in every build and can be read out of any of them, and what actually guards the
database is the rules. It is so that a fork does not write its lobbies into your database.
For a release build, either commit it deliberately or add it to the export.

## 3. The WebRTC extension

Godot ships the WebRTC *interface* in core and the *implementation* as a GDExtension, so
the classes exist in the editor either way and nothing warns you that it is missing. The
game probes for it at startup and hides the online switches when it is absent.

1. <https://github.com/godotengine/webrtc-native/releases> — take the release whose
   `compatibility_minimum` matches this project's Godot (4.7).
2. Extract so that `addons/webrtc/webrtc.gdextension` exists.
3. Restart the editor. `NetOnline.is_available()` answering true is the check;
   in practice, the two switches appearing in the menu is the same check.

If no build for 4.7 exists yet, this is the piece that blocks everything — it has to be
built from source against the matching `godot-cpp`, or the project has to sit on a Godot
version a release exists for. **Verify this before anything else**; the rest of the setup
is wasted if it turns out there is no usable binary.

## 4. Export

The `.gdextension` file carries its own platform libraries into an export, but only if
`addons/` is not excluded by the preset's filters. Check `export_presets.cfg` after
adding it, and confirm the exported build still shows the online switches — an export
that silently dropped the extension looks exactly like a build with no config.

## 5. Two real machines on two real networks

Two windows on one desk cannot test this. Both would sit behind the same NAT and would
connect through a local candidate, which is the one case that was never in doubt. It
needs two networks — a laptop on a phone hotspot is enough — and ideally one of them
behind a router that does not do UPnP, since that is the configuration the whole design
exists for.

What to watch, in order:

1. The host's lobby appears in the database under `lobbies/` (the console shows it live).
2. The client's ticket appears under `tickets/{lobbyId}/`, gains an `answer`, then both
   `ice_` lists fill.
3. The ticket is **deleted** — that is the host confirming the peer is connected.
4. The lobby's `players` count goes up.
5. Both `ice_` lists stop growing and the game plays. From here nothing should touch
   Firebase except the 20-second heartbeat.

If it stalls at 2, it is the rules or anonymous sign-in. If it stalls at 3 with both ICE
lists full, it is NAT — which is the TURN case, and the honest answer for now is that
those two networks cannot reach each other directly.

---

## Known gaps in what was written

Stated plainly because none of it has been run:

- **Nothing was executed.** No Godot binary was available. Syntax, the WebRTC signal
  signatures, and the exact shape of `WebRTCMultiplayerPeer.get_peers()` are written
  from the API as documented, not as observed.
- **The in-map F9 lobby (`scripts/lobby.gd`) is still LAN-only.** It hosts and joins by
  address. Deliberate — it is a debug panel for a session already under way — but it
  means "press F9 and host" does not list anything online.
- **`--autohost` / `--autojoin` are LAN-only**, so the existing cross-process tests do
  not cover any of this.
- **No rate limiting.** Anyone with the API key can create lobby entries. The rules cap
  what one entry can contain and who can change it, but not how many an attacker could
  make. Firebase App Check would be the answer and has no Godot client.
