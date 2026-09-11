extends Node
## Functional test: a client can SEE what it casts, and so can everybody else.
##
## Run with:  godot --headless --path . res://tools/tests/net_effects.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not happen.
##
## Cross-process, like lan_lobby.gd and lan_reconnect.gd, and for a stronger reason than
## either of them. The bug this guards against was invisible in every single-process test
## in the project, because in single-player `Net.is_server()` is true and `execute_spell`
## runs the effect locally exactly as it always did. It only appears when there is a real
## second peer whose casts take the OTHER branch:
##
##     if Net.is_active() and not Net.is_server():
##         _request_spell.rpc_id(1, spell_id, charge_pct)
##         return          <- and the client's own screen shows nothing
##
## So the client is the one that has to do the looking. It casts, watches its own scene,
## and reports what it saw; the host collects the report, adds what it can see from its
## own side, and prints the verdict. A test where the host cast and the host looked would
## pass with every one of these fixes reverted.

const PORT: int = 27018
const TIMEOUT_SECONDS: float = 150.0
const MAP_SCENE: String = "res://scenes/misc/main.tscn"
## Enough for a cast to reach the host, be resolved, and for the broadcast to come back.
## Generous because this shares a machine with a second full Godot instance.
const ROUND_TRIP: float = 1.2
const TEST_DAMAGE: float = 23.0
## The build the client buys, chosen so the host can be asked about it in three ways: the
## rank it resolves a spell at, the aura it can see, and the maximum health that aura
## changes. Sylvan Library multiplies max_hp, so the last one proves the host did not just
## STORE the build but ran _sync_auras over it.
const BUILT_SPELL: String = "blue_2"
const BUILT_RANK: int = 4
const BUILT_AURA: String = "aura_sylvan_library"
const BUILT_AURA_RANK: int = 3
## Long enough for the host to notice the drop and hold the seat. Standing in for the five
## minutes a real player spends on the menu - nothing in Net expires a reservation, so the
## length of the gap is not what the test is about.
const REJOIN_GAP: float = 2.0
## Where the test enemy is put: out on a lane, far enough from the crystal to have a walk
## to make and close enough to be on the baked navigation mesh.
const ENEMY_SPAWN: Vector3 = Vector3(0.0, 1.0, 30.0)
## How near a damage number has to appear to count as this enemy's. Waves are running
## during the test, so numbers from other fights are floating around the map.
const NUMBER_RADIUS: float = 8.0

var _is_client: bool = false
var _elapsed: float = 0.0
var _done: bool = false
var _started: bool = false
var _failures: Array[String] = []

## What the client saw, once it has finished looking.
var _client_report: Dictionary = {}
## What the client found when it came back from a drop.
var _rejoin_report: Dictionary = {}
## What the host could see of the client's first avatar, taken before it dropped.
var _host_view: Dictionary = {}
var _host_hp_before: float = -1.0
## The host's own answers to the loadout probe, to hold the client's up against.
var _host_loadout: Dictionary = {}
## Host side: the enemy the client is being shown. Held by reference rather than looked up,
## because dying removes it from the "enemies" group.
var _test_enemy: Node3D = null
## Client side: the name the host gave it. Names come from the spawner and match on both
## machines, which is what lets the client pick this one out of a map full of wave enemies.
var _test_enemy_name: String = ""


func _ready() -> void:
	if get_meta("survivor", false):
		return
	# Deferred: the root is still setting up its children on this frame, and add_child
	# into that is refused outright.
	_boot.call_deferred()


## This node has to outlive change_scene_to_file - the map replaces the current scene, and
## the test IS the current scene until it moves itself out of the way. Same trick
## charge_orb_shot.gd uses, with one added requirement: the name has to match on both
## sides, because it is the RPC address the two processes talk to each other over.
func _boot() -> void:
	_is_client = "--lan-client" in OS.get_cmdline_user_args()
	var survivor: Node = load("res://tools/tests/net_effects.gd").new()
	survivor.name = "NetEffectsProbe"
	survivor.set_meta("survivor", true)
	get_tree().root.add_child(survivor)
	survivor._is_client = _is_client
	survivor._begin()


func _begin() -> void:
	Net.match_started.connect(_on_match_started)
	if _is_client:
		# The host waits for everyone to be ready before it starts, so the client has to
		# say so - and it can only say so once the server's peer list has reached it.
		Net.peer_list_changed.connect(_on_client_peer_list_changed)
		if Net.join("127.0.0.1", PORT, "Client") != OK:
			get_tree().quit()
		return
	if Net.host(PORT, "Host", "Effect Test") != OK:
		_failures.append("the host could not open port %d" % PORT)
		_finish()
		return
	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.set_local_ready(true)
	var launched: Error = OS.create_instance([
		"--headless", "res://tools/tests/net_effects.tscn", "++", "--lan-client",
	])
	if launched < 0:
		_failures.append("could not launch the client process")
		_finish()


