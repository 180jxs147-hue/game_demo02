extends Control

## 主菜单：负责场景跳转与存档清理入口。

@onready var clear_save_dialog = $ClearSaveDialog
@onready var info_dialog = $InfoDialog

func _on_start_button_pressed():
	if GameState:
		GameState.load_progress()
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _on_level_select_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/LevelSelect.tscn")

func _on_barracks_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/Barracks.tscn")

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
