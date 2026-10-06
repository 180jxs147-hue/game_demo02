extends Control

@onready var gold_label = $Header/GoldLabel
@onready var next_level_btn = $Header/NextLevelBtn

# Infrastructure
@onready var btn_expand_rows = $Content/Infrastructure/Grid/ExpandRowsBtn
@onready var btn_expand_cols = $Content/Infrastructure/Grid/ExpandColsBtn
@onready var btn_max_manpower = $Content/Infrastructure/Grid/MaxManpowerBtn

# Hospital
@onready var hospital_container = $Content/Hospital/Scroll/VBox
var hospital_slot_scene = preload("res://Scenes/CardSlot.tscn")

# Recruitment
@onready var shop_container = $Content/Recruitment/ShopContainer
@onready var btn_refresh = $Content/Recruitment/Header/RefreshBtn
var shop_cards: Array[UnitData] = []
var shop_card_scene = preload("res://Scenes/CardSlot.tscn")
var balloon_scene = preload("res://Scenes/Dialogue/CustomBalloon.tscn")

const COST_EXPAND_ROWS = 10
const COST_EXPAND_COLS = 10
const COST_MAX_MANPOWER = 5
const COST_HEAL = 2
const COST_REFRESH = 1
const COST_CARD_BASE = 3

var current_shop_pool = null
var current_refresh_cost = COST_REFRESH
var current_base_card_cost = COST_CARD_BASE

func _load_shop_config():
	if not GameState: return
	var level_db = GameState.get_level_database()
	if not level_db: return
	
	var config_to_use = null
	var shop_pool_id_to_use = ""

	# Priority 1: Explicit override from story/dialogue
	if "next_shop_pool_id" in GameState and GameState.next_shop_pool_id != "":
		shop_pool_id_to_use = GameState.next_shop_pool_id
		# Clear it so it doesn't persist forever, unless that's desired.
		# For now, let's clear it to act as a one-time override.
		GameState.next_shop_pool_id = ""
	
	if shop_pool_id_to_use == "":
		# Priority 2: Pending level (from story) -> Current level (post-battle)
		if GameState.next_level_id_from_camp != "":
			var idx = level_db.get_index_by_id(GameState.next_level_id_from_camp)
			if idx != -1:
				config_to_use = level_db.get_level(idx)
		
		if not config_to_use:
			var idx = GameState.selected_level_index
			config_to_use = level_db.get_level(idx)
		
		if config_to_use and "shop_pool_id" in config_to_use:
			shop_pool_id_to_use = config_to_use.shop_pool_id

	if shop_pool_id_to_use != "":
		var shop_db = load("res://Resources/ShopPoolDatabase.tres")
		if shop_db:
			current_shop_pool = shop_db.get_pool_by_id(shop_pool_id_to_use)

	if current_shop_pool:
		current_refresh_cost = current_shop_pool.refresh_cost
		current_base_card_cost = current_shop_pool.base_card_cost
	else:
		current_refresh_cost = COST_REFRESH
		current_base_card_cost = COST_CARD_BASE
		
	# Apply Relic Discount
	if GameState:
		var discount = GameState.get_relic_effect_value("shop_discount")
		current_base_card_cost = max(1, current_base_card_cost - int(discount))
		# current_refresh_cost = max(1, current_refresh_cost - int(discount * 0.5)) # Optional

