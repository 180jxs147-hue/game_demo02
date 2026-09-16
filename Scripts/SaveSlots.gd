extends Control

@onready var background = $Background
@onready var back_button = $VBox/Bottom/BackButton

# Mode: "load", "new", "save"
var mode: String = "load"
var is_popup: bool = false
var slot_details: Dictionary = {}

@onready var mode_label = $VBox/Header/ModeLabel
@onready var s_auto = $VBox/Slots/SAuto
@onready var s_auto_info = $VBox/Slots/SAuto/SAutoInfo
@onready var s_auto_btn = $VBox/Slots/SAuto/SAutoStart
@onready var s1_info = $VBox/Slots/S1/S1Info
@onready var s2_info = $VBox/Slots/S2/S2Info
@onready var s3_info = $VBox/Slots/S3/S3Info
@onready var s1_btn = $VBox/Slots/S1/S1Start
@onready var s2_btn = $VBox/Slots/S2/S2Start
@onready var s3_btn = $VBox/Slots/S3/S3Start
@onready var s1_del = $VBox/Slots/S1/S1Delete
@onready var s2_del = $VBox/Slots/S2/S2Delete
@onready var s3_del = $VBox/Slots/S3/S3Delete

func _ready():
	preload("res://Scripts/WarMenuSkin.gd").apply.call_deferred(self)
	_apply_theme()
	
	# If GameState has a mode set, use it (unless we set it locally before ready?)
	# We'll assume GameState is the source of truth if we are in a full scene switch.
	# If is_popup is true, we expect the caller to set 'mode' before adding to tree.
	if GameState and not is_popup:
		mode = GameState.slot_select_mode
	
	if mode == "load":
		mode_label.text = "续接征途"
	elif mode == "save":
		mode_label.text = "记录战局"
	else:
		mode_label.text = "开启新篇"
		
	_refresh()
	
	s1_btn.pressed.connect(func(): _choose_slot(1))
	s2_btn.pressed.connect(func(): _choose_slot(2))
	s3_btn.pressed.connect(func(): _choose_slot(3))
	
	if s1_del: s1_del.pressed.connect(func(): _delete_slot(1))
	if s2_del: s2_del.pressed.connect(func(): _delete_slot(2))
	if s3_del: s3_del.pressed.connect(func(): _delete_slot(3))
	
	if back_button:
		# Disconnect any existing connections if necessary (though usually fresh instance)
		if is_popup:
			back_button.pressed.connect(func(): queue_free())
			back_button.text = "返回" # Or "关闭"
		else:
			back_button.pressed.connect(func():
				get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
			)
	
	if s_auto_btn:
		s_auto_btn.pressed.connect(_load_autosave)
	
	# Autosave slot visibility
	if s_auto:
		# Only show autosave in Load mode
		s_auto.visible = (mode == "load")
	$VBox.modulate.a = 0.0
	create_tween().tween_property($VBox, "modulate:a", 1.0, 0.3)

