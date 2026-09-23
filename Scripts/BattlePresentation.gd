extends Node

## Presentation only. Both armies share one scale and row origin at every size.
const Visuals = preload("res://Scripts/MenuVisuals.gd")
var battle: Node2D
var hud: Control
var phase: Label
var detail_root: VBoxContainer
var detail_name: Label
var detail_stats: GridContainer
var card_preview: Control
var plaque: TextureRect
var panels: Dictionary = {}
var header_plates: Dictionary = {}
var button_sheet: Texture2D
var detail_backdrop: TextureRect
var captions: Dictionary = {}

func _ready():
	battle = get_parent()
	hud = battle.get_node("CanvasLayer/HUD")
	hud.theme = Visuals.create_theme()
	button_sheet = load("res://Assets/UI/Battle/button_sheet_gen.png")
	var panel_order := ["Top", "Synergy", "Dock", "Details"]
	for panel_index in panel_order.size():
		var key: String = panel_order[panel_index]
		var panel: Control = Panel.new() if key in ["Dock", "Details"] else TextureRect.new()
		panel.name = "Battle" + key
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.z_index = -10 + panel_index
		if key == "Dock":
			panel.add_theme_stylebox_override("panel", dock_panel_style())
		elif key == "Details":
			panel.add_theme_stylebox_override("panel", details_panel_style())
		else:
			var texture_panel := panel as TextureRect
			texture_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_panel.clip_contents = true
			texture_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			if key == "Top":
				texture_panel.texture = load("res://Assets/UI/Battle/top_bar_gen_v2.png")
			else:
				# Generated lower-HUD frame is used as the visual base for the
				# reserve/detail/action dock. Labels and controls remain native UI
				# nodes so text stays crisp and responsive.
				texture_panel.texture = load("res://Assets/UI/Battle/%s" % ("synergy_panel_gen.png" if key == "Synergy" else "bottom_dock_frame_v1.png"))
			texture_panel.modulate = Color(1, 1, 1, 0.94)
		hud.add_child(panel)
		hud.move_child(panel, 0)
		panels[key] = panel
	for key in ["Title", "FriendlyPower", "EnemyPower", "Log", "Speed"]:
		var plate := Panel.new()
		plate.name = "HeaderPlate" + key
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.z_index = -5
		plate.add_theme_stylebox_override("panel", header_plate_style())
		hud.add_child(plate)
		header_plates[key] = plate
	captions["Title"] = label("时空阵线", 32, Visuals.PAPER)
	captions["Synergy"] = label("当前羁绊", 24, Visuals.GOLD)
	captions["Hint"] = label("拖动卡牌部署 · 悬停查看详情", 13, Visuals.MUTED)
	captions["Friendly"] = label("我方军阵", 17, Color("9bd0ab"))
	captions["Enemy"] = label("敌方军阵", 17, Color("e49b87"))
	for text_node in [captions.Title, captions.Synergy, captions.Friendly, captions.Enemy]:
		text_node.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.015, 0.9))
		text_node.add_theme_constant_override("outline_size", 2)
	plaque = TextureRect.new()
	plaque.texture = load("res://Assets/UI/Battle/status_plaque.png")
	plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(plaque)
	phase = label("布阵阶段", 32, Visuals.GOLD)
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.015, 0.95))
	phase.add_theme_constant_override("outline_size", 2)
	detail_root = VBoxContainer.new()
	detail_root.name = "UnitDetailContent"
	detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_theme_constant_override("separation", 5)
	detail_name = Label.new()
	detail_name.add_theme_font_size_override("font_size", 22)
	detail_name.add_theme_color_override("font_color", Visuals.GOLD)
	detail_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(detail_name)
	var separator := ColorRect.new()
	separator.custom_minimum_size.y = 1
	separator.color = Color(0.76, 0.60, 0.34, 0.62)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(separator)
	detail_stats = GridContainer.new()
	detail_stats.columns = 2
	detail_stats.add_theme_constant_override("h_separation", 18)
	detail_stats.add_theme_constant_override("v_separation", 8)
	detail_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(detail_stats)
	hud.add_child(detail_root)
	card_preview = load("res://Scenes/CardSlot.tscn").instantiate()
	card_preview.name = "UnitDetailCardPreview"
	card_preview.set("use_card_base", true)
	card_preview.set("drag_on_press", false)
	card_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control in card_preview.find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(card_preview)
	# Low-contrast background for the otherwise empty black unit detail area.
	detail_backdrop = TextureRect.new()
	detail_backdrop.texture = load("res://Assets/UI/Battle/unit_detail_backdrop_v1.png")
	detail_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	detail_backdrop.modulate = Color(1, 1, 1, 0.82)
	detail_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_backdrop.z_index = -1
	hud.add_child(detail_backdrop)
	battle.bench_grid.columns = 1000
	var scroll: ScrollContainer = battle.bench_grid.get_parent()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	battle.bench_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	battle.synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle.synergy_label.add_theme_font_size_override("font_size", 17)
	for button in hud.find_children("*", "Button", true, false):
		style_button(button)
	get_viewport().size_changed.connect(layout)
	layout()