func _on_client_peer_list_changed(_peers: Dictionary) -> void:
	if Net.peers.has(Net.local_id()) and not Net.is_ready(Net.local_id()):
		Net.set_local_ready(true)


func _process(delta: float) -> void:
	if _done or not get_meta("survivor", false):
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		if _is_client:
			_done = true
			get_tree().quit()
			return
		_failures.append("timed out after %.0fs - the client never reported" % TIMEOUT_SECONDS)
		_finish()


func _on_peer_list_changed(_peers: Dictionary) -> void:
	if _started or Net.peers.size() < 2 or not Net.all_ready():
		return
	_started = true
	Net.start_match()


## Both sides load the map here, exactly as MainMenu does.
func _on_match_started() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
	_run.call_deferred()


## Waits for the map to finish building itself. The navigation bake is deferred and the
## avatars are spawned two physics frames after it, so there is no single frame at which
## the world is known to be standing - it has to be watched for.
func _await_world() -> bool:
	var waited: float = 0.0
	while waited < 40.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var scene: Node = get_tree().current_scene
		if scene == null or scene.get_node_or_null("Effects") == null:
			continue
		if PlayerRegistry.get_local() == null:
			continue
		# BOTH avatars, not just ours: a cast sent before the host has built this peer's
		# player has nothing on the far end to run it.
		if PlayerRegistry.count() >= 2:
			return true
	return false


func _run() -> void:
	if not await _await_world():
		if _is_client:
			get_tree().quit()
			return
		_failures.append("the map never finished building on the host")
		_finish()
		return
	if _is_client:
		await _run_client_checks()
	else:
		await _run_host_side()


# --- the client: does it see its own magic? -----------------------------------

func _run_client_checks() -> void:
	var player: Node3D = PlayerRegistry.get_local()
	var scene: Node = get_tree().current_scene
	var effects: Node = scene.get_node_or_null("Effects")
	var report: Dictionary = {}

	# A real tree, bought the way the skill tree buys it. Everything below is then cast
	# with it, which is the point: the host resolves a client's spell and has to resolve it
	# against THIS, not against the empty build a freshly spawned avatar starts with.
	player.chosen_color_path = "blue"
	for rank: int in BUILT_RANK:
		player.grant_spell_rank(BUILT_SPELL)
	for rank: int in BUILT_AURA_RANK:
		player.grant_aura_rank(BUILT_AURA)
	await _wait(ROUND_TRIP)

	# 1. One-shot cosmetics. Frost Breath lays a ring and a ground decal, both of which
	#    NetFx places onto the scene root - so the scene simply has more in it than it
	#    did. Counting children rather than naming node types on purpose: what is being
	#    tested is that ANY of it arrived, and the shapes are SpellFx's business.
	var children_before: int = scene.get_child_count()
	var shaken: Array[bool] = [false]
	var on_shake: Callable = func(_s: float, _d: float) -> void: shaken[0] = true
	SignalBus.camera_shake_requested.connect(on_shake)
	player.execute_spell("blue_2")
	await _wait(ROUND_TRIP)
	SignalBus.camera_shake_requested.disconnect(on_shake)
	report["cosmetics"] = scene.get_child_count() > children_before
	report["cosmetics_detail"] = "%d -> %d children" % [children_before, scene.get_child_count()]
	report["shake"] = shaken[0]

	# 2. A persistent object. The wall has collision and stops what walks into it, so a
	#    client that cannot see it is a client walking its team into an invisible barrier.
	player.execute_spell("blue_4")
	await _wait(ROUND_TRIP)
	report["wall"] = _has_child_named(effects, "WallOfFrost")

	# 3. ...and one placed somewhere other than at the caster.
	player.execute_spell("green_3")
	await _wait(ROUND_TRIP)
	report["zone"] = _has_child_named(effects, "DoTZone") or _has_script_named(effects, "DoTZone")

	# 4. A projectile. Fired by the host, drawn by everyone.
	player.execute_spell("red_1", 1.0)
	await _wait(ROUND_TRIP)
	var flying: int = 0
	for proj: Node in ProjectilePool.pool:
		if proj.active:
			flying += 1
	report["projectile"] = flying > 0
	report["projectile_detail"] = "%d in the air" % flying

	# 5. The loadout bar, which a joining player reported being unable to put anything on.
	#    Bought and bound through the same two calls the skill tree makes, so a pass here
	#    puts the fault in the UI above them rather than in the player itself.
	var slot: int = Player.QUICK_SLOT_COUNT - 1
	player.grant_spell_rank("blue_1")
	report["owns"] = player.is_spell_owned("blue_1")
	report["points"] = player.skill_points
	report["bind"] = player.assign_quick_slot(slot, "blue_1")
	report["bound"] = String(player.quick_slots[slot])

	#    ...and the same thing again one layer up, through the SkillTree's own buy and
	#    bind calls. A pass at the player level with a failure here puts the fault in the
	#    UI; a pass at both says the model and the UI are fine and the problem is in
	#    getting input to them at all.
	var probe: Dictionary = await _loadout_probe()
	for key: String in probe:
		report[key] = probe[key]

	# 6. The TEAMMATE's body. A puppet never calls move_and_slide, so `is_on_floor()` on
	#    somebody else's avatar is false forever - and PlayerAnimator checks exactly that
	#    before anything else and plays the jump clip when it is false. The host is stood
	#    still on the ground; anything but an idle here is the bug a playtest found, where
	#    a teammate walked the whole map in a mid-air pose while their attacks, which come
	#    through _net_play_action and skip locomotion entirely, looked perfectly normal.
	var mate: Node3D = _other_player()
	report["mate"] = mate != null
	report["mate_grounded"] = mate.is_grounded if mate != null else false
	report["mate_loco"] = mate.animator._current_loco if mate != null else "<no mate>"

	# 7. Health authored by the host (it damaged us before we started casting). Without
	#    the vitals synchronizer a client's own bar sits at full while the host counts it
	#    down, and the first the player knows of it is being downed.
	report["health"] = player.hp < player.max_hp
	report["health_detail"] = "%.0f/%.0f" % [player.hp, player.max_hp]

	_client_result.rpc_id(1, report)
	await _wait(0.5)
	await _run_enemy_checks()
	await _run_cast_and_death_checks()
	await _run_rejoin_check()
	_done = true
	get_tree().quit()


