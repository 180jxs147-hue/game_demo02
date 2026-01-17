extends Control

@onready var currency_label = $VBox/Header/CurrencyLabel
@onready var save_btn = $VBox/Header/Buttons/SaveBtn
@onready var load_btn = $VBox/Header/Buttons/LoadBtn
@onready var exit_btn = $VBox/Header/Buttons/ExitBtn
@onready var u1_buy = $VBox/Upgrades/U1/U1Buy
@onready var u2_buy = $VBox/Upgrades/U2/U2Buy
@onready var u3_buy = $VBox/Upgrades/U3/U3Buy

func _ready():
	_refresh()
	if save_btn:
		save_btn.pressed.connect(func():
			if GameState and GameState.has_method("save_all"):
				var rc = GameState.save_all()
				_refresh()
		)
	if load_btn:
		load_btn.pressed.connect(func():
			if GameState and GameState.has_method("load_all"):
				GameState.load_all()
				_refresh()
		)
	if exit_btn:
		exit_btn.pressed.connect(func():
			get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
		)
	if u1_buy:
		u1_buy.pressed.connect(func():
			_try_buy("start_card_junguo_bing", 3)
		)
	if u2_buy:
		u2_buy.pressed.connect(func():
			_try_buy("max_manpower_plus_10", 5)
		)
	if u3_buy:
		u3_buy.pressed.connect(func():
			_try_buy("bench_columns_plus_1", 5)
		)

func _try_buy(key: String, cost: int):
	if not GameState: return
	if GameState.has_upgrade(key):
		return
	var ok = GameState.purchase_upgrade(key, cost)
	if ok:
		_refresh()

func _refresh():
	if GameState:
		currency_label.text = "军资: %d" % GameState.get_meta_currency()
		if u1_buy:
			u1_buy.disabled = GameState.has_upgrade("start_card_junguo_bing")
			u1_buy.text = "已购买" if u1_buy.disabled else "购买"
		if u2_buy:
			u2_buy.disabled = GameState.has_upgrade("max_manpower_plus_10")
			u2_buy.text = "已购买" if u2_buy.disabled else "购买"
		if u3_buy:
			u3_buy.disabled = GameState.has_upgrade("bench_columns_plus_1")
			u3_buy.text = "已购买" if u3_buy.disabled else "购买"
