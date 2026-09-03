extends CanvasLayer
class_name UpkeepPanel
## The build phase between waves: the only time team mana can be spent, and the one
## moment each wave the whole team is in the same place.
##
## Three purchases, and the consensus each needs rises with how permanent it is:
##
##   Myr             any player. Nobody objects to a worker, and making it a vote is
##                   pure friction.
##   Skill point     any player. It gives a point to EVERY player, so there is nothing
##                   to argue about.
##   Enchantment     majority vote. Permanent, colour-locked, and it shapes the whole
##                   run, so the team agrees or it does not happen.
##
## Unaffordable items stay visible and say what is MISSING rather than only greying
## out - "needs 6 more Black" is what sends the team to the black lane next wave, and
## that is the loop keeping colour alive now that builds are bought with points.
##
## Single-player skips the voting entirely: with one player there is no majority to
## reach, so the panel is simply a shop.
##
## Over the network the SERVER holds every proposal, every tally and every mana
## reservation; clients send requests and render what they are told. Anything else lets
## two peers pass contradictory votes with the same mana.

const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]
const COLOR_HEX: Dictionary = {
	"White": Color(0.95, 0.91, 0.72),
	"Blue": Color(0.35, 0.62, 0.95),
	"Black": Color(0.62, 0.42, 0.75),
	"Red": Color(0.92, 0.34, 0.24),
	"Green": Color(0.32, 0.78, 0.42),
}

var _root: Control
var _pool_label: RichTextLabel
var _level_label: Label
var _timer_label: Label
var _shop_rows: VBoxContainer
var _vote_rows: VBoxContainer
var _log_label: RichTextLabel
var _ready_button: Button

var _time_left: float = 0.0
var _active: bool = false
## Enchantment colour -> {"yes": int, "no": int, "voted": Dictionary}. Mana is reserved
## while a proposal is open, so two proposals can never overdraw the pool.
var _proposals: Dictionary = {}
## Colours that already failed a vote this Upkeep and may not be re-proposed, so one
## player cannot spam the same enchantment until people click yes to make it stop.
var _blocked: Dictionary = {}
var _reserved: Dictionary = {}
var _log_lines: Array[String] = []
var _local_ready: bool = false
## peer id -> ready. Server-owned; clients receive it.
var _ready_peers: Dictionary = {}
## peer ids that have already voted on a colour, so nobody votes twice.
var _voters: Dictionary = {}


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()
	SignalBus.upkeep_started.connect(_on_upkeep_started)
	SignalBus.mana_changed.connect(func(_pool: Dictionary): _refresh())
	SignalBus.enchantment_changed.connect(func(_c: String, _s: int): _refresh())


func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	_timer_label.text = "%0.0f s" % maxf(_time_left, 0.0)
	# The clock runs everywhere so the countdown reads correctly, but only the server
	# may act on it - two peers ending Upkeep would start the wave twice.
	if _time_left <= 0.0 and Net.is_server():
		_finish()


# --- lifecycle ----------------------------------------------------------------

func _on_upkeep_started(duration: float) -> void:
	_active = true
	_time_left = duration
	_proposals.clear()
	_blocked.clear()
	_reserved.clear()
	_log_lines.clear()
	_local_ready = false
	_ready_peers.clear()
	_voters.clear()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


## Ends Upkeep and starts the next wave. Any proposal still open simply lapses and its
## reservation is released - a team that cannot agree keeps its mana and loses only a
## wave of compounding, which is punishment enough.
func _finish() -> void:
	if not _active:
		return
	_active = false
	_proposals.clear()
	_reserved.clear()
	_voters.clear()
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SignalBus.upkeep_finished.emit()


func _on_ready_pressed() -> void:
	_local_ready = not _local_ready
	if not Net.is_active():
		if _local_ready:
			_finish()
		return
	_set_ready.rpc_id(1, _local_ready)
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _set_ready(ready: bool) -> void:
	if not Net.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = Net.local_id()
	_ready_peers[sender] = ready
	if _all_ready():
		_finish()
	else:
		_broadcast_ready.rpc(_ready_peers)
		_refresh()


@rpc("authority", "call_remote", "reliable")
func _broadcast_ready(state: Dictionary) -> void:
	_ready_peers = state
	_refresh()


## Counts only CONNECTED peers, so one drop-out cannot hold the phase open forever.
func _all_ready() -> bool:
	if not Net.is_active():
		return _local_ready
	for id in Net.ordered_ids():
		if not bool(_ready_peers.get(int(id), false)):
			return false
	return not Net.peers.is_empty()