## Two things a playtest found that the checks above still could not see.
##
## The CAST ANIMATION of somebody else. Only `_begin_action` broadcast what it started, so
## melee replicated and every spell did not - the one that got noticed was Fire Cone,
## because a channel holds its pose for seconds while the short casts were simply missed.
##
## And DYING. `is_downed` was set inside `die()`, which is reached on the server because
## that is where enemies think, and it crossed to nobody: the host had the player face
## down while their own screen let them carry on at zero health.
func _run_cast_and_death_checks() -> void:
	var mate: Node3D = _other_player()
	if mate == null:
		_client_cast_seen.rpc_id(1, {"mate": false})
		return

	_host_cast.rpc_id(1)
	# Inside the cast's own duration: an action that has already finished is
	# indistinguishable from one that never arrived.
	await _wait(0.35)
	_client_cast_seen.rpc_id(1, {
		"mate": true,
		"acting": mate.animator._action_timer > 0.0,
		"timer": mate.animator._action_timer,
	})

	# --- Fire Dash, whose trail is laid by the CASTER rather than by the host ----
	var dasher: Node3D = PlayerRegistry.get_local()
	dasher.grant_spell_rank("red_2")
	dasher.spell_cooldown_timers.erase("red_2")
	var patches_before: int = _count_fire_patches()
	# The real entry point: _begin_cast is what runs cast_red_fire_dash, and the trail is
	# then dropped frame by frame out of _physics_process while the dash carries them.
	dasher._begin_cast("red_2", 1.0)
	await _wait(ROUND_TRIP + 0.6)
	_client_dash_seen.rpc_id(1, {
		"patches": _count_fire_patches() - patches_before,
	})
	await _wait(0.3)

	# --- Giant Growth, which the caster could not see on themselves ---------
	var me_first: Node3D = PlayerRegistry.get_local()
	var before_scale: float = me_first.scale.x
	me_first.grant_spell_rank("green_2")
	me_first.spell_cooldown_timers.erase("green_2")
	me_first.execute_spell("green_2", 1.0)
	# The round trip, plus the 0.25s the growth tween takes.
	await _wait(ROUND_TRIP + 0.4)
	_client_giant_seen.rpc_id(1, {
		"scale": me_first.scale.x,
		"before": before_scale,
		"mult": me_first._giant_scale_mult,
		"camera_world_scale": me_first.scale.x * me_first.camera_pivot.scale.x,
	})

	# --- and our own death, which the host decides --------------------------
	var me: Node3D = PlayerRegistry.get_local()
	_host_kill_client.rpc_id(1)
	await _wait(ROUND_TRIP)
	_client_death_seen.rpc_id(1, {
		"downed": me.is_downed,
		"hp": me.hp,
		"timer": me.down_timer,
	})
	await _wait(0.5)


@rpc("any_peer", "call_remote", "reliable")
func _host_revive_client() -> void:
	if not Net.is_server():
		return
	var them: Node3D = _client_avatar()
	if them != null and them.is_downed:
		them.revive()


