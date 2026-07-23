extends CanvasLayer
class_name SkillTree

const COLOR_NAMES = ["red", "blue", "green", "white", "black"]
const COLOR_TITLES = {
	"red": "🔴 RED (Aggro)",
	"blue": "🔵 BLUE (Control)",
	"green": "🟢 GREEN (Strength)",
	"white": "⚪ WHITE (Holy)",
	"black": "🖤 BLACK (Sacrifice)"
}
const COLOR_HEX = {
	"red": Color(0.85, 0.2, 0.2),
	"blue": Color(0.2, 0.5, 0.9),
	"green": Color(0.2, 0.75, 0.2),
	"white": Color(0.9, 0.9, 0.8),
	"black": Color(0.4, 0.2, 0.5)
}

const SKILL_DATA = {
	"red": [
		{"id": "red_1", "name": "Shock / Lightning Bolt", "cost": 1, "tier": 0, "desc": "Fast projectile striking single target. High tiers chain-lightning to nearby targets.", "lore": "\"Shock deals 2 damage to any target.\""},
		{"id": "red_2", "name": "Fireball", "cost": 3, "tier": 1, "desc": "Hold key to charge. Releasing launches a fireball with scaling blast radius & impact damage.", "lore": "\"Fireball deals X damage divided evenly...\""},
		{"id": "red_3", "name": "Rain of Ember", "cost": 7, "tier": 2, "desc": "Calls down a searing meteor shower in a designated zone, burning enemies inside for 5s.", "lore": "\"Rain of Ember deals 1 damage to each creature...\""},
		{"id": "red_4", "name": "Act of Treason", "cost": 15, "tier": 3, "desc": "Heavy physical strike that knocks back and stuns enemies for 2s.", "lore": "\"Gain control of target creature until end of turn...\""},
		{"id": "red_5", "name": "Chandra's Ignition", "cost": 30, "tier": 4, "desc": "Triggers a fiery shockwave around your character, pushing surrounding enemies outward.", "lore": "\"Target creature deals damage equal to its power to each other...\""},
		{"id": "aura_fervor", "name": "Fervor (Aura)", "cost": 50, "tier": 5, "desc": "Passive Capstone Aura: Increases movement speed and attack speed for player and Myrs (+25%).", "lore": "\"Creatures you control have haste.\""}
	],
	"blue": [
		{"id": "blue_1", "name": "Unsummon", "cost": 1, "tier": 0, "desc": "Force projectile knocking enemy backward. Wall/obstacle collisions deal heavy impact damage.", "lore": "\"Return target creature to its owner's hand.\""},
		{"id": "blue_2", "name": "Aetherize", "cost": 3, "tier": 1, "desc": "Hold key to charge. Sends out a massive water/wind wave blasting enemies into obstacles.", "lore": "\"Return all attacking creatures to their owner's hand.\""},
		{"id": "blue_3", "name": "Psionic Blast", "cost": 7, "tier": 2, "desc": "Instant psychic blast bypassing enemy defenses (deals 100 damage at 10 self HP cost).", "lore": "\"Psionic Blast deals 4 damage to any target and 2 damage to you.\""},
		{"id": "blue_4", "name": "Freeze Breath", "cost": 15, "tier": 3, "desc": "Applies Chill stacks. At 3 stacks, target freezes solid and explodes dealing Shatter AoE.", "lore": "\"Frozen solid and shattered to ice.\""},
		{"id": "blue_5", "name": "Counterspell", "cost": 30, "tier": 4, "desc": "Short 1.5s parry shield that absorbs next incoming hit and resets all spell cooldowns.", "lore": "\"Counter target spell.\""},
		{"id": "aura_rhystic_study", "name": "Rhystic Study (Aura)", "cost": 50, "tier": 5, "desc": "Passive Capstone Aura: Accelerates CDR by 30% and grants a +15 temp shield on spell cast.", "lore": "\"Did you pay the 1?\""}
	],
	"green": [
		{"id": "green_1", "name": "Titanic Growth", "cost": 1, "tier": 0, "desc": "Heavy frontal cone melee swing dealing Cleave damage scaling directly with Max HP (25%).", "lore": "\"Target creature gets +4/+4 until end of turn.\""},
		{"id": "green_2", "name": "Hurricane / Entangle", "cost": 3, "tier": 1, "desc": "Hold key to charge. Releasing roots enemies in radius for 3s and applies Poison DoT.", "lore": "\"Vines burst from the earth...\""},
		{"id": "green_3", "name": "Overrun", "cost": 7, "tier": 2, "desc": "Dash forward, trampling smaller enemies, knocking them aside, dealing speed-scaled damage.", "lore": "\"Creatures you control get +3/+3 and gain trample...\""},
		{"id": "green_4", "name": "Rabid Bite", "cost": 15, "tier": 3, "desc": "Quick feral bite dealing high physical damage, healing 50% of damage if target is rooted.", "lore": "\"Target creature deals damage equal to its power...\""},
		{"id": "green_5", "name": "Briar Patch", "cost": 30, "tier": 4, "desc": "Thorn aura reflecting 30% of incoming melee damage back to the attacker for 10s.", "lore": "\"Whenever a creature attacks you, Briar Patch deals damage...\""},
		{"id": "aura_sylvan_library", "name": "Sylvan Library (Aura)", "cost": 50, "tier": 5, "desc": "Passive Capstone Aura: Increases Max HP (+50%) and provides passive HP regen (+5/sec).", "lore": "\"Knowledge at the cost of blood.\""}
	],
	"white": [
		{"id": "white_1", "name": "Swords to Plowshares", "cost": 1, "tier": 0, "desc": "Radiant lance. Hits enemy -> 35% Max HP holy exile damage. Hits ally -> heals 60 HP.", "lore": "\"Exile target creature. Its controller gains life...\""},
		{"id": "white_2", "name": "Path to Exile", "cost": 3, "tier": 1, "desc": "Hold key to charge. Blinding ray dealing execute damage to low HP targets & leaving speed trail.", "lore": "\"Exile target creature...\""},
		{"id": "white_3", "name": "Wrath of God", "cost": 7, "tier": 2, "desc": "Hold key to charge. Sacred Nova healing allies, dealing 40% Max HP damage & blinding enemies.", "lore": "\"Destroy all creatures. They can't be regenerated.\""},
		{"id": "white_4", "name": "Pacifism", "cost": 15, "tier": 3, "desc": "Debuffs enemy/boss, reducing damage by 50% for 6s and clearing target aggro.", "lore": "\"Enchanted creature can't attack or block.\""},
		{"id": "white_5", "name": "Gideon's Reproach", "cost": 30, "tier": 4, "desc": "Holy retribution shield reflecting 40% of incoming damage back as radiant holy damage.", "lore": "\"Gideon's Reproach deals damage to target attacker...\""},
		{"id": "aura_glorious_anthem", "name": "Glorious Anthem (Aura)", "cost": 50, "tier": 5, "desc": "Passive Capstone Aura: Grants a +50 flat absorption shield and boosts party damage (+20%).", "lore": "\"Creatures you control get +1/+1.\""}
	],
	"black": [
		{"id": "black_1", "name": "Drain Life", "cost": 1, "tier": 0, "desc": "Dark projectile dealing dark damage and lifestealing 100% of damage dealt back to caster HP.", "lore": "\"Drain Life deals X damage... You gain life...\""},
		{"id": "black_2", "name": "Toxic Deluge", "cost": 3, "tier": 1, "desc": "Hold key to charge. Sacrifices current HP to unleash a toxic mist zone dealing heavy DoT.", "lore": "\"Pay X life: All creatures get -X/-X...\""},
		{"id": "black_3", "name": "Doom Blade", "cost": 7, "tier": 2, "desc": "Shadow strike dealing heavy direct damage & cursing enemy (+30% damage taken for 6s).", "lore": "\"Destroy target nonblack creature.\""},
		{"id": "black_4", "name": "Tendrils of Agony", "cost": 15, "tier": 3, "desc": "Life-draining tendrils. If cast within 3s of another spell, duplicates to hit 3 targets!", "lore": "\"Tendrils of Agony deals damage... Storm.\""},
		{"id": "black_5", "name": "Sign in Blood", "cost": 30, "tier": 4, "desc": "Blood pact resetting all active skill cooldowns at the cost of 15% current HP.", "lore": "\"Target player draws two cards and loses 2 life.\""},
		{"id": "aura_phyrexian_arena", "name": "Phyrexian Arena (Aura)", "cost": 50, "tier": 5, "desc": "Passive Capstone Aura: Drains 1% HP/sec, but boosts party damage (+40%) & movement (+30%).", "lore": "\"A small price for absolute power.\""}
	]
}

