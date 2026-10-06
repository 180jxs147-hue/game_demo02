extends Control

## 主菜单：负责场景跳转与存档清理入口。

@onready var clear_save_dialog = $ClearSaveDialog
@onready var info_dialog = $InfoDialog

func _ready():
	_apply_theme()

func _apply_theme():
	var visuals = preload("res://Scripts/MenuVisuals.gd")
	theme = visuals.create_theme()
	for button in $MenuColumn/Actions.get_children():
		button.add_theme_font_size_override("font_size", 23)
		button.add_theme_stylebox_override("normal", _button_style(Color.TRANSPARENT))
		button.add_theme_stylebox_override("hover", visuals.inset(Color(1.5, 1.3, 1.05)))
		button.add_theme_stylebox_override("pressed", visuals.inset(Color("a68c6c")))
	for dialog in [$SettingsDialog, $DeveloperDialog, $ClearSaveDialog, $InfoDialog]:
		preload("res://Scripts/MenuVisuals.gd").style_dialog(dialog, dialog == $ClearSaveDialog)
		dialog.get_ok_button().text = "关闭" if dialog != $ClearSaveDialog else "确认"
		dialog.get_ok_button().custom_minimum_size = Vector2(120, 44)
		dialog.visibility_changed.connect(_refresh_modal_shade)
	$ClearSaveDialog.get_cancel_button().text = "取消"
	var start: Button = $MenuColumn/Actions/StartButton
	start.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "pressed"]:
		start.remove_theme_stylebox_override(state)
	visuals.primary(start)
	$ClearSaveDialog.get_ok_button().text = "确认清除"

func _refresh_modal_shade():
	$ModalShade.visible = $SettingsDialog.visible or $DeveloperDialog.visible or $ClearSaveDialog.visible or $InfoDialog.visible

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 30.0
	style.content_margin_right = 24.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _on_settings_button_pressed():
	var content = $SettingsDialog.find_child("Content", true, false)
	if content and content.has_method("refresh"):
		content.refresh()
	$SettingsDialog.popup_centered()

func _on_developer_button_pressed():
	$DeveloperDialog.popup_centered()

func _on_editor_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/LevelEditor.tscn")

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
	$DeveloperDialog.hide()
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
