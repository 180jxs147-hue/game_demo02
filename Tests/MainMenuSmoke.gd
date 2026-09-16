extends SceneTree

var failures: Array[String] = []
var output_dir := "res://output/menu-direction"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var packed := load("res://Scenes/MainMenu.tscn") as PackedScene
	if not packed:
		push_error("Main menu failed to load")
		quit(1)
		return
	var menu := packed.instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var prefix := "before" if baseline else "after"
	for dimensions in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		_check(screenshot.get_width() == dimensions.x, "Screenshot width")
		var destination := "%s/%s-%dx%d.png" % [output_dir, prefix, dimensions.x, dimensions.y]
		_check(screenshot.save_png(destination) == OK, "Save screenshot " + destination)
		if not baseline:
			_check_layout(menu)
	if not baseline:
		_check(menu.get_node("Background").texture != null, "Background loaded")
		var start := menu.get_node("MenuColumn/Actions/StartButton") as Button
		start.grab_focus()
		await process_frame
		_check(start.has_focus(), "Keyboard focus")
		menu.get_node("MenuColumn/Footer/SettingsButton").pressed.emit()
		await process_frame
		_check(menu.get_node("SettingsDialog").visible, "Settings opens")
		_check(menu.get_node("ModalShade").visible, "Modal backdrop opens")
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(output_dir + "/after-settings.png") == OK, "Settings screenshot")
		var game_state := root.get_node("GameState")
		var original_profile: String = game_state.current_display_profile
		var resolution: OptionButton = menu.get_node("SettingsDialog/DialogBody/Content/Display/Resolution")
		var target_index := 1 if resolution.selected == 0 else 0
		resolution.select(target_index)
		resolution.item_selected.emit(target_index)
		await process_frame
		_check(game_state.current_display_profile != original_profile, "Resolution changes")
		_check(resolution.selected == target_index, "Resolution selection updates")
		game_state.apply_display_profile(original_profile)
		menu.get_node("SettingsDialog").hide()
		menu.get_node("Utilities/DevButton").pressed.emit()
		await process_frame
		_check(menu.get_node("DeveloperDialog").visible, "Developer tools opens")
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(output_dir + "/after-developer.png") == OK, "Developer screenshot")
		menu.get_node("DeveloperDialog").hide()
		_check(not menu.get_node("ModalShade").visible, "Modal backdrop closes")
		for button in menu.find_children("*", "Button", true, false):
			if button.is_visible_in_tree():
				_check(not button.get_signal_connection_list("pressed").is_empty(), "Connected: " + str(button.name))
		# Load mode only opens the picker; it must not choose a slot or write a save.
		menu.get_node("MenuColumn/Actions/LoadButton").pressed.emit()
		await process_frame
		await process_frame
		_check(current_scene != null and current_scene.scene_file_path == "res://Scenes/SaveSlots.tscn", "Load destination")
		_check(game_state.slot_select_mode == "load", "Load mode")
		change_scene_to_file("res://Scenes/MainMenu.tscn")
		await process_frame
		await process_frame
		current_scene.get_node("MenuColumn/Actions/StartButton").pressed.emit()
		await process_frame
		await process_frame
		_check(current_scene != null and current_scene.scene_file_path == "res://Scenes/SaveSlots.tscn", "New game destination")
		_check(game_state.slot_select_mode == "new", "New game mode")
	print("MENU_SMOKE: ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check_layout(menu: Control) -> void:
	var bounds := menu.get_global_rect()
	var buttons: Array[Control] = []
	for node in menu.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and not node.get_parent() is Window:
			buttons.append(node)
			_check(bounds.encloses(node.get_global_rect()), "Button in viewport: " + str(node.name))
			_check(node.size.x >= node.get_minimum_size().x, "Button width: " + str(node.name))
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			_check(not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect()), "Overlapping buttons")
	var title := menu.get_node("MenuColumn/Header/TitleRow/Title") as Label
	var seal := menu.get_node("MenuColumn/Header/TitleRow/Seal") as Control
	_check(not title.get_global_rect().intersects(seal.get_global_rect()), "Title and seal separation")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
