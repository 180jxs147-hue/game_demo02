extends Control

@export var level_database: LevelDatabase

@onready var list_container = $ScrollContainer/VBoxContainer

func _ready():
	_build_list()

func _build_list():
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