func _ready():
	preload("res://Scripts/WarMenuSkin.gd").apply.call_deferred(self)
	print("CampShop: _ready called")
	get_tree().paused = false # Ensure game is not paused from previous state (e.g. Dialogue)
	_load_shop_config()
	_refresh_ui()
	_refresh_hospital()
	_refresh_shop(true) # Initial refresh (free or auto)
	
	if next_level_btn:
		print("CampShop: Connecting NextLevelBtn")
		if next_level_btn.is_connected("pressed", _on_next_level_pressed):
			next_level_btn.pressed.disconnect(_on_next_level_pressed)
		next_level_btn.pressed.connect(_on_next_level_pressed)
	else:
		push_error("CampShop: NextLevelBtn not found!")
		
	if btn_refresh:
		btn_refresh.pressed.connect(_on_refresh_shop_pressed)
		
	if btn_expand_rows:
		btn_expand_rows.pressed.connect(func(): _try_upgrade("rows", get_expand_cost_rows()))
	if btn_expand_cols:
		btn_expand_cols.pressed.connect(func(): _try_upgrade("cols", get_expand_cost_cols()))
	if btn_max_manpower:
		btn_max_manpower.pressed.connect(func(): _try_upgrade("manpower", COST_MAX_MANPOWER))
	
	_setup_save_button()
	_setup_back_button()

func _setup_back_button():
	var header = $Header
	if header:
		var btn_back = Button.new()
		btn_back.name = "BackBtn"
		btn_back.text = "返回主菜单"
		btn_back.custom_minimum_size = Vector2(120, 0)
		if GameState:
			GameState.apply_button_style(btn_back)
		header.add_child(btn_back)
		btn_back.pressed.connect(_on_back_pressed)

func _on_back_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _setup_save_button():
	var header = $Header
	if header:
		var btn_save = Button.new()
		btn_save.text = "保存进度"
		btn_save.custom_minimum_size = Vector2(120, 0)
		if GameState:
			GameState.apply_button_style(btn_save)
		
		# Insert before NextLevelBtn
		if next_level_btn:
			header.add_child(btn_save)
			header.move_child(btn_save, next_level_btn.get_index())
		else:
			header.add_child(btn_save)
			
		btn_save.pressed.connect(_on_save_pressed)

func _on_save_pressed():
	var save_scene = preload("res://Scenes/SaveSlots.tscn").instantiate()
	save_scene.is_popup = true
	save_scene.mode = "save"
	add_child(save_scene)

func get_expand_cost_rows() -> int:
	var upgrades_done = max(0, GameState.current_rows - 3) if GameState else 0
	if upgrades_done == 0: return 6
	elif upgrades_done == 1: return 10
	else: return 16

func get_expand_cost_cols() -> int:
	var upgrades_done = max(0, GameState.current_cols - 2) if GameState else 0
	if upgrades_done == 0: return 6
	elif upgrades_done == 1: return 10
	else: return 16

func _refresh_ui():
	if not GameState: return
	gold_label.text = "当前军资: %d" % GameState.get_run_gold()
	
	var cost_rows = get_expand_cost_rows()
	var cost_cols = get_expand_cost_cols()
	
	# Update buttons state
	if btn_expand_rows:
		btn_expand_rows.text = "扩充军阵(行)\n消耗: %d" % cost_rows
		btn_expand_rows.disabled = GameState.get_run_gold() < cost_rows or GameState.current_rows >= GameConst.MAP_ROWS
	
	if btn_expand_cols:
		btn_expand_cols.text = "扩充军阵(列)\n消耗: %d" % cost_cols
		btn_expand_cols.disabled = GameState.get_run_gold() < cost_cols or GameState.current_cols >= GameConst.MAP_COLUMNS
		
	if btn_max_manpower:
		btn_max_manpower.text = "粮草征收(上限+10)\n消耗: %d" % COST_MAX_MANPOWER
		btn_max_manpower.disabled = GameState.get_run_gold() < COST_MAX_MANPOWER
		
	if btn_refresh:
		btn_refresh.text = "刷新商品 (%d)" % current_refresh_cost
		btn_refresh.disabled = GameState.get_run_gold() < current_refresh_cost