@rpc("any_peer", "call_remote", "reliable")
func _host_cast() -> void:
	if not Net.is_server():
		return
	var me: Node3D = PlayerRegistry.get_local()
	if me == null:
		return
	me.grant_spell_rank("blue_2")
	me.spell_cooldown_timers.erase("blue_2")
	me._begin_cast("blue_2", 1.0)


@rpc("any_peer", "call_remote", "reliable")
func _host_kill_client() -> void:
	if not Net.is_server():
		return
	var them: Node3D = _client_avatar()
	if them != null:
		them.take_damage(them.hp + them.total_shield() + 1000.0, null, false)


@rpc("any_peer", "call_remote", "reliable")
func _client_cast_seen(view: Dictionary) -> void:
	if not Net.is_server():
		return
	print("WHAT THE CLIENT SEES THE HOST DOING")
	_check("it has the host's avatar to watch", view.get("mate", false))
	# The reported symptom, and every other spell animation with it.
	_check("the host's cast animation plays there", view.get("acting", false),
		"action timer %.2f" % float(view.get("timer", 0.0)))


## Burning ground from a Fire Dash, on this machine. Counted by type rather than held by
## reference because the dash lays a line of them, not one.
func _count_fire_patches() -> int:
	var found: int = 0
	var effects: Node = _effects_root()
	if effects == null:
		return 0
	for child: Node in effects.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == "DoTZone" 				and String(child.zone_type) == "fire_patch":
			found += 1
	return found


@rpc("any_peer", "call_remote", "reliable")
func _client_dash_seen(view: Dictionary) -> void:
	if not Net.is_server():
		return
	print("WHAT A CLIENT'S FIRE DASH LEAVES BEHIND")
	# The dash runs on the caster for responsiveness, so its trail is asked for from
	# there - and `request_effect` used to refuse a client outright, leaving no fire on
	# any screen and nothing burning what the dash passed over.
	_check("its trail burns on its own screen", int(view.get("patches", 0)) > 0,
		"%s patches" % view.get("patches"))
	_check("...and on the host's", _count_fire_patches() > 0,
		"%d patches" % _count_fire_patches())


@rpc("any_peer", "call_remote", "reliable")
func _client_giant_seen(view: Dictionary) -> void:
	if not Net.is_server():
		return
	# The spell resolves HERE, so the size it produces has to travel back before the
	# caster can see their own body change. Measured on the client's own avatar because
	# that is the screen the growth was invisible on.
	_check("Giant Growth makes it bigger on its own screen",
		float(view.get("scale", 0.0)) > float(view.get("before", 1.0)) * 1.05,
		"%.2f -> %.2f (mult %.2f)" % [view.get("before", 0.0), view.get("scale", 0.0), view.get("mult", 0.0)])
	# ...and the host's copy has to agree, or the melee multiplier keyed off it is
	# measuring a different creature from the one on screen.
	var them: Node3D = _client_avatar()
	# ...and the caster can actually SEE it. The camera rig hangs off the player node, so
	# scaling the body scaled the spring arm too and the character stayed exactly as big
	# on its own screen as it had been. The pivot's world scale has to come back to 1.
	_check("the growth is visible through the caster's own camera",
		is_equal_approx(float(view.get("camera_world_scale", 0.0)), 1.0),
		"pivot world scale %.2f" % float(view.get("camera_world_scale", 0.0)))
	_check("...and the host's copy is the same size",
		them != null and them.scale.x > 1.05, "%.2f" % [them.scale.x if them != null else -1.0])


@rpc("any_peer", "call_remote", "reliable")
func _client_death_seen(view: Dictionary) -> void:
	if not Net.is_server():
		return
	_check("being killed by the host puts it down on its own screen",
		view.get("downed", false), "hp %s" % view.get("hp"))
	_check("...with a revive window it can see run out",
		float(view.get("timer", 0.0)) > 0.0, "%.1fs" % float(view.get("timer", 0.0)))


