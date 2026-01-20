extends Control

# Paths
const LEVELS_DIR = "res://Resources/Levels/"
const UNITS_DIR = "res://Resources/DataFiles/"

# References
@onready var level_list: ItemList = $MainLayout/ContentSplit/LeftPanel/LevelList
@onready var unit_container: HBoxContainer = $MainLayout/BottomPanel/ScrollContainer/UnitContainer
@onready var grid_root: Node2D = $MainLayout/ContentSplit/GridContainer/GridRoot
@onready var grid_overlay: Control = $MainLayout/ContentSplit/GridContainer/GridOverlay
@onready var save_btn: Button = $MainLayout/TopBar/SaveButton
@onready var feedback_label: Label = $MainLayout/TopBar/FeedbackLabel

const UnitCard = preload("res://Scripts/Editor/UnitCard.gd")
const EditorGridInput = preload("res://Scripts/Editor/EditorGridInput.gd")
const DraggableUnitVisual = preload("res://Scripts/Editor/DraggableUnitVisual.gd")
const CardSlotScene = preload("res://Scenes/CardSlot.tscn")
const EditorCardSlotScript = preload("res://Scripts/Editor/EditorCardSlot.gd")

# State
var current_level_path: String = ""
var current_level_config: LevelConfig = null
var selected_unit_path: String = ""
var current_units_visuals: Dictionary = {} # Vector2i -> Node2D (Sprite/Label)

func _ready():
	refresh_file_list()
	refresh_unit_list()
	
	# Connect signals
	level_list.item_selected.connect(_on_level_selected)
	save_btn.pressed.connect(_on_save_pressed)
	
	# Setup grid input
	grid_overlay.set_script(EditorGridInput)
	grid_overlay.setup(grid_root)
	grid_overlay.place_unit_requested.connect(_on_place_unit_requested)
	grid_overlay.move_unit_requested.connect(_on_move_unit_requested)
	grid_overlay.grid_clicked.connect(_on_grid_clicked)

