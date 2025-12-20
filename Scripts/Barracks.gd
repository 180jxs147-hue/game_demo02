extends Control

@export var player_library: CardLibrary
@onready var grid_container = $ScrollContainer/GridContainer

var card_slot_scene = preload("res://Scenes/CardSlot.tscn")

func _ready():
	_load_cards()

func _load_cards():
	if not player_library:
		print("Error: PlayerLibrary not assigned in Barracks")
		return
		
	# 清空现有显示
	for child in grid_container.get_children():
		child.queue_free()
		
	# 遍历库中的卡牌
	for data in player_library.collected_cards:
		var slot = card_slot_scene.instantiate()
		grid_container.add_child(slot)
		slot.setup(data)

func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