func _try_upgrade(type: String, cost: int):
	if not GameState: return
	if GameState.spend_run_gold(cost):
		if type == "rows":
			GameState.current_rows = min(GameState.current_rows + 1, GameConst.MAP_ROWS)
		elif type == "cols":
			GameState.current_cols = min(GameState.current_cols + 1, GameConst.MAP_COLUMNS)
		elif type == "manpower":
			# Manpower cap is usually defined in BattleManager.
			# We might need to store a bonus in GameState or increase base.
			# Currently BattleManager.max_manpower = 50.0
			# Let's add a "max_manpower_bonus" in GameState for run-specific upgrades
			# Wait, GameState already has meta upgrades. We need run upgrades.
			# Let's add 'run_manpower_bonus' to GameState.
			GameState.add_run_manpower_bonus(10)
			
		# GameState.save_progress() # Deprecated: RAM only now
		# GameState.trigger_autosave() # Deprecated: Only Autosave at Level Start, not shop purchase
		_refresh_ui()

func _refresh_hospital():
	# Clear
	for c in hospital_container.get_children():
		c.queue_free()
		
	if not GameState: return
	var lib = GameState.load_player_library()
	if not lib: return
	GameState.set_current_library(lib)
	
	var injured_found = false
	for unit in lib.collected_cards:
		if unit.is_injured:
			injured_found = true
			var hbox = HBoxContainer.new()
			
			var lbl = Label.new()
			lbl.text = unit.name
			lbl.custom_minimum_size = Vector2(100, 0)
			hbox.add_child(lbl)
			
			var btn = Button.new()
			btn.text = "治疗 (-%d)" % COST_HEAL
			if GameState.get_run_gold() < COST_HEAL:
				btn.disabled = true
			
			btn.pressed.connect(_heal_injured_unit.bind(unit))
			hbox.add_child(btn)
			
			hospital_container.add_child(hbox)
			
	if not injured_found:
		var lbl = Label.new()
		lbl.text = "没有受伤单位"
		lbl.add_theme_color_override("font_color", Color.GRAY)
		hospital_container.add_child(lbl)

func _heal_injured_unit(unit: UnitData) -> void:
	if not is_instance_valid(unit) or not unit.is_injured:
		return
	if GameState.spend_run_gold(COST_HEAL):
		unit.is_injured = false
		GameState.trigger_autosave()
		_refresh_ui()
		_refresh_hospital()

func _refresh_shop(free: bool = false):
	if not free:
		if not GameState.spend_run_gold(current_refresh_cost):
			return
	
	_refresh_ui()
	
	# Clear
	for c in shop_container.get_children():
		c.queue_free()
		
	shop_cards.clear()
	
	# Generate cards
	var generated_cards: Array[Dictionary] = [] # { "unit": UnitData, "cost": int }
	
	if current_shop_pool and not current_shop_pool.entries.is_empty():
		for i in range(3):
			var picked = _pick_weighted(current_shop_pool.entries)
			if picked and picked.has("unit"):
				var unit = picked.get("unit")
				# If ShopPool entry has specific cost, use it; otherwise use rarity based price
				var cost = picked.get("cost", -1)
				if cost < 0:
					cost = GameState.get_card_buy_price(unit.rarity)
				generated_cards.append({ "unit": unit, "cost": cost })
	else:
		# Random 3 cards (Fallback)
		var db = GameState.get_unit_database()
		if db and not db.units.is_empty(): 
			for i in range(3):
				var card = db.units.pick_random()
				var cost = GameState.get_card_buy_price(card.rarity)
				generated_cards.append({ "unit": card, "cost": cost })
	
	for card_info in generated_cards:
		var card = card_info.unit
		var cost = card_info.cost
		
		shop_cards.append(card)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		vbox.add_theme_constant_override("separation", 16)
		
		# Slot display
		var slot = shop_card_scene.instantiate()
		if slot.has_method("setup"):
			slot.setup(card)
		vbox.add_child(slot)
		
		# Buy button
		var btn = Button.new()
		# var cost = COST_CARD_BASE # Removed local var
		btn.text = "购买 (%d)" % cost
		btn.custom_minimum_size.y = 48
		preload("res://Scripts/MenuVisuals.gd").primary(btn)
		if GameState.get_run_gold() < cost:
			btn.disabled = true
			
		btn.pressed.connect(func():
			if GameState.spend_run_gold(cost):
				# Add to library
				var lib = GameState.load_player_library()
				if lib:
					lib.collected_cards.append(card.duplicate())
					GameState.set_current_library(lib)
					GameState.trigger_autosave()
				
				# Disable button
				btn.disabled = true
				btn.text = "已购买"
				_refresh_ui()
		)
		vbox.add_child(btn)
		
		shop_container.add_child(vbox)