# --- purchases ----------------------------------------------------------------

func _local_player() -> Node:
	return PlayerRegistry.get_local()


func _buy_myr() -> void:
	if Net.is_active() and not Net.is_server():
		_request_myr.rpc_id(1)
		return
	_request_myr()


@rpc("any_peer", "call_local", "reliable")
func _request_myr() -> void:
	if not Net.is_server():
		return
	if not RunState.spend({"Colorless": GameSettings.myr_mana_cost}):
		return
	var main_controller: Node = get_tree().current_scene
	if main_controller != null and main_controller.has_method("spawn_myr"):
		main_controller.spawn_myr()
	_announce("Built a myr for %d" % GameSettings.myr_mana_cost)


## Any player, like the myr: in an emergency you want whoever notices to be able to act,
## and making the team vote while the crystal is at 10% would be agonising.
func _buy_repair() -> void:
	if Net.is_active() and not Net.is_server():
		_request_repair.rpc_id(1)
		return
	_request_repair()


@rpc("any_peer", "call_local", "reliable")
func _request_repair() -> void:
	if not Net.is_server():
		return
	var main_controller: Node = get_tree().current_scene
	if main_controller == null or not main_controller.has_method("repair_crystal"):
		return
	if main_controller.crystal_missing() <= 1.0:
		return
	if not RunState.spend({"Colorless": GameSettings.upkeep_crystal_repair_cost}):
		return
	var restored: float = main_controller.repair_crystal(GameSettings.upkeep_crystal_repair_amount)
	_announce("Repaired the crystal for %d" % int(restored))


func _buy_skill_point() -> void:
	if Net.is_active() and not Net.is_server():
		_request_skill_point.rpc_id(1)
		return
	_request_skill_point()


@rpc("any_peer", "call_local", "reliable")
func _request_skill_point() -> void:
	if not Net.is_server():
		return
	if not RunState.spend({"Colorless": GameSettings.upkeep_skill_point_cost}):
		return
	# Every player, not only whoever clicked - that is what makes it uncontroversial.
	if Net.is_active():
		_grant_point_to_all.rpc()
	_grant_point_to_all()
	_announce("Bought a skill point for everyone (%d)" % GameSettings.upkeep_skill_point_cost)


@rpc("authority", "call_remote", "reliable")
func _grant_point_to_all() -> void:
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player.has_method("grant_skill_points"):
			player.grant_skill_points(1)


## Proposing reserves the mana rather than spending it, so a second proposal cannot be
## made with money the first one is already counting on.
func _propose(color: String) -> void:
	if Net.is_active() and not Net.is_server():
		_request_propose.rpc_id(1, color)
		return
	_request_propose(color)


@rpc("any_peer", "call_local", "reliable")
func _request_propose(color: String) -> void:
	if not Net.is_server():
		return
	if _proposals.has(color) or _blocked.has(color):
		return
	var cost: Dictionary = RunState.enchantment_cost(color)
	if not RunState.can_afford(_with_reservations(cost)):
		return
	_reserved[color] = cost
	var proposer: int = multiplayer.get_remote_sender_id() if Net.is_active() else 1
	if proposer == 0:
		proposer = Net.local_id()
	_proposals[color] = {"yes": 1, "no": 0}
	_voters[color] = {proposer: true}
	if _vote_threshold() <= 1:
		_resolve(color, true)
		return
	_broadcast_proposals()


func _vote(color: String, approve: bool) -> void:
	if Net.is_active() and not Net.is_server():
		_request_vote.rpc_id(1, color, approve)
		return
	_request_vote(color, approve)


@rpc("any_peer", "call_local", "reliable")
func _request_vote(color: String, approve: bool) -> void:
	if not Net.is_server() or not _proposals.has(color):
		return
	var voter: int = multiplayer.get_remote_sender_id() if Net.is_active() else 1
	if voter == 0:
		voter = Net.local_id()
	# One vote each. Without this a single client could carry any motion alone.
	var cast: Dictionary = _voters.get(color, {})
	if cast.has(voter):
		return
	cast[voter] = true
	_voters[color] = cast

	var proposal: Dictionary = _proposals[color]
	var key: String = "yes" if approve else "no"
	proposal[key] = int(proposal[key]) + 1
	# Resolves the instant a majority is reached rather than waiting out the timer.
	if int(proposal["yes"]) >= _vote_threshold():
		_resolve(color, true)
	elif int(proposal["no"]) >= _vote_threshold():
		_resolve(color, false)
	else:
		_broadcast_proposals()


