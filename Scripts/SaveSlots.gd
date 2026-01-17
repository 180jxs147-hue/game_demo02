extends Control

@onready var background = $Background
@onready var back_button = $VBox/Bottom/BackButton
var load_mode: bool = false
@onready var mode_label = $VBox/Header/ModeLabel
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
	if GameState:
		load_mode = GameState.slot_select_mode == "load"
	mode_label.text = "载入模式" if load_mode else "新游戏模式"
	_refresh()
	s1_btn.pressed.connect(func(): _choose_slot(1))
	s2_btn.pressed.connect(func(): _choose_slot(2))
	s3_btn.pressed.connect(func(): _choose_slot(3))
	if s1_del: s1_del.pressed.connect(func(): _delete_slot(1))
	if s2_del: s2_del.pressed.connect(func(): _delete_slot(2))
	if s3_del: s3_del.pressed.connect(func(): _delete_slot(3))
	if back_button:
		back_button.pressed.connect(func():
			get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
		)

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

func _refresh():
	s1_info.text = _slot_info(1)
	s2_info.text = _slot_info(2)
	s3_info.text = _slot_info(3)

func _choose_slot(i: int):
	if not GameState: return
	GameState.current_slot = i
	if load_mode:
		GameState.load_all()
	else:
		GameState.clear_save()
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _delete_slot(i: int):
	var save_path := "user://savegame_slot_%d.cfg" % i
	var lib_path := "user://PlayerLibrary_slot_%d.tres" % i
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(lib_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(lib_path))
	_refresh()