## What a client can see of an enemy: that it walks, that it can be hurt, that it dies.
##
## Everything an enemy does happens on the server - its AI, its damage, its death - and
## for a long time none of the RESULTS reached anyone else. A joining player reported
## being unable to hurt anything; the hits were landing perfectly well on the host, and
## the client was watching a motionless body with a full health bar that eventually
## blinked out of existence. Three separate holes behind one symptom, so three checks.
##
## Driven from this end, one step at a time, because the two processes have no other way
## to agree on when the enemy is supposed to be walking and when it is supposed to be
## dead. The host compares each snapshot against its OWN copy as it arrives, while that
## copy is still in the matching state.
func _run_enemy_checks() -> void:
	_host_spawn_enemy.rpc_id(1)
	# Long enough to be spawned, pathed, and actually under way.
	await _wait(3.0)
	var enemy: Node3D = _find_test_enemy()
	if enemy == null:
		_client_enemy_walking.rpc_id(1, {"found": false})
		return

	_client_enemy_walking.rpc_id(1, {
		"found": true,
		"speed": Vector2(enemy.velocity.x, enemy.velocity.z).length(),
		"anim": enemy.visual_anim_player.current_animation if enemy.visual_anim_player != null else "",
		"playing": enemy.visual_anim_player.is_playing() if enemy.visual_anim_player != null else false,
	})

	# --- hurt it, and watch for the three things a hit should produce ---------
	var numbers: Array[int] = [0]
	var here: Vector3 = enemy.global_position
	var on_number: Callable = func(at: Vector3, _amount: float, _tint: Color, _label: String) -> void:
		if at.distance_to(here) < NUMBER_RADIUS:
			numbers[0] += 1
	SignalBus.damage_number_requested.connect(on_number)
	_host_hurt_enemy.rpc_id(1)
	await _wait(ROUND_TRIP)
	SignalBus.damage_number_requested.disconnect(on_number)
	_client_enemy_hurt.rpc_id(1, {
		"health": enemy.health,
		"bar": enemy.health_bar.health_ratio if enemy.health_bar != null else -1.0,
		"numbers": numbers[0],
	})

	# --- and kill it ---------------------------------------------------------
	_host_kill_enemy.rpc_id(1)
	await _wait(ROUND_TRIP)
	_client_enemy_dead.rpc_id(1, {
		"valid": is_instance_valid(enemy),
		"dying": enemy.is_dying if is_instance_valid(enemy) else false,
		"anim": enemy.visual_anim_player.current_animation if is_instance_valid(enemy) and enemy.visual_anim_player != null else "",
	})
	await _wait(0.5)


## The host's enemy, on this machine, by the name the spawner gave it on both.
func _find_test_enemy() -> Node3D:
	if _test_enemy_name == "":
		return null
	var scene: Node = get_tree().current_scene
	var enemies: Node = scene.get_node_or_null("Enemies") if scene != null else null
	return enemies.get_node_or_null(_test_enemy_name) as Node3D if enemies != null else null


# --- the host end of that conversation ---------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _host_spawn_enemy() -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_test_enemy = get_tree().current_scene.request_enemy({
		"position": ENEMY_SPAWN, "color": "Red", "type": "Melee", "elite": "",
	})
	_name_test_enemy.rpc_id(sender, _test_enemy.name if _test_enemy != null else "")


@rpc("authority", "call_remote", "reliable")
func _name_test_enemy(enemy_name: String) -> void:
	_test_enemy_name = enemy_name


@rpc("any_peer", "call_remote", "reliable")
func _host_hurt_enemy() -> void:
	if not Net.is_server() or not is_instance_valid(_test_enemy):
		return
	# Half of it, so the bar has somewhere to move to that is neither full nor empty.
	_test_enemy.take_damage(_test_enemy.health * 0.5, null, false)


@rpc("any_peer", "call_remote", "reliable")
func _host_kill_enemy() -> void:
	if not Net.is_server() or not is_instance_valid(_test_enemy):
		return
	_test_enemy.take_damage(_test_enemy.health + 1000.0, null, false)


@rpc("any_peer", "call_remote", "reliable")
func _client_enemy_walking(view: Dictionary) -> void:
	if not Net.is_server():
		return
	print("WHAT THE CLIENT SEES OF AN ENEMY")
	_check("it has the enemy at all", view.get("found", false))
	if not view.get("found", false):
		return
	# Compared against the host's OWN copy rather than against a fixed number: whether an
	# enemy happens to be walking at this instant depends on the navigation mesh and where
	# the wave put it. What must be true is that both machines agree.
	var mine: float = Vector2(_test_enemy.velocity.x, _test_enemy.velocity.z).length() if is_instance_valid(_test_enemy) else 0.0
	if mine > 0.01:
		_check("its motion reached the client", float(view.get("speed", 0.0)) > 0.01,
			"host %.2f, client %.2f" % [mine, view.get("speed", 0.0)])
		# The one the player actually notices: an enemy sliding down the lane in a
		# T-pose, or frozen on the first frame of its walk.
		_check("it is playing its walk there",
			String(view.get("anim", "")) == "walk" and bool(view.get("playing", false)),
			"'%s' playing=%s" % [view.get("anim"), view.get("playing")])
	else:
		print("       (the host's own copy is not moving - motion not judged)")


@rpc("any_peer", "call_remote", "reliable")
func _client_enemy_hurt(view: Dictionary) -> void:
	if not Net.is_server():
		return
	_check("the damage reached the client's copy",
		float(view.get("health", -1.0)) < float(_test_enemy.enemy_data.health) if is_instance_valid(_test_enemy) else false,
		"%s" % view.get("health"))
	# `health` replicated all along; set_health was only ever called from take_damage,
	# which runs here. So the number fell and the bar above it did not move.
	_check("its health BAR moved there",
		float(view.get("bar", -1.0)) > 0.0 and float(view.get("bar", -1.0)) < 1.0,
		"ratio %s" % view.get("bar"))
	_check("a damage number appeared there", int(view.get("numbers", 0)) > 0,
		"%s numbers" % view.get("numbers"))


