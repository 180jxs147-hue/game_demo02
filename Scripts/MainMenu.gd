extends Control

## 主菜单：负责场景跳转与存档清理入口。

@onready var clear_save_dialog = $ClearSaveDialog
@onready var info_dialog = $InfoDialog

func _ready():
	_apply_theme()

func _apply_theme():
	if not GameState: return
	
	# 尝试加载背景图
	if has_node("Background"):
		var bg_node = $Background
		var bg_path = "res://Assets/Backgrounds/main_menu_bg.png"
		if ResourceLoader.exists(bg_path):
			var tex = load(bg_path)
			if tex:
				bg_node.texture = tex
				# 如果有背景图，半透明遮罩可以淡一点
				if has_node("ColorRect"):
					$ColorRect.color = Color(0, 0, 0, 0.3)
	
	# 应用样式到所有按钮
	for node in find_children("", "Button", true, false):
		if node is Button:
			GameState.apply_button_style(node)

func _on_start_button_pressed():
	if GameState:
		GameState.slot_select_mode = "new"
	get_tree().change_scene_to_file("res://Scenes/SaveSlots.tscn")

func start_level_id(id: String):
	var level_database = load("res://Resources/EnemyLevels.tres")
	var idx = 0
	if level_database:
		var found = level_database.get_index_by_id(id)
		if found != -1: idx = found
	
	if GameState:
		GameState.selected_level_index = idx
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _on_level_select_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/LevelSelect.tscn")

func _on_barracks_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/Barracks.tscn")

func _on_unlock_all_button_pressed():
	if GameState and GameState.has_method("unlock_all_cards"):
		GameState.unlock_all_cards()
	if info_dialog:
		info_dialog.dialog_text = "已解锁全部卡牌"
		info_dialog.popup_centered()

func _on_clear_save_button_pressed():
	if clear_save_dialog:
		clear_save_dialog.popup_centered()

func _on_clear_save_dialog_confirmed():
	var err := OK
	if GameState and GameState.has_method("clear_save"):
		err = GameState.clear_save()
	if info_dialog:
		info_dialog.dialog_text = "已清除存档" if err == OK else "清除失败：%d" % err
		info_dialog.popup_centered()

func _on_quit_button_pressed():
	get_tree().quit()

func _on_load_button_pressed():
	if GameState:
		GameState.slot_select_mode = "load"
	get_tree().change_scene_to_file("res://Scenes/SaveSlots.tscn")

func _on_metashop_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MetaShop.tscn")
