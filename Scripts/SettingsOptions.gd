extends VBoxContainer

@onready var resolution: OptionButton = $Display/Resolution
@onready var volume: HSlider = $Audio/Volume
@onready var volume_value: Label = $Audio/Value

func _ready():
	theme = preload("res://Scripts/MenuVisuals.gd").create_theme()
	resolution.add_item("1600 × 900", 0)
	resolution.add_item("1920 × 1080", 1)
	resolution.item_selected.connect(_select_resolution)
	volume.value_changed.connect(_change_volume)
	$Text/Speed.add_item("标准")
	refresh()

func refresh():
	resolution.select(1 if GameState.current_display_profile == GameState.DISPLAY_PROFILE_1080P else 0)
	volume.set_value_no_signal(GameState.master_volume_percent)
	volume_value.text = "%d%%" % roundi(volume.value)

func _select_resolution(index: int):
	GameState.apply_display_profile(GameState.DISPLAY_PROFILE_1080P if index == 1 else GameState.DISPLAY_PROFILE_900P)

func _change_volume(value: float):
	GameState.apply_master_volume(value)
	volume_value.text = "%d%%" % roundi(value)