@rpc("any_peer", "call_remote", "reliable")
func _client_enemy_dead(view: Dictionary) -> void:
	if not Net.is_server():
		return
	_check("the death reached the client", bool(view.get("dying", false)))
	_check("it plays the death clip there rather than vanishing",
		String(view.get("anim", "")) == "death", "'%s'" % view.get("anim"))


## Drop out, come back, and see whether the tree came back too.
##
## The sequence MainController and MainMenu perform between them when a connection is
## lost and RECONNECT is pressed: the build is saved off the avatar that is about to be
## destroyed, the peer goes away, and the map is reloaded with a pending join that
## `spawn_entities` completes once it is standing.
##
## This is here rather than in lan_reconnect.gd because that test never loads the map,
## and with no map there are no avatars and so no build to lose. The failure being
## guarded against needs both: a real second peer AND a real world for it to come back
## into.
func _run_rejoin_check() -> void:
	var before: Node3D = PlayerRegistry.get_local()
	# Back on its feet before the drop: the checks below are about the BUILD surviving,
	# and a corpse would confuse what they measure.
	_host_revive_client.rpc_id(1)
	await _wait(ROUND_TRIP)
	var wanted_rank: int = before.get_spell_rank(BUILT_SPELL)
	var wanted_aura: int = before.get_aura_rank(BUILT_AURA)
	var wanted_points: int = before.skill_points
	# A passive, which export_build did not carry - so the points spent on it were counted
	# as spent and the ranks they bought were gone.
	before.skill_points += 4
	before.grant_passive_rank("vigilance")
	before.grant_passive_rank("vigilance")
	var wanted_passive: int = before.get_passive_rank("vigilance")

	PlayerRegistry.save_local_build()
	var details: Dictionary = Net.last_join.duplicate()
	Net.leave()
	await _wait(REJOIN_GAP)
	Net.begin_join(
		String(details["address"]), int(details["port"]),
		String(details["name"]), String(details["password"])
	)
	# The map completes the join itself, once it is built - the order that keeps a spawn
	# from arriving before there is a spawner to receive it.
	get_tree().change_scene_to_file(MAP_SCENE)
	if not await _await_world():
		_rejoin_result.rpc_id(1, {"returned": false})
		return
	await _wait(ROUND_TRIP)

	var after: Node3D = PlayerRegistry.get_local()
	_rejoin_result.rpc_id(1, {
		"returned": after != null,
		"rank": after.get_spell_rank(BUILT_SPELL) if after != null else -1,
		"wanted_rank": wanted_rank,
		"aura": after.get_aura_rank(BUILT_AURA) if after != null else -1,
		"wanted_aura": wanted_aura,
		"points": after.skill_points if after != null else -1,
		"wanted_points": wanted_points,
		"passive": after.get_passive_rank("vigilance") if after != null else -1,
		"wanted_passive": wanted_passive,
	})
	await _wait(0.5)


## Buying a skill and putting it on the bar, three ways, on whichever machine calls it.
##
## The three are deliberately layered, because a playtester reported the bar not taking
## anything on the client and the first two layers turned out to be fine:
##
##   1. `Player.assign_quick_slot` - the model.
##   2. `SkillTree._bind_hovered_to_slot` - the UI function the key is supposed to reach.
##   3. a REAL InputEventKey pushed through the viewport - which is the only one of the
##      three that exercises _input ordering, `set_input_as_handled`, and the fact that
##      `Player._unhandled_input` wants the number keys too. Nothing else in this project
##      tests input delivery at all, and it is the one part a headless run can still do
##      honestly: push_input goes through the same pipeline a keyboard does.
func _loadout_probe() -> Dictionary:
	var out: Dictionary = {}
	var player: Node3D = PlayerRegistry.get_local()
	var tree: Node = get_tree().current_scene.get_node_or_null("SkillTree")
	out["tree"] = tree != null
	if tree == null or player == null:
		return out

	player.skill_points = 40
	# Branch 0 is the colour's AFFINITY and branch 1 its first spell, the order
	# skill_purchase.gd buys them in: a rank-0 spell is unreachable until something joined
	# to it is owned, and the affinity is what opens every colour.
	var affinity: Dictionary = tree._find_record("blue", 0)
	var spell: Dictionary = tree._find_record("blue", 1)
	if affinity.is_empty() or spell.is_empty():
		out["record"] = false
		return out
	out["record"] = true

	tree._on_node_pressed("blue", 0, affinity["info"])
	var node_id: String = String(spell["info"]["id"])
	tree._on_node_pressed("blue", 1, spell["info"])
	out["ui_bought"] = player.get_spell_rank(node_id) > 0

	# Cleared before each attempt: buying a spell drops it into the first free slot on its
	# own, so a bind that did nothing would otherwise look exactly like one that worked.
	player.assign_quick_slot(2, "")
	tree._hovered_record = spell
	tree._bind_hovered_to_slot(2)
	out["ui_bound"] = String(player.quick_slots[2]) == node_id

	# ...and now the same thing by pressing the key. The tree has to be OPEN, because its
	# _input returns early when it is not - which is also the first thing to suspect.
	player.assign_quick_slot(2, "")
	tree.visible = true
	tree._hovered_record = spell
	var press := InputEventKey.new()
	press.keycode = KEY_3          # KEY_1 + 2, the third slot
	press.physical_keycode = KEY_3
	press.pressed = true
	get_viewport().push_input(press)
	await get_tree().process_frame
	out["key_bound"] = String(player.quick_slots[2]) == node_id
	out["key_detail"] = "'%s' -> slot2 '%s'" % [node_id, player.quick_slots[2]]
	tree.visible = false
	return out