func _resolve(color: String, passed: bool) -> void:
	_proposals.erase(color)
	_reserved.erase(color)
	_voters.erase(color)
	if passed and RunState.buy_enchantment(color):
		_announce("%s passed - now %d stacks" % [RunState.enchantment_name(color), RunState.enchantment_stacks(color)])
	else:
		_blocked[color] = true
		_announce("%s was rejected" % RunState.enchantment_name(color))
	_broadcast_proposals()


func _withdraw(color: String) -> void:
	if Net.is_active() and not Net.is_server():
		_request_withdraw.rpc_id(1, color)
		return
	_request_withdraw(color)


@rpc("any_peer", "call_local", "reliable")
func _request_withdraw(color: String) -> void:
	if not Net.is_server():
		return
	_proposals.erase(color)
	_reserved.erase(color)
	_voters.erase(color)
	_broadcast_proposals()


## Proposals and their tallies are the server's; this is how clients learn them.
func _broadcast_proposals() -> void:
	if Net.is_active():
		_apply_proposals.rpc(_proposals, _blocked)
	_refresh()


@rpc("authority", "call_remote", "reliable")
func _apply_proposals(proposals: Dictionary, blocked: Dictionary) -> void:
	_proposals = proposals
	_blocked = blocked
	_refresh()


## Purchases are announced rather than logged locally, so every player sees the same
## history of what the team's mana went on.
func _announce(line: String) -> void:
	if Net.is_active():
		_apply_log.rpc(line)
	_apply_log(line)


@rpc("authority", "call_remote", "reliable")
func _apply_log(line: String) -> void:
	_log(line)
	_refresh()


func _vote_threshold() -> int:
	var players: int = maxi(get_tree().get_nodes_in_group("player").size(), 1)
	return players / 2 + 1


## `cost` plus everything currently reserved by open proposals, so affordability is
## judged against what is actually still free.
func _with_reservations(cost: Dictionary) -> Dictionary:
	var total: Dictionary = cost.duplicate()
	for color: String in _reserved.keys():
		for key: String in _reserved[color].keys():
			total[key] = int(total.get(key, 0)) + int(_reserved[color][key])
	return total


func _log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > 6:
		_log_lines.remove_at(0)


# --- ui -----------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.018, 0.025, 0.9)
	_root.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-520.0, -290.0)
	panel.size = Vector2(1040.0, 580.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.045, 0.055, 0.98), Color(0.9, 0.67, 0.2)))
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	# --- header: the pool, the level, the clock -------------------------------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	rows.add_child(header)

	var heading := Label.new()
	heading.text = "UPKEEP"
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", Color(1.0, 0.8, 0.36))
	header.add_child(heading)

	_pool_label = RichTextLabel.new()
	_pool_label.bbcode_enabled = true
	_pool_label.fit_content = true
	_pool_label.scroll_active = false
	_pool_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_pool_label)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 16)
	header.add_child(_level_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 24)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	header.add_child(_timer_label)

	rows.add_child(HSeparator.new())

	# --- body: shop on the left, votes and log on the right -------------------
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)

	var shop_column := VBoxContainer.new()
	shop_column.add_theme_constant_override("separation", 6)
	shop_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(shop_column)
	shop_column.add_child(_section_label("PURCHASES"))
	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 6)
	shop_column.add_child(_shop_rows)

	var vote_column := VBoxContainer.new()
	vote_column.add_theme_constant_override("separation", 6)
	vote_column.custom_minimum_size = Vector2(360.0, 0.0)
	body.add_child(vote_column)
	vote_column.add_child(_section_label("PROPOSALS"))
	_vote_rows = VBoxContainer.new()
	_vote_rows.add_theme_constant_override("separation", 6)
	vote_column.add_child(_vote_rows)
	vote_column.add_child(_section_label("THIS UPKEEP"))
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vote_column.add_child(_log_label)

	# --- footer: ready check --------------------------------------------------
	rows.add_child(HSeparator.new())
	_ready_button = Button.new()
	_ready_button.custom_minimum_size = Vector2(0.0, 42.0)
	_ready_button.pressed.connect(_on_ready_pressed)
	rows.add_child(_ready_button)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	return label


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _refresh() -> void:
	if not is_instance_valid(_pool_label):
		return

	var pool := PackedStringArray()
	for color: String in COLORS:
		pool.append("[color=#%s]%s %d[/color]" % [
			COLOR_HEX[color].to_html(false), color.substr(0, 1), int(RunState.mana_pool.get(color, 0))])
	_pool_label.text = "  ".join(pool)

	var progress: Vector2 = RunState.xp_progress()
	var points: int = 0
	var local: Node = _local_player()
	if local != null and "skill_points" in local:
		points = int(local.skill_points)
	_level_label.text = "Level %d   XP %d/%d   Points %d" % [
		RunState.team_level, int(progress.x), int(progress.y), points]

	_rebuild_shop()
	_rebuild_votes()
	_log_label.text = "\n".join(_log_lines) if not _log_lines.is_empty() else "[color=#666]nothing bought yet[/color]"
	_ready_button.text = "READY - waiting for the rest" if _local_ready else "READY (start the next wave)"


