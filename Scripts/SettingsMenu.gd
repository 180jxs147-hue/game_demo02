extends Control

func _ready():
	preload("res://Scripts/WarMenuSkin.gd").apply.call_deferred(self)
	theme = preload("res://Scripts/MenuVisuals.gd").create_theme()
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Noto Serif CJK SC", "serif"])
	$Content/Title.add_theme_font_override("font", title_font)
	$Content/Back.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn"))
	$Content.modulate.a = 0
	create_tween().tween_property($Content, "modulate:a", 1.0, 0.25)
