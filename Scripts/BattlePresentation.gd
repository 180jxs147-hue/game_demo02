extends Node

## Presentation only. Both armies share one scale and row origin at every size.
const Visuals = preload("res://Scripts/MenuVisuals.gd")
var battle: Node2D
var hud: Control
var phase: Label
var subtitle: Label
var detail: Label
var portrait: TextureRect
var footprint: Control
var selected: UnitData
var panels: Dictionary = {}
var captions: Dictionary = {}

func _ready():
	battle = get_parent()
	hud = battle.get_node("CanvasLayer/HUD")
	hud.theme = Visuals.create_theme()
	for key in ["Top", "Synergy", "Dock", "Details"]:
		var panel := Panel.new()
		panel.name = "Battle" + key
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", Visuals.surface(Color(0.075, 0.073, 0.066, 0.96), Visuals.GOLD))
		hud.add_child(panel)
		hud.move_child(panel, 0)
		panels[key] = panel
	captions["Title"] = label("时空阵线", 32, Visuals.PAPER)
	captions["Synergy"] = label("当前羁绊", 24, Visuals.GOLD)
	captions["Hint"] = label("拖动卡牌部署 · 悬停查看详情", 13, Visuals.MUTED)
	captions["Friendly"] = label("我方军阵", 17, Color("9bd0ab"))
	captions["Enemy"] = label("敌方军阵", 17, Color("e49b87"))
	phase = label("布阵阶段", 32, Visuals.GOLD)
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle = label("部署军阵，准备迎敌", 14, Visuals.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail = label("单位详情\n\n悬停棋子或备战卡牌\n查看属性与占位", 17, Visuals.PAPER)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(portrait)
	footprint = Control.new()
	footprint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footprint.draw.connect(_draw_footprint)
	hud.add_child(footprint)
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

func style_button(button: Button, primary: bool = false):
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.remove_theme_stylebox_override(state)
	button.modulate = Color.WHITE
	button.add_theme_font_size_override("font_size", 23 if primary else 17)
	if primary: Visuals.primary(button)

func place(node: Control, rect: Rect2):
	node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	node.position = rect.position
	node.size = rect.size

func layout():
	if not is_instance_valid(hud): return
	var size := get_viewport().get_visible_rect().size
	var w := size.x
	var h := size.y
	var dock_y := h - 216.0
	place(panels.Top, Rect2(0, 0, w, 86))
	place(panels.Synergy, Rect2(14, 116, 210, dock_y - 128))
	place(panels.Dock, Rect2(0, dock_y, w, 216))
	place(panels.Details, Rect2(w * 0.39, dock_y + 14, w * 0.36, 188))
	place(captions.Title, Rect2(24, 17, 245, 48))
	place(captions.Synergy, Rect2(32, 132, 170, 36))
	place(battle.synergy_label, Rect2(32, 190, 172, maxf(100, dock_y - 240)))
	place(battle.manpower_label, Rect2(w * 0.19, 26, w * 0.22, 34))
	place(battle.enemy_manpower_label, Rect2(w * 0.63, 26, w * 0.20, 34))
	battle.manpower_label.add_theme_color_override("font_color", Color("9bd0ab"))
	battle.enemy_manpower_label.add_theme_color_override("font_color", Color("e49b87"))
	place(phase, Rect2(w * 0.41, 7, w * 0.22, 44))
	place(subtitle, Rect2(w * 0.41, 54, w * 0.22, 24))
	place(hud.get_node("BattleLogButton"), Rect2(w - 228, 23, 132, 40))
	place(hud.get_node("BattleSpeedButton"), Rect2(w - 84, 23, 66, 40))
	place(battle.bench_panel, Rect2(24, dock_y + 12, w * 0.37 - 24, 192))
	place(captions.Hint, Rect2(132, dock_y + 16, 300, 24))
	place(portrait, Rect2(w * 0.39 + 14, dock_y + 26, 118, 155))
	place(detail, Rect2(w * 0.39 + 148, dock_y + 24, w * 0.36 - 158, 163))
	place(footprint, Rect2(w * 0.75 - 84, dock_y + 128, 70, 60))
	var action := Rect2(w * 0.77, dock_y + 38, w * 0.21, 68)
	place(hud.get_node("StartButton"), action)
	style_button(hud.get_node("StartButton"), true)
	if hud.has_node("FinishBattleButton"):
		place(hud.get_node("FinishBattleButton"), action)
		style_button(hud.get_node("FinishBattleButton"), true)
	place(hud.get_node("SaveButton"), Rect2(w * 0.77, dock_y + 131, w * 0.10, 47))
	place(hud.get_node("TopMenuButton"), Rect2(w * 0.88, dock_y + 131, w * 0.10, 47))
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
		subtitle.text = "敌军已溃败" if battle._count_alive_units(false) == 0 else "战局已定"
	elif BattleManager.is_battle_started:
		phase.text = "交战中"
		subtitle.text = "两军交锋"
	else:
		phase.text = "布阵阶段"
		subtitle.text = "部署军阵，准备迎敌"
	if battle.synergy_label.text.strip_edges() == "当前羁绊:":
		battle.synergy_label.text = "暂无激活羁绊\n\n部署同文明、同兵种\n单位可激活加成。"
	elif battle.synergy_label.text.begins_with("当前羁绊:"):
		battle.synergy_label.text = battle.synergy_label.text.trim_prefix("当前羁绊:\n")

func inspect(data: UnitData):
	selected = data
	portrait.texture = data.icon
	detail.text = "%s\n\n生命  %g       防御  %g\n攻击  %g       射程  %g\n冷却  %.1fs    民力  %g" % [data.name, data.max_hp, data.defense, data.attack_damage, data.attack_range, data.cooldown, data.manpower_cost]
	footprint.queue_redraw()

func _draw_footprint():
	if not selected: return
	var bounds := Vector2i.ONE
	for cell in selected.grid_shape: bounds = bounds.max(cell + Vector2i.ONE)
	var step := minf(14, minf(footprint.size.x / bounds.x, footprint.size.y / bounds.y))
	for cell in selected.grid_shape:
		footprint.draw_rect(Rect2(Vector2(cell) * step, Vector2.ONE * (step - 2)), Visuals.GOLD)