func _rebuild_shop() -> void:
	for child in _shop_rows.get_children():
		child.queue_free()

	_shop_rows.add_child(_purchase_row(
		"Build a myr", "Harvests a lane and sweeps drops. Compounds, so worth most early.",
		{"Colorless": GameSettings.myr_mana_cost}, _buy_myr, Color(0.8, 0.82, 0.86)))
	_shop_rows.add_child(_purchase_row(
		"Skill point for everyone", "+1 point to every player, not just the buyer.",
		{"Colorless": GameSettings.upkeep_skill_point_cost}, _buy_skill_point, Color(0.9, 0.85, 0.5)))

	# Only offered when there is something to fix, so a healthy team is not tempted to
	# waste mana on it and a hurt one cannot miss it.
	var main_controller: Node = get_tree().current_scene
	if main_controller != null and main_controller.has_method("crystal_missing") and main_controller.crystal_missing() > 1.0:
		_shop_rows.add_child(_purchase_row(
			"Repair the crystal (%d missing)" % int(main_controller.crystal_missing()),
			"Restores %d integrity. The only way to undo a leak." % int(GameSettings.upkeep_crystal_repair_amount),
			{"Colorless": GameSettings.upkeep_crystal_repair_cost}, _buy_repair, Color(0.55, 0.85, 1.0)))

	for color: String in COLORS:
		var cost: Dictionary = RunState.enchantment_cost(color)
		var label: String = "%s  (%s, %d stacks)" % [
			RunState.enchantment_name(color), color, RunState.enchantment_stacks(color)]
		var row: Control = _purchase_row(
			label, RunState.enchantment_description(color), cost,
			_propose.bind(color), COLOR_HEX[color])
		_shop_rows.add_child(row)


## One shop line. Unaffordable rows stay visible and name what is missing, because
## knowing what you CANNOT buy is what drives the next wave's lane choice.
func _purchase_row(title: String, subtitle: String, cost: Dictionary, on_press: Callable, tint: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", tint)
	text.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = subtitle
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.65, 0.67, 0.72))
	text.add_child(desc_label)
	row.add_child(text)

	var button := Button.new()
	button.custom_minimum_size = Vector2(210.0, 40.0)
	var missing: Dictionary = RunState.shortfall(_with_reservations(cost))
	if missing.is_empty():
		button.text = _cost_text(cost)
		button.pressed.connect(on_press)
	else:
		var parts := PackedStringArray()
		for color: String in missing.keys():
			parts.append("%d %s" % [int(missing[color]), color])
		button.text = "needs %s" % ", ".join(parts)
		button.disabled = true
	row.add_child(button)
	return row


func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for color: String in cost.keys():
		parts.append("%d %s" % [int(cost[color]), "any" if color == "Colorless" else color])
	return "Buy - " + ", ".join(parts)


func _rebuild_votes() -> void:
	for child in _vote_rows.get_children():
		child.queue_free()

	if _proposals.is_empty():
		var idle := Label.new()
		idle.text = "No open proposals."
		idle.add_theme_font_size_override("font_size", 12)
		idle.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
		_vote_rows.add_child(idle)
		return

	for color: String in _proposals.keys():
		var proposal: Dictionary = _proposals[color]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "%s   %d yes / %d no  (need %d)" % [
			RunState.enchantment_name(color), int(proposal["yes"]), int(proposal["no"]), _vote_threshold()]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", COLOR_HEX[color])
		row.add_child(label)
		var yes := Button.new()
		yes.text = "Yes"
		yes.pressed.connect(_vote.bind(color, true))
		row.add_child(yes)
		var no := Button.new()
		no.text = "No"
		no.pressed.connect(_vote.bind(color, false))
		row.add_child(no)
		var withdraw := Button.new()
		withdraw.text = "x"
		withdraw.pressed.connect(_withdraw.bind(color))
		row.add_child(withdraw)
		_vote_rows.add_child(row)