@onready var control_root: Control = $Control
var status_label: Label
var mana_label: Label
var tooltip_title: Label
var tooltip_lore: Label
var tooltip_desc: Label

var _column_containers: Dictionary = {}

func _ready() -> void:
	hide()
	SignalBus.color_path_chosen.connect(func(_c): update_ui())
	SignalBus.mana_changed.connect(func(_p): update_ui())
	_build_ui()
	update_ui()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree") or (visible and event.is_action_pressed("ui_cancel")):
		visible = not visible
		if visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			update_ui()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	if not control_root:
		return
		
	# Clear existing static panel children
	for c in control_root.get_children():
		c.queue_free()
		
	# Dim Background
	var bg = ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = Color(0.02, 0.02, 0.04, 0.92)
	control_root.add_child(bg)
	
	# Main Container
	var vbox = VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_child(vbox)
	control_root.add_child(margin)
	
	# Header Title
	var title = Label.new()
	title.text = "MTG 5-COLOR SKILL TREE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)
	
	# Path Lock Status
	status_label = Label.new()
	status_label.text = "SELECT YOUR COLOR PATH (Unlocking any node locks your path permanently)"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(status_label)
	
	# Mana Balance Display
	mana_label = Label.new()
	mana_label.text = "Collected Mana: W: 0 | U: 0 | B: 0 | R: 0 | G: 0"
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_label.add_theme_font_size_override("font_size", 15)
	mana_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	vbox.add_child(mana_label)
	
	if GameSettings.debug_mode:
		var dbg_hbox = HBoxContainer.new()
		dbg_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		dbg_hbox.add_theme_constant_override("separation", 10)
		
		var m_btn = Button.new()
		m_btn.text = "⚡ +100 All Mana (F1)"
		m_btn.pressed.connect(func():
			var main_c = get_tree().current_scene
			if main_c and main_c.has_method("add_mana"):
				for c in ["White", "Blue", "Black", "Red", "Green"]:
					main_c.add_mana(c, 100)
			update_ui()
		)
		dbg_hbox.add_child(m_btn)
		
		var r_btn = Button.new()
		r_btn.text = "🔄 Reset Color Path (F2)"
		r_btn.pressed.connect(func():
			var p = get_tree().get_first_node_in_group("player")
			if p:
				p.chosen_color_path = ""
				p.unlocked_spells_in_path.clear()
				p.unlocked_capstone_aura = ""
				SignalBus.color_path_chosen.emit("")
				SignalBus.active_spell_changed.emit(p.get_spell_name_for_slot(p.active_spell_index))
			update_ui()
		)
		dbg_hbox.add_child(r_btn)
		
		var u_btn = Button.new()
		u_btn.text = "🔓 Unlock Current Path (F3)"
		u_btn.pressed.connect(func():
			var p = get_tree().get_first_node_in_group("player")
			if p:
				var target_color = p.chosen_color_path if p.chosen_color_path != "" else "red"
				p.chosen_color_path = target_color
				for i in range(1, 6):
					var sid = target_color + "_" + str(i)
					if not p.unlocked_spells_in_path.has(sid):
						p.unlocked_spells_in_path.append(sid)
				p.unlocked_capstone_aura = "aura_" + p._get_aura_name_for_color(target_color)
				SignalBus.color_path_chosen.emit(target_color)
				SignalBus.active_spell_changed.emit(p.get_spell_name_for_slot(p.active_spell_index))
			update_ui()
		)
		dbg_hbox.add_child(u_btn)
		vbox.add_child(dbg_hbox)
	
	# Middle HBox for 5 Columns
	var hbox = HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)
	
	for color in COLOR_NAMES:
		var col_panel = PanelContainer.new()
		col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var col_vbox = VBoxContainer.new()
		col_vbox.add_theme_constant_override("separation", 8)
		
		var col_title = Label.new()
		col_title.text = COLOR_TITLES[color]
		col_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_title.add_theme_font_size_override("font_size", 16)
		col_title.add_theme_color_override("font_color", COLOR_HEX[color])
		col_vbox.add_child(col_title)
		
		var sep = HSeparator.new()
		col_vbox.add_child(sep)
		
		var nodes = SKILL_DATA[color]
		for node_info in nodes:
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 48)
			btn.text = "%s\n(Cost: %d Mana)" % [node_info["name"], node_info["cost"]]
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.mouse_entered.connect(_show_tooltip.bind(node_info))
			btn.pressed.connect(_on_node_click.bind(color, node_info))
			btn.set_meta("node_info", node_info)
			col_vbox.add_child(btn)
			
		col_panel.add_child(col_vbox)
		hbox.add_child(col_panel)
		_column_containers[color] = col_vbox

	# Bottom Tooltip Panel
	var tt_panel = PanelContainer.new()
	tt_panel.custom_minimum_size = Vector2(0, 110)
	
	var tt_vbox = VBoxContainer.new()
	tt_vbox.add_theme_constant_override("separation", 4)
	
	tooltip_title = Label.new()
	tooltip_title.text = "Hover over a skill node to view details"
	tooltip_title.add_theme_font_size_override("font_size", 16)
	tooltip_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	tt_vbox.add_child(tooltip_title)
	
	tooltip_lore = Label.new()
	tooltip_lore.text = ""
	tooltip_lore.add_theme_font_size_override("font_size", 12)
	tooltip_lore.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	tt_vbox.add_child(tooltip_lore)
	
	tooltip_desc = Label.new()
	tooltip_desc.text = ""
	tooltip_desc.add_theme_font_size_override("font_size", 13)
	tt_vbox.add_child(tooltip_desc)
	
	tt_panel.add_child(tt_vbox)
	vbox.add_child(tt_panel)

