extends PanelContainer

signal drag_requested(data: UnitData)
var data: UnitData
var use_card_base := false
var drag_on_press := true

func setup_stacked(value: UnitData, count: int):
	data = value
	custom_minimum_size = Vector2(132, 152)
	add_theme_stylebox_override("panel", preload("res://Scripts/MenuVisuals.gd").surface(Color("24231f"), Color("897452")))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var art := TextureRect.new()
	art.texture = data.icon
	art.custom_minimum_size = Vector2(96, 80)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	var title := Label.new()
	title.text = data.name + (" ×%d" % count if count > 1 else "")
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var stats := Label.new()
	stats.text = "生命 %d  攻击 %d" % [data.max_hp, data.attack_damage]
	stats.add_theme_font_size_override("font_size", 12)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	mouse_entered.connect(func():
		if BattleManager.instance: BattleManager.instance.show_tooltip(data, self)
		modulate = Color(1.15, 1.1, 1.0)
	)
	mouse_exited.connect(func(): modulate = Color.WHITE)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if data and not BattleManager.is_battle_started and not BattleManager.instance.battle_ended:
			drag_requested.emit(data)
			accept_event()
