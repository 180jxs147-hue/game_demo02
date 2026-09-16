extends RefCounted

const Visuals = preload("res://Scripts/MenuVisuals.gd")

static func backdrop(root: Control):
	for name in ["ColorRect", "BgLayer"]:
		var old = root.get_node_or_null(name)
		if old: old.hide()
	var background := TextureRect.new()
	background.texture = preload("res://Assets/UI/WarRoom/camp_backdrop.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	root.move_child(background, 0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.055, 0.035, 0.02, 0.12)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	root.move_child(shade, 1)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func frame(control: Control, padding: int = 24):
	# A container child would participate in layout. Put decoration under the
	# scene layout instead, and follow the content rect without changing its size.
	var root: Control = control
	while root.get_parent() is Control:
		root = root.get_parent()
	var panel := Panel.new()
	panel.name = str(control.name) + "Frame"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Visuals.cloth(false, Color.WHITE, padding))
	root.add_child(panel)
	root.move_child(panel, mini(2, root.get_child_count() - 1))
	var update := func():
		panel.position = control.get_global_rect().position - root.get_global_rect().position - Vector2(padding, padding)
		panel.size = control.size + Vector2(padding, padding) * 2
	control.item_rect_changed.connect(update)
	update.call_deferred()

static func controls(root: Control):
	root.theme = Visuals.create_theme()
	for button in root.find_children("*", "Button", true, false):
		# Cards retain their own art and rarity styling.
		if _inside_card(button, root): continue
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.remove_theme_stylebox_override(state)
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 44)
		button.add_theme_font_size_override("font_size", 18)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func _inside_card(node: Node, root: Node) -> bool:
	var parent := node.get_parent()
	while parent and parent != root:
		if parent.scene_file_path == "res://Scenes/CardSlot.tscn": return true
		parent = parent.get_parent()
	return false

static func apply(root: Control):
	controls(root)
	match root.name:
		"Barracks":
			backdrop(root)
			root.get_node("RootLayout/Sidebar").add_theme_stylebox_override("panel", Visuals.cloth(false, Color.WHITE, 18))
			root.get_node("RootLayout/Content").add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			root.get_node("RootLayout/Content/ContentVBox/MainArea/Detail").add_theme_stylebox_override("panel", Visuals.cloth(false, Color.WHITE, 22))
			root.get_node("RootLayout/Content/ContentVBox/MainArea/Pages/TagsPage/CardList").add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			root.get_node("RootLayout/Sidebar/SidebarVBox/TitleLabel").text = "兵营图鉴"
			root.get_node("RootLayout/Sidebar/SidebarVBox/TitleLabel").add_theme_color_override("font_color", Visuals.GOLD)
			var detail: Control = root.get_node("RootLayout/Content/ContentVBox/MainArea/Detail/DetailVBox")
			detail.get_node("CountLabel").add_theme_color_override("font_color", Visuals.MUTED)
			detail.get_node("NameLabel").add_theme_color_override("font_color", Visuals.GOLD)
			root._update_columns.call_deferred()
		"MetaShop":
			backdrop(root)
			var layout: Control = root.get_node("VBox")
			layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layout.offset_left = 100
			layout.offset_top = 90
			layout.offset_right = -100
			layout.offset_bottom = -90
			layout.add_theme_constant_override("separation", 40)
			root.get_node("VBox/Header/Title").add_theme_font_size_override("font_size", 32)
			root.get_node("VBox/Upgrades").add_theme_constant_override("separation", 36)
			for row in root.get_node("VBox/Upgrades").get_children():
				row.custom_minimum_size.y = 120
				row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.get_child(1).size_flags_vertical = Control.SIZE_SHRINK_CENTER
				frame(row, 14)
		"CampShop":
			backdrop(root)
			for name in ["Infrastructure", "Hospital", "Recruitment"]:
				frame(root.get_node("Content/" + name), 20)
			var header: Label = root.get_node("Header/Label")
			header.add_theme_font_size_override("font_size", 34)
			root.get_node("Header/GoldLabel").add_theme_color_override("font_color", Visuals.GOLD)
			Visuals.primary(root.get_node("Header/NextLevelBtn"))
		"LevelSelect":
			backdrop(root)
			var list = root.get_node("ScrollContainer/VBoxContainer")
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for card in list.get_children():
				if card is PanelContainer:
					card.add_theme_stylebox_override("panel", Visuals.cloth(false, Color.WHITE, 20))
		"SaveSlots":
			for panel in root.get_node("VBox/Slots").get_children():
				if panel is PanelContainer:
					panel.add_theme_stylebox_override("panel", Visuals.cloth(false, Color.WHITE, 20))
		"SettingsMenu":
			backdrop(root)
			root.get_node("Background").hide()
			root.get_node("Shade").hide()
			frame(root.get_node("Content"), 30)
