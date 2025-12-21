extends Control

## 关卡选择界面。
## 约定：选中关卡索引写入 GameState.selected_level_index，战斗场景读取后生成敌军。

@export var level_database: LevelDatabase

@onready var list_container = $ScrollContainer/VBoxContainer

func _ready():
	_build_list()

func _build_list():
	if not level_database:
		if GameState and GameState.has_method("get_level_database"):
			level_database = GameState.get_level_database()
		if not level_database:
			level_database = load("res://Resources/EnemyLevels.tres")
	
	for child in list_container.get_children():
		child.queue_free()
	
	if not level_database or level_database.levels.is_empty():
		var label = Label.new()
		label.text = "没有关卡配置"
		list_container.add_child(label)
		return
	
	for i in range(level_database.levels.size()):
		var level: LevelConfig = level_database.levels[i]
		var btn = Button.new()
		btn.text = level.level_name
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(func():
			GameState.selected_level_index = i
			get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
		)
		list_container.add_child(btn)

func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
