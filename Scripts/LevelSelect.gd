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
			# 尝试获取剧情路径
			var dialogue_path = BattleManager.get_dialogue_path_by_id(level.level_id)
			if dialogue_path != "":
				var resource = load(dialogue_path)
				var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
				if resource and balloon_scene:
					# 传入 self 以便响应 start_level_id
					DialogueManager.show_dialogue_balloon_scene(balloon_scene, resource, "start", [self])
					return
			
			GameState.selected_level_index = i
			get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
		)
		list_container.add_child(btn)

func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func start_level_id(id: String):
	if not level_database: return
	
	var idx = level_database.get_index_by_id(id)
	if idx != -1:
		GameState.selected_level_index = idx
		get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
	else:
		push_error("Level ID not found: " + id)