func refresh_file_list():
	level_list.clear()
	var dir = DirAccess.open(LEVELS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				level_list.add_item(file_name)
			file_name = dir.get_next()
		level_list.sort_items_by_text()

func refresh_unit_list():
	for child in unit_container.get_children():
		child.queue_free()
		
	var dir = DirAccess.open(UNITS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				# Try to load to get icon or name
				var full_path = UNITS_DIR + file_name
				var res = load(full_path)
				
				if res and res is UnitData:
					_create_unit_card_button(res, full_path)
					
			file_name = dir.get_next()

func _create_unit_card_button(unit_data: UnitData, full_path: String):
	var card = CardSlotScene.instantiate()
	card.set_script(EditorCardSlotScript)
	
	# Connect signal before adding to tree or after? 
	# CardSlot script connects its own signals in _ready.
	# We want to connect the 'pressed' signal from CardSlot to our handler.
	card.pressed.connect(func(_data): _on_unit_button_clicked(full_path))
	
	unit_container.add_child(card)
	
	# Setup must be called after adding to tree if it depends on ready, 
	# but CardSlot.gd's setup() calls _apply_card_skin which checks is_node_ready().
	# So we call setup after add_child, or wait for ready.
	# Actually CardSlot.gd says: if not is_node_ready(): return
	# So we MUST call setup after adding to tree.
	card.setup(unit_data)

func _on_unit_button_clicked(path: String):
	selected_unit_path = path
	feedback_label.text = "Selected Unit: " + path.get_file()

func _on_level_selected(index: int):
	var file_name = level_list.get_item_text(index)
	current_level_path = LEVELS_DIR + file_name
	load_level(current_level_path)

func _on_unit_selected(index: int):
	# Deprecated
	pass

func load_level(path: String):
	current_level_config = load(path)
	if not current_level_config:
		feedback_label.text = "Failed to load level!"
		return
	
	feedback_label.text = "Loaded: " + path.get_file()
	draw_level()

func draw_level():
	# Clear existing visuals
	for child in grid_root.get_children():
		child.queue_free()
	current_units_visuals.clear()
	
	if not current_level_config:
		return

	# Draw grid lines (Visual only)
	_draw_grid_cells()
	
	# Spawn units
	for spawn in current_level_config.enemy_units:
		if spawn and spawn.unit_data:
			_create_unit_visual(spawn.unit_data, spawn.grid_pos)

func _draw_grid_cells():
	for x in range(current_level_config.grid_width):
		for y in range(current_level_config.grid_height):
			var cell = ReferenceRect.new()
			cell.size = Vector2(GameConst.GRID_SIZE, GameConst.GRID_SIZE)
			cell.position = Vector2(x, y) * GameConst.GRID_SIZE
			cell.border_color = Color(0.5, 0.5, 0.5, 0.3)
			cell.editor_only = false
			cell.border_width = 2.0
			grid_root.add_child(cell)

func _create_unit_visual(unit_data: UnitData, grid_pos: Vector2i):
	var marker = DraggableUnitVisual.new()
	marker.color = Color(0.8, 0.2, 0.2, 0.5) # Red for enemies, semi-transparent
	marker.position = Vector2(grid_pos) * GameConst.GRID_SIZE
	marker.setup(grid_pos, unit_data)
	
	grid_root.add_child(marker)
	current_units_visuals[grid_pos] = marker

func _on_grid_input(event: InputEvent):
	# Deprecated, handled by EditorGridInput signals
	pass

func _on_place_unit_requested(grid_pos: Vector2i, unit_data: Resource):
	if not _is_valid_grid_pos(grid_pos):
		return
	
	if unit_data is UnitData:
		_place_unit(grid_pos, unit_data)

func _on_move_unit_requested(from_pos: Vector2i, to_pos: Vector2i):
	if not _is_valid_grid_pos(to_pos):
		return
		
	# Find unit data at from_pos
	var unit_spawn = _get_spawn_at(from_pos)
	if not unit_spawn:
		return
		
	var data = unit_spawn.unit_data
	
	# Remove from old pos
	_remove_unit(from_pos)
	
	# Place at new pos
	_place_unit(to_pos, data)

func _on_grid_clicked(grid_pos: Vector2i, button_index: int):
	if not _is_valid_grid_pos(grid_pos):
		return
		
	if button_index == MOUSE_BUTTON_LEFT:
		if selected_unit_path == "":
			feedback_label.text = "Select a unit first!"
			return
		_place_unit(grid_pos)
	elif button_index == MOUSE_BUTTON_RIGHT:
		_remove_unit(grid_pos)

func _is_valid_grid_pos(grid_pos: Vector2i) -> bool:
	if not current_level_config:
		return false
	return grid_pos.x >= 0 and grid_pos.x < current_level_config.grid_width and \
		   grid_pos.y >= 0 and grid_pos.y < current_level_config.grid_height

func _get_spawn_at(grid_pos: Vector2i) -> UnitSpawn:
	if not current_level_config:
		return null
	for spawn in current_level_config.enemy_units:
		if spawn.grid_pos == grid_pos:
			return spawn
	return null

func _place_unit(grid_pos: Vector2i, specific_data: UnitData = null):
	# Remove existing if any
	_remove_unit(grid_pos)
	
	var unit_data = specific_data
	
	# If no specific data provided, try to load from selection
	if not unit_data:
		if selected_unit_path == "":
			return
		unit_data = load(selected_unit_path)
	
	if not unit_data:
		return
		
	# Update Resource
	var spawn = UnitSpawn.new()
	spawn.unit_data = unit_data
	spawn.grid_pos = grid_pos
	current_level_config.enemy_units.append(spawn)
	
	# Update Visual
	_create_unit_visual(unit_data, grid_pos)

func _remove_unit(grid_pos: Vector2i):
	# Remove from visuals
	if current_units_visuals.has(grid_pos):
		current_units_visuals[grid_pos].queue_free()
		current_units_visuals.erase(grid_pos)
	
	# Remove from data
	var to_remove = -1
	for i in range(current_level_config.enemy_units.size()):
		var s = current_level_config.enemy_units[i]
		if s.grid_pos == grid_pos:
			to_remove = i
			break
	if to_remove != -1:
		current_level_config.enemy_units.remove_at(to_remove)

func _on_save_pressed():
	if current_level_config and current_level_path != "":
		var err = ResourceSaver.save(current_level_config, current_level_path)
		if err == OK:
			feedback_label.text = "Saved: " + current_level_path.get_file()
		else:
			feedback_label.text = "Error saving: " + str(err)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
