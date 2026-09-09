extends Control
class_name MainMenu
## The screen the game starts on: play alone, host a LAN game, or find one to join.
##
## Four pages in one Control rather than four scenes, because they share every piece of
## state that matters - the player name, the connection, and the peer list - and a page
## change here is a `visible` flag rather than a scene load that would drop it.
##
## The map is only ever loaded once a decision has been made, so a solo run reaches
## exactly the same scene by the same call as a five-player one. Networking stays inert
## until Host or Join is pressed; see scripts/net.gd.

const MAP_SCENE: String = "res://scenes/misc/main.tscn"

enum Page { MAIN, HOST, BROWSE, LOBBY }

var _pages: Dictionary = {}
var _status_label: Label

var _name_field: LineEdit
var _server_name_field: LineEdit
var _host_port_field: LineEdit
var _host_password_field: LineEdit

var _server_list: ItemList
var _scan_button: Button
var _join_password_field: LineEdit
var _join_button: Button
var _direct_address_field: LineEdit
var _servers: Array = []

var _reconnect_button: Button

var _lobby_title: Label
var _peer_list: VBoxContainer
var _ready_button: Button
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_show_page(Page.MAIN)

	# Arriving here from a match that dropped rather than from the desktop. The address
	# is still known and the host holds the seat, so the only thing worth showing is the
	# way back in.
	if Net.can_reconnect():
		_set_status("Connection lost. Your seat is held - reconnect to rejoin the run.")
	_refresh_reconnect()

	Net.peer_list_changed.connect(_on_peer_list_changed)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_closed.connect(_on_server_closed)
	Net.join_rejected.connect(_on_join_rejected)
	Net.lan_servers_updated.connect(_on_lan_servers_updated)
	Net.lan_scan_finished.connect(_on_lan_scan_finished)
	Net.match_started.connect(_on_match_started)


# --- actions ------------------------------------------------------------------

## Single-player is deliberately the shortest path in this file: no peer, no lobby, no
## readiness - straight into the map, exactly as the game booted before this menu.
func _on_solo_pressed() -> void:
	# A solo run is a NEW run, so it must not inherit the build left over from a match
	# this player was dropped out of.
	PlayerRegistry.clear_saved_build()
	GameSettings.player_count = 1
	_enter_map()


func _on_create_pressed() -> void:
	var port: int = _host_port()
	var result: Error = Net.host(port, _player_name(), _server_name_field.text, _host_password_field.text)
	if result != OK:
		_set_status("Could not open port %d - something else is already using it." % port)
		return
	PlayerRegistry.clear_saved_build()
	_set_status("Hosting on port %d. Waiting for players." % port)
	_show_page(Page.LOBBY)


func _on_scan_pressed() -> void:
	_servers = []
	_server_list.clear()
	_scan_button.disabled = true
	_set_status("Scanning the local network...")
	Net.scan_lan()


func _on_join_pressed() -> void:
	var address: String = _direct_address_field.text.strip_edges()
	var port: int = Net.DEFAULT_PORT
	var in_progress: bool = false
	var selected: PackedInt32Array = _server_list.get_selected_items()
	if selected.size() > 0 and selected[0] < _servers.size():
		var server: Dictionary = _servers[selected[0]]
		address = String(server.get("address", ""))
		port = int(server.get("port", Net.DEFAULT_PORT))
		in_progress = bool(server.get("in_progress", false))
	if address.is_empty():
		_set_status("Pick a server from the list, or type an address.")
		return
	# Only RECONNECT brings a build back. Picking a match out of the browser is joining
	# as a new player, even if the machine still remembers one.
	PlayerRegistry.clear_saved_build()
	if in_progress:
		# There is no lobby to wait in - the match is already running. The map is loaded
		# FIRST and opens the connection itself once it is standing, because the server
		# pushes the whole existing world the moment a peer connects.
		Net.begin_join(address, port, _player_name(), _join_password_field.text)
		_enter_map()
		return
	if Net.join(address, port, _player_name(), _join_password_field.text) != OK:
		_set_status("Could not reach %s:%d." % [address, port])
		return
	_set_status("Connecting to %s:%d..." % [address, port])
	_show_page(Page.LOBBY)


func _on_ready_pressed() -> void:
	Net.set_local_ready(not Net.is_ready(Net.local_id()))


func _on_start_pressed() -> void:
	Net.start_match()


func _on_leave_pressed() -> void:
	Net.leave()
	Net.forget_last_join()
	PlayerRegistry.clear_saved_build()
	_refresh_reconnect()
	_set_status("Left the session.")
	_show_page(Page.MAIN)