func label(value: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(node)
	return node

func ornate_panel() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://Assets/UI/Battle/ornate_panel.png")
	style.texture_margin_left = 92
	style.texture_margin_top = 92
	style.texture_margin_right = 92
	style.texture_margin_bottom = 92
	style.expand_margin_left = 2
	style.expand_margin_top = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	style.modulate_color = Color(1.0, 0.96, 0.86, 0.96)
	return style

func battle_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.028, 0.022, 0.84)
	style.border_color = Color(0.67, 0.52, 0.31, 0.82)
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func style_button(button: Button, primary: bool = false):
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.remove_theme_stylebox_override(state)
	button.modulate = Color.WHITE
	button.add_theme_font_size_override("font_size", 23 if primary else 17)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var regions := {"normal": Rect2(0, 0, 768, 512), "hover": Rect2(768, 0, 768, 512), "pressed": Rect2(0, 512, 768, 512), "disabled": Rect2(768, 512, 768, 512)}
	for state in regions:
		var atlas := AtlasTexture.new()
		atlas.atlas = button_sheet
		atlas.region = regions[state]
		var style := StyleBoxTexture.new()
		style.texture = atlas
		style.texture_margin_left = 90
		style.texture_margin_right = 90
		style.texture_margin_top = 90
		style.texture_margin_bottom = 90
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		button.add_theme_stylebox_override(state, style)
	if primary: button.add_theme_font_size_override("font_size", 24)

func details_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.038, 0.026, 0.70)
	style.border_color = Color(0.62, 0.47, 0.28, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func dock_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.026, 0.020, 0.94)
	style.border_color = Color(0.48, 0.36, 0.22, 0.9)
	style.set_border_width_all(1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func header_plate_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.018, 0.014, 0.62)
	style.border_color = Color(0.70, 0.53, 0.30, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style

func style_action_button(button: Button, primary: bool):
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("5a211a") if primary else Color("261d16")
		if state == "hover": style.bg_color = Color("7a3020") if primary else Color("3b2a1c")
		if state == "pressed": style.bg_color = Color("3e1714") if primary else Color("17120e")
		if state == "disabled": style.bg_color = Color("211c18")
		style.border_color = Color("d3a85f") if primary else Color("9f7a45")
		style.set_border_width_all(2 if primary else 1)
		style.set_corner_radius_all(7)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Visuals.PAPER)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 22 if primary else 16)

func place(node: Control, rect: Rect2):
	node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	node.position = rect.position
	node.size = rect.size

