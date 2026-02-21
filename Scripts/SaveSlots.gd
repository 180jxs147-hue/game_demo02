extends Control

@onready var background = $Background
@onready var back_button = $VBox/Bottom/BackButton

# Mode: "load", "new", "save"
var mode: String = "load"
var is_popup: bool = false

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
	_apply_theme()
	
	# If GameState has a mode set, use it (unless we set it locally before ready?)
	# We'll assume GameState is the source of truth if we are in a full scene switch.
	# If is_popup is true, we expect the caller to set 'mode' before adding to tree.
	if GameState and not is_popup:
		mode = GameState.slot_select_mode
	
	if mode == "load":
		mode_label.text = "载入模式"
	elif mode == "save":
		mode_label.text = "存储模式"
	else:
		mode_label.text = "新游戏模式"
		
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

func _apply_theme():
	if not GameState:
		return
	if background:
		var bg_path = "res://Assets/Backgrounds/main_menu_bg.png"
		if ResourceLoader.exists(bg_path):
			var tex = load(bg_path)
			if tex:
				background.texture = tex
				if has_node("ColorRect"):
					$ColorRect.color = Color(0, 0, 0, 0.3)
	for node in find_children("", "Button", true, false):
		if node is Button:
			GameState.apply_button_style(node)

func _slot_info(i: int) -> String:
	var cfg := ConfigFile.new()
	var err = cfg.load("user://savegame_slot_%d.cfg" % i)
	if err == OK:
		var idx = int(cfg.get_value("progress", "level_index", 0))
		return "槽位 %d · 关卡索引 %d" % [i, idx]
	return "槽位 %d · 空" % i

func _autosave_info() -> String:
	var cfg := ConfigFile.new()
	var err = cfg.load("user://autosave_progress.cfg")
	if err == OK:
		var idx = int(cfg.get_value("progress", "level_index", 0))
		return "自动存档 · 关卡索引 %d" % idx
	return "自动存档 · 空"

func _refresh():
	s1_info.text = _slot_info(1)
	s2_info.text = _slot_info(2)
	s3_info.text = _slot_info(3)
	
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
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove("savegame_slot_%d.cfg" % i)
		dir.remove("PlayerLibrary_slot_%d.tres" % i)
		_refresh()