## Back into the run that dropped, on exactly the terms the browser uses for any other
## match in progress: load the map, then connect.
func _on_reconnect_pressed() -> void:
	var details: Dictionary = Net.last_join
	if details.is_empty():
		return
	Net.begin_join(
		String(details["address"]),
		int(details["port"]),
		String(details["name"]),
		String(details["password"]),
	)
	_enter_map()


func _refresh_reconnect() -> void:
	if is_instance_valid(_reconnect_button):
		_reconnect_button.visible = Net.can_reconnect()


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- net callbacks ------------------------------------------------------------

func _on_peer_list_changed(_peers: Dictionary) -> void:
	_refresh_lobby()


func _on_connection_failed() -> void:
	_set_status("Could not reach that host.")
	_show_page(Page.BROWSE)


func _on_server_closed() -> void:
	Net.forget_last_join()
	PlayerRegistry.clear_saved_build()
	_refresh_reconnect()
	_set_status("The host closed the session.")
	_show_page(Page.MAIN)


func _on_join_rejected(reason: String) -> void:
	_set_status(reason)
	_show_page(Page.BROWSE)


func _on_lan_servers_updated(servers: Array) -> void:
	_servers = servers
	_server_list.clear()
	for server in servers:
		var entry: Dictionary = server
		var lock: String = " [locked]" if bool(entry.get("password", false)) else ""
		if bool(entry.get("in_progress", false)):
			lock += " [in progress]"
		_server_list.add_item("%s  -  %d/%d  -  %s:%d%s" % [
			String(entry.get("name", "LAN Game")),
			int(entry.get("players", 1)),
			int(entry.get("max", Net.MAX_PLAYERS)),
			String(entry.get("address", "")),
			int(entry.get("port", Net.DEFAULT_PORT)),
			lock,
		])


func _on_lan_scan_finished(servers: Array) -> void:
	_scan_button.disabled = false
	if servers.is_empty():
		_set_status("No games found on this network. You can still type an address.")
	else:
		_set_status("Found %d game%s." % [servers.size(), "" if servers.size() == 1 else "s"])


## Every peer lands here, host included: the host through its own local call and the
## clients through the RPC, so nobody loads the map at a different moment than anyone
## else and the server can spawn one avatar per peer as soon as the map is up.
func _on_match_started() -> void:
	_enter_map()


func _enter_map() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(MAP_SCENE)


# --- helpers ------------------------------------------------------------------

func _player_name() -> String:
	var entered: String = _name_field.text.strip_edges()
	return entered if not entered.is_empty() else "Player"


func _host_port() -> int:
	var entered: String = _host_port_field.text.strip_edges()
	if not entered.is_valid_int():
		return Net.DEFAULT_PORT
	return clampi(int(entered), 1024, 65535)


func _set_status(text: String) -> void:
	_status_label.text = text


func _show_page(page: Page) -> void:
	for key in _pages:
		(_pages[key] as Control).visible = key == page
	if page == Page.LOBBY:
		_refresh_lobby()


func _refresh_lobby() -> void:
	if not is_instance_valid(_peer_list):
		return
	for child in _peer_list.get_children():
		child.queue_free()

	var active: bool = Net.is_active()
	_lobby_title.text = Net.server_name if active else "Not connected"
	_ready_button.disabled = not active
	_ready_button.text = "NOT READY" if Net.is_ready(Net.local_id()) else "READY"
	# Only the host starts, and only once every single person has said yes.
	_start_button.visible = Net.is_server()
	_start_button.disabled = not (active and Net.is_server() and Net.all_ready())

	if not active:
		var idle := Label.new()
		idle.text = "Waiting for the connection..."
		idle.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		_peer_list.add_child(idle)
		return

	for id in Net.ordered_ids():
		var peer_id: int = int(id)
		var row := Label.new()
		var tag: String = " (you)" if peer_id == Net.local_id() else ""
		var host_tag: String = " - host" if peer_id == 1 else ""
		var state: String = "READY" if Net.is_ready(peer_id) else "not ready"
		row.text = "%d. %s%s%s   -   %s" % [
			Net.seat_of(peer_id) + 1, Net.display_name(peer_id), tag, host_tag, state,
		]
		row.add_theme_color_override(
			"font_color",
			Color(0.5, 0.9, 0.55) if Net.is_ready(peer_id) else Color(0.8, 0.78, 0.7),
		)
		_peer_list.add_child(row)


