extends Control

## 关卡选择界面。
## 约定：选中关卡索引写入 GameState.selected_level_index，战斗场景读取后生成敌军。

@export var level_database: LevelDatabase

@onready var list_container = $ScrollContainer/VBoxContainer

func _ready():
	_apply_theme()
	_build_list()

func _apply_theme():
	if not GameState: return
	
	# 添加背景
	if not has_node("BgLayer"):
		var bg = ColorRect.new()
		bg.name = "BgLayer"
		bg.color = GameState.UI_COLOR_BG_DARK
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.show_behind_parent = true
		add_child(bg)
		move_child(bg, 0)
		
	# 返回按钮样式
	var back_btn = find_child("BackButton", true, false)
	if back_btn:
		GameState.apply_button_style(back_btn)

func _build_list():
	if not level_database:
		if GameState and GameState.has_method("get_level_database"):
			level_database = GameState.get_level_database()
		if not level_database:
			level_database = load("res://Resources/EnemyLevels.tres")
	
	for child in list_container.get_children():
		child.queue_free()
	
	# 增加间距
	list_container.add_theme_constant_override("separation", 10)
	
	if not level_database or level_database.levels.is_empty():
		var label = Label.new()
		label.text = "没有关卡配置"
		list_container.add_child(label)
		return
	
	for i in range(level_database.levels.size()):
		var level: LevelConfig = level_database.levels[i]
		
		# 使用 PanelContainer 制作卡片背景
		var card = PanelContainer.new()
		if GameState:
			card.add_theme_stylebox_override("panel", GameState.get_ui_style("level_card_bg"))
		
		var vbox = VBoxContainer.new()
		card.add_child(vbox)
		
		# 关卡标题
		var title_label = Label.new()
		title_label.text = level.level_name
		title_label.add_theme_color_override("font_color", GameState.UI_COLOR_ACCENT_GOLD if GameState else Color.GOLD)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vbox.add_child(title_label)
		
		# 开始按钮
		var btn = Button.new()
		btn.text = "出征"
		btn.custom_minimum_size = Vector2(0, 40)
		if GameState:
			GameState.apply_button_style(btn)
			
		btn.pressed.connect(func():
			play_level_intro(level.level_id)
		)
		vbox.add_child(btn)
		
		list_container.add_child(card)

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
	
func play_level_intro(id: String):
	print("[LevelSelect] Playing intro for: ", id)
	# 如果是选关界面播放了剧情，进战斗后就不应该再播一遍
	GameState.skip_intro = true
	
	var dialogue_path = BattleManager.get_dialogue_path_by_id(id)
	
	if dialogue_path != "":
		if ResourceLoader.exists(dialogue_path):
			var resource = load(dialogue_path)
			var balloon_scene = load("res://Scenes/Dialogue/CustomBalloon.tscn")
			if resource and balloon_scene:
				print("[LevelSelect] Showing dialogue balloon...")
				# 使用手动实例化方式，确保行为可控且能在 Pause 状态下运行（虽然 LevelSelect 通常不 Pause）
				var balloon = balloon_scene.instantiate()
				get_tree().root.add_child(balloon)
				balloon.start(resource, "start", [self])
				return
			else:
				push_error("[LevelSelect] Failed to load resource or balloon scene.")
		else:
			push_warning("[LevelSelect] Dialogue file not found at: " + dialogue_path)
			
	print("[LevelSelect] Skipping intro, starting level directly.")
	GameState.skip_intro = true
	start_level_id(id)