func layout():
	if not is_instance_valid(hud): return
	var size := get_viewport().get_visible_rect().size
	var w := size.x
	var h := size.y
	var dock_y := h - 240.0
	place(panels.Top, Rect2(0, 0, w, 86))
	place(panels.Synergy, Rect2(14, 116, 210, dock_y - 128))
	place(panels.Dock, Rect2(0, dock_y, w, 240))
	place(panels.Details, Rect2(w * 0.39, dock_y + 14, w * 0.36, 212))
	place(detail_backdrop, Rect2(w * 0.39 + 8, dock_y + 22, w * 0.36 - 16, 196))
	place(header_plates.Title, Rect2(20, 14, 170, 54))
	place(captions.Title, Rect2(20, 18, 170, 42))
	captions.Title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	captions.Title.add_theme_font_size_override("font_size", 26)
	place(plaque, Rect2(w * 0.34, 2, w * 0.32, 78))
	place(captions.Synergy, Rect2(46, 158, 160, 30))
	captions.Synergy.add_theme_font_size_override("font_size", 20)
	place(battle.synergy_label, Rect2(46, 206, 154, maxf(100, dock_y - 260)))
	place(header_plates.FriendlyPower, Rect2(w * 0.20, 14, w * 0.16, 54))
	place(header_plates.EnemyPower, Rect2(w * 0.60, 14, w * 0.18, 54))
	place(header_plates.Log, Rect2(w - 246, 14, 150, 54))
	place(header_plates.Speed, Rect2(w - 90, 14, 70, 54))
	place(battle.manpower_label, Rect2(w * 0.20, 24, w * 0.16, 34))
	place(battle.enemy_manpower_label, Rect2(w * 0.60, 24, w * 0.18, 34))
	battle.manpower_label.add_theme_color_override("font_color", Color("9bd0ab"))
	battle.enemy_manpower_label.add_theme_color_override("font_color", Color("e49b87"))
	battle.manpower_label.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.95))
	battle.enemy_manpower_label.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.95))
	battle.manpower_label.add_theme_constant_override("outline_size", 2)
	battle.enemy_manpower_label.add_theme_constant_override("outline_size", 2)
	battle.manpower_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle.enemy_manpower_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place(phase, Rect2(w * 0.38, 7, w * 0.24, 56))
	phase.add_theme_font_size_override("font_size", 30)
	phase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place(hud.get_node("BattleLogButton"), Rect2(w - 228, 23, 132, 40))
	place(hud.get_node("BattleSpeedButton"), Rect2(w - 84, 23, 66, 40))
	place(battle.bench_panel, Rect2(32, dock_y + 20, w * 0.36 - 40, 208))
	var bench_title := battle.bench_panel.get_node_or_null("VBox/Title") as Label
	if bench_title:
		bench_title.add_theme_font_size_override("font_size", 16)
		bench_title.add_theme_color_override("font_color", Visuals.PAPER)
	place(captions.Hint, Rect2(164, dock_y + 20, 420, 24))
	card_preview.position = Vector2(w * 0.39 + 11, dock_y + 12)
	card_preview.scale = Vector2.ONE * 0.47
	place(detail_root, Rect2(w * 0.39 + 154, dock_y + 34, w * 0.36 - 168, 160))
	var action := Rect2(w - 360, dock_y + 26, 336, 58)
	place(hud.get_node("StartButton"), action)
	style_action_button(hud.get_node("StartButton"), true)
	if hud.has_node("FinishBattleButton"):
		place(hud.get_node("FinishBattleButton"), action)
		style_action_button(hud.get_node("FinishBattleButton"), true)
	place(hud.get_node("SaveButton"), Rect2(w - 360, dock_y + 100, 156, 48))
	place(hud.get_node("TopMenuButton"), Rect2(w - 180, dock_y + 100, 156, 48))
	style_action_button(hud.get_node("SaveButton"), false)
	style_action_button(hud.get_node("TopMenuButton"), false)
	# Scale the combined board once. Unequal armies NEVER scale independently.
	var cols: int = GridManager.playable_columns
	var rows: int = GridManager.playable_rows
	var gap := 88.0
	var region := Rect2(256, 176, w - 294, dock_y - 208)
	var cell := minf(102.0, minf((region.size.x - gap) / (cols + battle.current_enemy_cols), region.size.y / maxi(rows, battle.current_enemy_rows)))
	var scale_factor := cell / GameConst.GRID_SIZE
	battle.battlefield.scale = Vector2.ONE * scale_factor
	var combined_width: float = cell * (cols + battle.current_enemy_cols) + gap
	battle.battlefield_position = Vector2(region.position.x + (region.size.x - combined_width) * 0.5, region.position.y)
	battle.battlefield.position = battle.battlefield_position
	battle.friendly_field.position = Vector2.ZERO
	battle.enemy_field.position = Vector2(cols * GameConst.GRID_SIZE + gap / scale_factor, 0)
	place(captions.Friendly, Rect2(battle.battlefield_position + Vector2(0, -32), Vector2(240, 24)))
	place(captions.Enemy, Rect2(battle.enemy_field.global_position + Vector2(0, -32), Vector2(240, 24)))
	captions.Friendly.text = "我方军阵  %d × %d" % [cols, rows]
	captions.Enemy.text = "敌方军阵  %d × %d" % [battle.current_enemy_cols, battle.current_enemy_rows]

func _process(_delta: float):
	if battle.battle_ended:
		phase.text = "战斗胜利" if battle._count_alive_units(false) == 0 else "战斗结束"
	elif BattleManager.is_battle_started:
		phase.text = "交战中"
	else:
		phase.text = "布阵阶段"
	if battle.synergy_label.text.strip_edges() == "当前羁绊:":
		battle.synergy_label.text = "暂无激活羁绊\n\n部署同文明、同兵种\n单位可激活加成。"
	elif battle.synergy_label.text.begins_with("当前羁绊:"):
		battle.synergy_label.text = battle.synergy_label.text.trim_prefix("当前羁绊:\n")

func inspect(data: UnitData):
	if not data: return
	detail_name.text = data.name
	if card_preview.has_method("setup"):
		card_preview.setup(data)
	for child in detail_stats.get_children():
		child.queue_free()
	var stats := [
		["生命", "%.1f" % data.max_hp], ["防御", "%.1f" % data.defense],
		["攻击", "%.1f" % data.attack_damage], ["射程", "%.1f" % data.attack_range],
		["冷却", "%.1fs" % data.cooldown], ["民力", "%.1f" % data.manpower_cost]
	]
	for entry in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := Label.new()
		key.text = entry[0]
		key.custom_minimum_size.x = 42
		key.add_theme_font_size_override("font_size", 15)
		key.add_theme_color_override("font_color", Visuals.MUTED)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var value := Label.new()
		value.text = entry[1]
		value.add_theme_font_size_override("font_size", 17)
		value.add_theme_color_override("font_color", Visuals.PAPER)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(key)
		row.add_child(value)
		detail_stats.add_child(row)
