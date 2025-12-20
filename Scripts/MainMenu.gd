extends Control

func _on_start_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")

func _on_barracks_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/Barracks.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