## The one avatar on this machine that is not ours.
func _other_player() -> Node3D:
	for player: Node3D in PlayerRegistry.players:
		if is_instance_valid(player) and player != PlayerRegistry.get_local():
			return player
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _effects_root() -> Node:
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null("Effects") if scene != null else null


func _has_child_named(parent: Node, prefix: String) -> bool:
	if parent == null:
		return false
	for child: Node in parent.get_children():
		if child.name.begins_with(prefix):
			return true
	return false


func _has_script_named(parent: Node, type: String) -> bool:
	if parent == null:
		return false
	for child: Node in parent.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == type:
			return true
	return false


# --- the host: it hits the client, then judges the report ---------------------

func _run_host_side() -> void:
	# Damage authored where damage is always authored. The client is asked about its own
	# hp at the end of its run, by which point this has had every chance to reach it.
	var them: Node3D = _client_avatar()
	if them == null:
		_failures.append("the host never built an avatar for the client")
		_finish()
		return
	_host_hp_before = them.hp
	them.take_damage(TEST_DAMAGE, null, false)
	# The same loadout probe the client runs, for comparison. A check that fails on both
	# machines is a broken check; one that fails only on the client is the reported bug.
	_host_loadout = await _loadout_probe()


func _client_avatar() -> Node3D:
	for player: Node3D in PlayerRegistry.players:
		if is_instance_valid(player) and player.get_multiplayer_authority() != 1:
			return player
	return null


@rpc("any_peer", "call_remote", "reliable")
func _client_result(report: Dictionary) -> void:
	if not Net.is_server() or _done:
		return
	_client_report = report
	# Read NOW, not in _finish(). The client drops immediately after sending this and the
	# avatar these are about is destroyed with the connection; by the time the verdict is
	# printed, _client_avatar() answers with the replacement that came back.
	var them: Node3D = _client_avatar()
	_host_view = {
		"wall": _has_child_named(_effects_root(), "WallOfFrost"),
		"hp": them.hp if them != null else -1.0,
		"rank": them.get_spell_rank(BUILT_SPELL) if them != null else -1,
		"aura": them.get_aura_rank(BUILT_AURA) if them != null else -1,
		"max_hp": them.max_hp if them != null else -1.0,
	}


