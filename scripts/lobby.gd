extends CanvasLayer
class_name Lobby
## Host or join, see who is connected, start the match.
##
## Deliberately reachable from inside the running map rather than sitting in front of
## it as a separate main scene. The game must stay playable alone at every step of the
## networking work, so single-player never touches this panel at all: press F9, host or
## join, and the map reloads with everyone in it.
##
## See docs/MULTIPLAYER_PLAN.md, Phase 1.

const TOGGLE_ACTION := "lobby"

var _root: Control
var _address_field: LineEdit
var _name_field: LineEdit
var _status_label: Label
var _peer_list: VBoxContainer
var _host_button: Button
var _join_button: Button
var _start_button: Button
var _leave_button: Button


func _ready() -> void:
	layer = 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()
	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.connection_failed.connect(func(): _set_status("Could not reach that host."))
	Net.server_closed.connect(func(): _set_status("The host closed the session."))
	Net.match_started.connect(_on_match_started)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(TOGGLE_ACTION):
		return
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()
	get_viewport().set_input_as_handled()


# --- actions ------------------------------------------------------------------

func _on_host_pressed() -> void:
	if Net.host(Net.DEFAULT_PORT, _player_name()) == OK:
		_set_status("Hosting on port %d. Waiting for players." % Net.DEFAULT_PORT)
	else:
		_set_status("Could not open port %d - is something already using it?" % Net.DEFAULT_PORT)
	_refresh()


func _on_join_pressed() -> void:
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	if Net.join(address, Net.DEFAULT_PORT, _player_name()) == OK:
		_set_status("Connecting to %s..." % address)
	else:
		_set_status("Could not reach %s." % address)
	_refresh()


## Reloading the map is what actually starts the match: every peer rebuilds the scene,
## and only then does the server spawn one avatar per connected peer. Doing it this way
## keeps a single spawn path for both single- and multiplayer.
func _on_start_pressed() -> void:
	Net.start_match()


func _on_match_started() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func _on_leave_pressed() -> void:
	Net.leave()
	_set_status("Left the session.")
	_refresh()


func _player_name() -> String:
	var entered: String = _name_field.text.strip_edges()
	return entered if not entered.is_empty() else "Player"


# --- ui -----------------------------------------------------------------------

func _on_peer_list_changed(_peers: Dictionary) -> void:
	_refresh()


func _set_status(text: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = text


func _refresh() -> void:
	if not is_instance_valid(_peer_list):
		return
	for child in _peer_list.get_children():
		child.queue_free()

	var active: bool = Net.is_active()
	_host_button.disabled = active
	_join_button.disabled = active
	_address_field.editable = not active
	_name_field.editable = not active
	_leave_button.disabled = not active
	# Only the host may start, and only with somebody to start with.
	_start_button.disabled = not (active and Net.is_server() and Net.peers.size() > 1)

	if not active:
		var idle := Label.new()
		idle.text = "Not connected. Host, or join an address."
		idle.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		_peer_list.add_child(idle)
		return

	for id in Net.ordered_ids():
		var row := Label.new()
		var tag: String = " (you)" if int(id) == Net.local_id() else ""
		var host_tag: String = " - host" if int(id) == 1 else ""
		row.text = "%d. %s%s%s" % [Net.seat_of(int(id)) + 1, Net.display_name(int(id)), tag, host_tag]
		_peer_list.add_child(row)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.018, 0.025, 0.92)
	_root.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-280.0, -220.0)
	panel.size = Vector2(560.0, 440.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.055, 0.98)
	style.border_color = Color(0.4, 0.66, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var heading := Label.new()
	heading.text = "MULTIPLAYER"
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	rows.add_child(heading)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Your name"
	_name_field.text = "Player"
	rows.add_child(_name_field)

	_host_button = Button.new()
	_host_button.text = "HOST on port %d" % Net.DEFAULT_PORT
	_host_button.custom_minimum_size = Vector2(0.0, 38.0)
	_host_button.pressed.connect(_on_host_pressed)
	rows.add_child(_host_button)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_address_field = LineEdit.new()
	_address_field.placeholder_text = "127.0.0.1"
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address_field)
	_join_button = Button.new()
	_join_button.text = "JOIN"
	_join_button.custom_minimum_size = Vector2(120.0, 38.0)
	_join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(_join_button)
	rows.add_child(join_row)

	rows.add_child(HSeparator.new())

	var players_heading := Label.new()
	players_heading.text = "PLAYERS"
	players_heading.add_theme_font_size_override("font_size", 14)
	players_heading.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	rows.add_child(players_heading)

	_peer_list = VBoxContainer.new()
	_peer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_peer_list)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	rows.add_child(_status_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.custom_minimum_size = Vector2(0.0, 40.0)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)
	_leave_button = Button.new()
	_leave_button.text = "LEAVE"
	_leave_button.custom_minimum_size = Vector2(140.0, 40.0)
	_leave_button.pressed.connect(_on_leave_pressed)
	buttons.add_child(_leave_button)
	rows.add_child(buttons)

	_set_status("Press F9 to close. Host, or join an address.")