func _pick_weighted(entries: Array) -> Dictionary:
	var total_weight = 0.0
	for e in entries:
		total_weight += e.get("prob", 0.0)
	
	if total_weight <= 0.0: return {}

	var r = randf() * total_weight
	var acc = 0.0
	for e in entries:
		acc += e.get("prob", 0.0)
		if r <= acc:
			return e
	return entries.back() if not entries.is_empty() else {}

func _on_refresh_shop_pressed():
	_refresh_shop(false)

func _on_next_level_pressed():
	print("CampShop: Next Level Pressed")
	# 检查是否有挂起的目标关卡（从剧情跳转过来的情况）
	var target_level_id = ""
	var is_from_dialogue = false
	
	# Prevent loop: If pending ID is same as current level, ignore it
	var level_db = GameState.get_level_database()
	if GameState.next_level_id_from_camp != "":
		var pending_id = GameState.next_level_id_from_camp
		var current_level_id = ""
		if level_db:
			var lvl = level_db.get_level(GameState.selected_level_index)
			if lvl: current_level_id = lvl.level_id
			
		if pending_id == current_level_id:
			print("CampShop: Pending ID same as current. Ignoring to prevent loop.")
			GameState.next_level_id_from_camp = ""
		else:
			target_level_id = pending_id
			is_from_dialogue = true
			print("CampShop: Using next_level_id_from_camp: ", target_level_id)
	
	if target_level_id == "":
		# 正常流程：当前关卡的下一关
		if not level_db: 
			print("CampShop: No level database")
			return
		
		var current_idx = GameState.selected_level_index
		var next_idx = current_idx + 1
		print("CampShop: Calculating next level. Current: ", current_idx, " Next: ", next_idx)
		
		if next_idx < level_db.levels.size():
			var next_level_data = level_db.levels[next_idx]
			target_level_id = next_level_data.level_id
			# 设置 pending ID 以便 BattleManager 播放剧情
			GameState.next_level_id_from_camp = target_level_id
			print("CampShop: Calculated next level ID: ", target_level_id)
	
	if target_level_id != "":
		# 更新 GameState 索引，确保加载正确的环境
		if level_db:
			var idx = level_db.get_index_by_id(target_level_id)
			if idx != -1:
				GameState.selected_level_index = idx
				# GameState.save_progress() # Deprecated: RAM only
				print("CampShop: Saved progress. Selected Index: ", idx)
		
		# 如果是从剧情跳转过来的（例如 1-0-2 -> Camp -> 1-0-2），
		# 我们希望跳过该关卡的 Intro（因为已经播过了）。
		# 强制设置 skip_intro = true，防止因存档或其他原因丢失标记。
		if is_from_dialogue:
			GameState.skip_intro = true
			print("CampShop: Forcing skip_intro = true for pending level")
		
		print("CampShop: Changing scene to Battle.tscn")
		get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
	else:
		# Game Over / Win
		print("CampShop: No target level (Win/Game Over). To MainMenu.")
		get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func start_level_id(id: String):
	# 此函数供对话脚本调用，或无剧情时直接调用
	var level_db = GameState.get_level_database()
	if not level_db: return
	
	var idx = level_db.get_index_by_id(id)
	if idx != -1:
		GameState.selected_level_index = idx
		# 标记跳过 BattleManager 内部的开场剧情检查，因为我们已经在 CampShop 处理过了（或者本身就没有）
		GameState.skip_intro = true
		# GameState.save_progress() # Deprecated: RAM only
		get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
	else:
		push_error("Level ID not found: " + id)