@rpc("any_peer", "call_remote", "reliable")
func _rejoin_result(report: Dictionary) -> void:
	if not Net.is_server() or _done:
		return
	_rejoin_report = report
	_finish()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _finish() -> void:
	_done = true
	if not _client_report.is_empty():
		print("WHAT THE CLIENT SAW OF ITS OWN CASTS")
		_check("its one-shot visuals appeared", _client_report.get("cosmetics", false),
			String(_client_report.get("cosmetics_detail", "")))
		_check("its camera was shaken", _client_report.get("shake", false))
		_check("its wall was standing there", _client_report.get("wall", false))
		_check("its zone was standing there", _client_report.get("zone", false))
		_check("its fireball was in the air", _client_report.get("projectile", false),
			String(_client_report.get("projectile_detail", "")))
		_check("its health matched the host's", _client_report.get("health", false),
			String(_client_report.get("health_detail", "")))
		_check("it owns a spell it bought", _client_report.get("owns", false),
			"points %s" % _client_report.get("points"))
		_check("it can put that spell on its bar", _client_report.get("bind", false),
			"slot holds '%s'" % _client_report.get("bound"))
		_check("its skill tree exists", _client_report.get("tree", false))
		_check("the tree's own buy call works there", _client_report.get("ui_bought", false))
		_check("the tree's own bind call works there", _client_report.get("ui_bound", false))
		# The reported bug, if it is here at all. Printed alongside the host's own answer
		# so the two can be told apart at a glance.
		print("       host key-bind=%s  client key-bind=%s" % [
			_host_loadout.get("key_bound"), _client_report.get("key_bound")])
		_check("a number key binds on the host", _host_loadout.get("key_bound", false),
			String(_host_loadout.get("key_detail", "")))
		_check("a number key binds on the client", _client_report.get("key_bound", false),
			String(_client_report.get("key_detail", "")))
		_check("it has the host's avatar", _client_report.get("mate", false))
		_check("the host is standing on the ground there",
			_client_report.get("mate_grounded", false))
		_check("the host is not stuck mid-jump there",
			String(_client_report.get("mate_loco", "")) != PlayerAnimator.JUMP_CLIP,
			"loco '%s'" % _client_report.get("mate_loco"))

		print("WHAT THE HOST SEES OF THE CLIENT")
		# The other half of the same claim: the objects are on BOTH machines, not moved
		# from one to the other.
		_check("the client's wall reached the host", _host_view.get("wall", false))
		_check("the host's own copy took the damage",
			float(_host_view.get("hp", -1.0)) < _host_hp_before,
			"%.0f -> %s" % [_host_hp_before, _host_view.get("hp")])

		print("WHAT THE HOST KNOWS OF THE CLIENT'S TREE")
		# The host is where a client's spell is RESOLVED. Without the build it resolves
		# against nothing: rank 1, no auras, no affinity - so a maxed tree cast rank-1
		# spells with nothing behind them, on every screen including its owner's.
		_check("it resolves their spell at the rank they bought",
			int(_host_view.get("rank", -1)) == BUILT_RANK,
			"rank %s, wanted %d" % [_host_view.get("rank"), BUILT_RANK])
		_check("it knows about their aura",
			int(_host_view.get("aura", -1)) == BUILT_AURA_RANK,
			"rank %s, wanted %d" % [_host_view.get("aura"), BUILT_AURA_RANK])
		# ...and applied it, rather than merely filing it. Sylvan Library raises maximum
		# health, so this is _sync_auras having run on the host's copy of them.
		_check("it applied the aura to their maximum health",
			float(_host_view.get("max_hp", -1.0)) > GameSettings.player_max_hp,
			"%s vs a base %.0f" % [_host_view.get("max_hp"), GameSettings.player_max_hp])

	if not _rejoin_report.is_empty():
		print("WHAT THE CLIENT KEPT ACROSS A DROP")
		_check("it got back into the running match", _rejoin_report.get("returned", false))
		# The host holds a seat for a dropped player for the rest of the match and pushes
		# every OTHER player's build to whoever arrives. Pushing them their own would hand
		# back the empty avatar the host had just spawned and erase the tree they came
		# back for - silently, and with no way to get it back.
		_check("its spell ranks came back with it",
			_rejoin_report.get("rank", -1) == _rejoin_report.get("wanted_rank", -2),
			"rank %s, had %s" % [_rejoin_report.get("rank"), _rejoin_report.get("wanted_rank")])
		_check("its auras came back with it",
			_rejoin_report.get("aura", -1) == _rejoin_report.get("wanted_aura", -2),
			"rank %s, had %s" % [_rejoin_report.get("aura"), _rejoin_report.get("wanted_aura")])
		# Not "the same number it left with" any more: a player who was away while the team
		# levelled is owed those points, and RunState.points_awarded is what they are
		# settled against. So the floor is what they had, and more is correct.
		_check("its unspent skill points came back with it",
			int(_rejoin_report.get("points", -1)) >= int(_rejoin_report.get("wanted_points", 999)),
			"%s, had %s" % [_rejoin_report.get("points"), _rejoin_report.get("wanted_points")])
		_check("its passive ranks came back with it",
			int(_rejoin_report.get("passive", -1)) == int(_rejoin_report.get("wanted_passive", -2)),
			"rank %s, had %s" % [_rejoin_report.get("passive"), _rejoin_report.get("wanted_passive")])
		# The host has to learn it a second time. The avatar it spawned for the returning
		# player starts empty, and only the client can fill it in - if _publish_build does
		# not fire again after a reconnect, they cast rank-1 spells for the rest of the run
		# while their own screen shows the tree they paid for.
		var returned: Node3D = _client_avatar()
		_check("the host relearned their tree on the way back in",
			returned != null and returned.get_spell_rank(BUILT_SPELL) == BUILT_RANK,
			"rank %d" % [returned.get_spell_rank(BUILT_SPELL) if returned != null else -1])
	elif not _client_report.is_empty():
		_failures.append("the client never came back from its drop")

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL - %d failed: %s" % [_failures.size(), ", ".join(_failures)])
	get_tree().create_timer(0.5).timeout.connect(get_tree().quit)