# --- ui -----------------------------------------------------------------------

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.018, 0.025)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-300.0, -250.0)
	panel.size = Vector2(600.0, 500.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.055, 0.98)
	style.border_color = Color(0.4, 0.66, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var heading := Label.new()
	heading.text = "MTG PENTAGON TOWER DEFENSE"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(heading)

	# One name field for the whole menu: the player types it once and it is used by
	# whichever page they end up on.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = "Name"
	name_row.add_child(name_label)
	_name_field = LineEdit.new()
	_name_field.text = "Player"
	_name_field.placeholder_text = "Your name"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_field)
	rows.add_child(name_row)

	rows.add_child(HSeparator.new())

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	_pages[Page.MAIN] = _build_main_page()
	_pages[Page.HOST] = _build_host_page()
	_pages[Page.BROWSE] = _build_browse_page()
	_pages[Page.LOBBY] = _build_lobby_page()
	for key in _pages:
		body.add_child(_pages[key])

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	rows.add_child(_status_label)


func _build_main_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_menu_button("HOST A GAME", func() -> void: _show_page(Page.HOST)))
	page.add_child(_menu_button("JOIN A GAME", func() -> void: _show_page(Page.BROWSE)))
	_reconnect_button = _menu_button("RECONNECT", _on_reconnect_pressed)
	_reconnect_button.visible = false
	page.add_child(_reconnect_button)
	page.add_child(_menu_button("PLAY SOLO", _on_solo_pressed))
	page.add_child(_menu_button("QUIT", _on_quit_pressed))
	return page


func _build_host_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(_section_label("HOST A LAN GAME"))

	_server_name_field = LineEdit.new()
	_server_name_field.placeholder_text = "Server name"
	page.add_child(_field_row("Server", _server_name_field))

	_host_port_field = LineEdit.new()
	_host_port_field.text = str(Net.DEFAULT_PORT)
	page.add_child(_field_row("Port", _host_port_field))

	_host_password_field = LineEdit.new()
	_host_password_field.secret = true
	_host_password_field.placeholder_text = "Leave empty for no password"
	page.add_child(_field_row("Password", _host_password_field))

	page.add_child(_spacer())
	page.add_child(_menu_button("CREATE LOBBY", _on_create_pressed))
	page.add_child(_menu_button("BACK", func() -> void: _show_page(Page.MAIN)))
	return page


func _build_browse_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(_section_label("GAMES ON THIS NETWORK"))

	_server_list = ItemList.new()
	_server_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_server_list.custom_minimum_size = Vector2(0.0, 140.0)
	_server_list.item_activated.connect(func(_index: int) -> void: _on_join_pressed())
	page.add_child(_server_list)

	_scan_button = Button.new()
	_scan_button.text = "SCAN"
	_scan_button.custom_minimum_size = Vector2(0.0, 34.0)
	_scan_button.pressed.connect(_on_scan_pressed)
	page.add_child(_scan_button)

	# Discovery is a broadcast, and a broadcast does not always cross a router or a
	# VPN. Typing the host's address has to stay possible when it does not.
	_direct_address_field = LineEdit.new()
	_direct_address_field.placeholder_text = "127.0.0.1"
	page.add_child(_field_row("Address", _direct_address_field))

	_join_password_field = LineEdit.new()
	_join_password_field.secret = true
	_join_password_field.placeholder_text = "Password, if the game has one"
	page.add_child(_field_row("Password", _join_password_field))

	_join_button = Button.new()
	_join_button.text = "JOIN"
	_join_button.custom_minimum_size = Vector2(0.0, 34.0)
	_join_button.pressed.connect(_on_join_pressed)
	page.add_child(_join_button)
	page.add_child(_menu_button("BACK", func() -> void: _show_page(Page.MAIN)))
	return page


func _build_lobby_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_lobby_title = Label.new()
	_lobby_title.add_theme_font_size_override("font_size", 18)
	_lobby_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	page.add_child(_lobby_title)
	page.add_child(_section_label("PLAYERS"))

	_peer_list = VBoxContainer.new()
	_peer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_peer_list)

	_ready_button = Button.new()
	_ready_button.text = "READY"
	_ready_button.custom_minimum_size = Vector2(0.0, 36.0)
	_ready_button.pressed.connect(_on_ready_pressed)
	page.add_child(_ready_button)

	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.custom_minimum_size = Vector2(0.0, 40.0)
	_start_button.pressed.connect(_on_start_pressed)
	page.add_child(_start_button)

	page.add_child(_menu_button("LEAVE", _on_leave_pressed))
	return page


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(action)
	return button


func _field_row(label_text: String, field: LineEdit) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(80.0, 0.0)
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