func update_ui() -> void:
	var player = get_tree().get_first_node_in_group("player")
	var main_c = get_tree().current_scene
	
	if main_c and "mana_pool" in main_c and mana_label:
		var mp = main_c.mana_pool
		mana_label.text = "Collected Mana: W: %d | U: %d | B: %d | R: %d | G: %d" % [
			mp.get("White", 0), mp.get("Blue", 0), mp.get("Black", 0), mp.get("Red", 0), mp.get("Green", 0)
		]
		
	if not player:
		return
		
	var path = player.chosen_color_path
	if path != "" and status_label:
		status_label.text = "PATH COMMITTED: %s (Other 4 color paths are locked)" % COLOR_TITLES[path]
		status_label.add_theme_color_override("font_color", COLOR_HEX[path])
	elif status_label:
		status_label.text = "SELECT YOUR COLOR PATH (Unlocking any node locks your path permanently)"
		status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		
	for color in COLOR_NAMES:
		var col_vbox = _column_containers.get(color, null)
		if not col_vbox:
			continue
			
		var is_locked_branch = (path != "" and path != color)
		var nodes = SKILL_DATA[color]
		
		var buttons = []
		for child in col_vbox.get_children():
			if child is Button:
				buttons.append(child)
				
		for i in range(buttons.size()):
			var btn = buttons[i]
			var info = nodes[i]
			var spell_id = info["id"]
			var cost = info["cost"]
			var tier = info["tier"]
			
			var is_unlocked = player.unlocked_spells_in_path.has(spell_id) or player.unlocked_capstone_aura == spell_id
			
			if is_unlocked:
				btn.text = "%s\n[UNLOCKED]" % info["name"]
				btn.disabled = true
			elif is_locked_branch:
				btn.text = "%s\n[PATH LOCKED]" % info["name"]
				btn.disabled = true
			else:
				# Must unlock sequentially within branch
				var can_unlock_tier = true
				if tier > 0:
					var prev_id = nodes[tier - 1]["id"]
					can_unlock_tier = player.unlocked_spells_in_path.has(prev_id)
					
				var mana_key = color.capitalize()
				if color == "white": mana_key = "White"
				elif color == "blue": mana_key = "Blue"
				elif color == "black": mana_key = "Black"
				elif color == "red": mana_key = "Red"
				elif color == "green": mana_key = "Green"
				
				var available_mana = main_c.mana_pool.get(mana_key, 0) if (main_c and "mana_pool" in main_c) else 0
				var can_afford = available_mana >= cost
				
				btn.text = "%s\nCost: %d %s Mana" % [info["name"], cost, mana_key]
				btn.disabled = not (can_unlock_tier and can_afford)

func _show_tooltip(info: Dictionary) -> void:
	if tooltip_title:
		tooltip_title.text = info["name"] + " (Cost: %d Mana)" % info["cost"]
	if tooltip_lore:
		tooltip_lore.text = info["lore"]
	if tooltip_desc:
		tooltip_desc.text = info["desc"]

func _on_node_click(color: String, info: Dictionary) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var main_c = get_tree().current_scene
	if not player or not main_c or not main_c.has_method("spend_mana_cost"):
		return
		
	var mana_key = color.capitalize()
	if color == "white": mana_key = "White"
	elif color == "blue": mana_key = "Blue"
	elif color == "black": mana_key = "Black"
	elif color == "red": mana_key = "Red"
	elif color == "green": mana_key = "Green"
	
	var cost = info["cost"]
	if main_c.spend_mana_cost({mana_key: cost}):
		player._on_spell_unlocked(color, info["id"])
		update_ui()