func _apply_theme():
	background.texture = preload("res://Assets/UI/WarRoom/camp_backdrop.png")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$ColorRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$ColorRect.color = Color(0.05, 0.03, 0.02, 0.25)
	theme = preload("res://Scripts/MenuVisuals.gd").create_theme()
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Noto Serif CJK SC", "serif"])
	$VBox/Header/Title.add_theme_font_override("font", title_font)
	mode_label.add_theme_color_override("font_color", Color("bfae91"))
	var rows := [s_auto, s1_info.get_parent(), s2_info.get_parent(), s3_info.get_parent()]
	var infos := [s_auto_info, s1_info, s2_info, s3_info]
	for index in range(rows.size()):
		var row: HBoxContainer = rows[index]
		var info: Label = infos[index]
		var position_in_list := row.get_index()
		var panel := PanelContainer.new()
		panel.name = "Archive%d" % index
		panel.add_theme_stylebox_override("panel", preload("res://Scripts/MenuVisuals.gd").cloth(false, Color.WHITE, 20))
		row.get_parent().add_child(panel)
		row.get_parent().move_child(panel, position_in_list)
		row.reparent(panel)
		panel.custom_minimum_size.y = 112
		# The wrapper follows the automatic row's mode-dependent visibility.
		row.visibility_changed.connect(func(): panel.visible = row.visible)
		panel.visible = row.visible
		var number := Label.new()
		number.text = "自动" if index == 0 else "%02d" % index
		number.custom_minimum_size.x = 64
		number.add_theme_font_override("font", title_font)
		number.add_theme_font_size_override("font_size", 28)
		number.add_theme_color_override("font_color", Color("c5a369"))
		row.add_child(number)
		row.move_child(number, 0)
		var text_column := VBoxContainer.new()
		text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text_column.add_theme_constant_override("separation", 8)
		row.add_child(text_column)
		row.move_child(text_column, 1)
		info.reparent(text_column)
		info.add_theme_font_size_override("font_size", 23)
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var detail := Label.new()
		detail.add_theme_font_size_override("font_size", 16)
		detail.add_theme_color_override("font_color", Color("aa9982"))
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_column.add_child(detail)
		slot_details[index] = detail
	for button in [s_auto_btn, s1_btn, s2_btn, s3_btn, s1_del, s2_del, s3_del, back_button]:
		button.custom_minimum_size = Vector2(108, 46)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", 20)
	for button in [s1_del, s2_del, s3_del]:
		button.add_theme_stylebox_override("normal", _surface(Color.TRANSPARENT, Color.TRANSPARENT))
		button.add_theme_color_override("font_color", Color("ba8b80"))
	var auto_spacer := Control.new()
	auto_spacer.custom_minimum_size.x = 108
	s_auto.add_child(auto_spacer)
	back_button.text = "返回主菜单"
	back_button.custom_minimum_size.x = 160

func _surface(fill: Color, border: Color, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _record_info(path: String, index: int) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		if FileAccess.file_exists(path):
			slot_details[index].text = "存档无法读取"
			return "自动存档" if index == 0 else "战役档案"
		slot_details[index].text = "尚无自动记录" if index == 0 else "尚未记录战局"
		return "自动存档 · 空" if index == 0 else "空白档案"
	var level_index := int(cfg.get_value("progress", "level_index", 0))
	var database = GameState.get_level_database()
	var level_title := "未知战役"
	if database and level_index >= 0 and level_index < database.levels.size():
		level_title = database.levels[level_index].level_name
	var stamp := FileAccess.get_modified_time(path)
	var date := Time.get_datetime_string_from_unix_time(stamp).replace("T", "  ")
	slot_details[index].text = "%s  ·  %s UTC" % ["自动记录" if index == 0 else "手动存档", date]
	return level_title

func _slot_info(i: int) -> String:
	return _record_info("user://savegame_slot_%d.cfg" % i, i)

func _autosave_info() -> String:
	return _record_info("user://autosave_progress.cfg", 0)

func _refresh():
	s1_info.text = _slot_info(1)
	s2_info.text = _slot_info(2)
	s3_info.text = _slot_info(3)
	var buttons := [s1_btn, s2_btn, s3_btn]
	var deletes := [s1_del, s2_del, s3_del]
	for index in range(3):
		var path := "user://savegame_slot_%d.cfg" % (index + 1)
		var exists := FileAccess.file_exists(path)
		buttons[index].disabled = mode == "load" and ConfigFile.new().load(path) != OK
		deletes[index].disabled = not (exists or FileAccess.file_exists("user://PlayerLibrary_slot_%d.tres" % (index + 1)))
	
	if s_auto_info:
		s_auto_info.text = _autosave_info()
	if s_auto_btn:
		s_auto_btn.disabled = not _autosave_exists()
	
	# In Save Mode, update button text?
	if mode == "save":
		s1_btn.text = "存储"
		s2_btn.text = "存储"
		s3_btn.text = "存储"
	elif mode == "load":
		s1_btn.text = "读取"
		s2_btn.text = "读取"
		s3_btn.text = "读取"
	else:
		s1_btn.text = "开始"
		s2_btn.text = "开始"
		s3_btn.text = "开始"

func _autosave_exists() -> bool:
	return FileAccess.file_exists("user://autosave_progress.cfg") or FileAccess.file_exists("user://Autosave_PlayerLibrary.tres")

func _choose_slot(i: int):
	var occupied := FileAccess.file_exists("user://savegame_slot_%d.cfg" % i) or FileAccess.file_exists("user://PlayerLibrary_slot_%d.tres" % i)
	if mode != "load" and occupied:
		var dialog := ConfirmationDialog.new()
		dialog.title = "覆盖存档"
		dialog.dialog_text = "槽位 %d 已有战役记录。继续将替换原有存档，此操作不可撤销。" % i
		dialog.get_ok_button().text = "确认覆盖"
		dialog.confirmed.connect(func():
			dialog.queue_free()
			_perform_choose_slot(i)
		)
		dialog.canceled.connect(dialog.queue_free)
		_show_confirmation(dialog)
		return
	_perform_choose_slot(i)

func _perform_choose_slot(i: int):
	if not GameState: return
	
	if mode == "save":
		GameState.save_to_slot(i)
		_refresh() # Update info to show it's saved
		# Optional: Feedback or Close
		# For now, let's just refresh and maybe close if popup?
		if is_popup:
			queue_free()
		return

	# Load or New Game
	GameState.current_slot = i
	# GameState.use_autosave_library = false # Force manual slot mode -> NO, we now load TO autosave.
	
	if mode == "load":
		# Load from Slot i directly
		GameState.load_from_slot(i)
	else: # new
		GameState.clear_save()
		# For new game, we also want to be in Autosave mode eventually?
		# clear_save() saves to current_slot path if use_autosave_library is false.
		# Let's see clear_save implementation. It uses save_progress().
		# We should probably init autosave for new game too.
		# But for now, let's stick to existing clear_save logic which might need update.
		# If clear_save resets everything, we should probably:
		# 1. Reset memory state.
		# 2. Init Autosave with this fresh state.
		# 3. Leave Slot i empty or overwritten? "New Game" usually overwrites Slot i?
		# Actually, standard flow: New Game -> Overwrite Slot i immediately? Or just play and save later?
		# User requirement: "Manual slots ... only modified when manually saved".
		# So New Game should NOT touch Slot i until user saves?
		# But "New Game" button is on the Slot selection screen. It implies "Start New Game on Slot 1".
		# Usually this means we overwrite Slot 1.
		# Let's assume New Game overwrites Slot 1 with initial state.
		
		# GameState.use_autosave_library = false # Deprecated
		GameState.clear_save() # Writes initial state to Slot i
		
		# AFTER overwriting Slot i, we should switch to Autosave mode so further progress doesn't touch it.
		GameState.load_from_slot(i) # Reload into memory (and reset autosave mode state if any)
		
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _load_autosave():
	if not GameState: return
	if mode == "save": return # Should be hidden, but safety check
	
	GameState.load_autosave_all()
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _delete_slot(i: int):
	_confirm_delete(i)

func _confirm_delete(i: int):
	var dialog = ConfirmationDialog.new()
	dialog.title = "确认删除"
	dialog.dialog_text = "确定要删除槽位 %d 的存档吗？此操作不可撤销。" % i
	dialog.get_ok_button().text = "确定删除"
	dialog.get_cancel_button().text = "取消"
	dialog.confirmed.connect(func():
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove("savegame_slot_%d.cfg" % i)
			dir.remove("PlayerLibrary_slot_%d.tres" % i)
		dialog.queue_free()
		_refresh()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	_show_confirmation(dialog)

func _show_confirmation(dialog: ConfirmationDialog):
	add_child(dialog)
	preload("res://Scripts/MenuVisuals.gd").style_dialog(dialog, true)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.018, 0.012, 0.7)
	add_child(shade)
	dialog.tree_exiting.connect(shade.queue_free)
	dialog.popup_centered()
