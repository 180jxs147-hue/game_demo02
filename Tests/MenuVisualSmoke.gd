extends SceneTree

## Render real scenes and verify layout; run with the isolated UI QA runtime.
var failures: Array[String] = []
const OUT := "res://output/war-room"

func _initialize():
	_run.call_deferred()

func _settle():
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw

func _load_scene(path: String) -> Control:
	if current_scene:
		current_scene.free()
	var scene: Control = load(path).instantiate()
	root.add_child(scene)
	current_scene = scene
	return scene

func _capture(name: String):
	await _settle()
	_check(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK, "Save " + name)

func _check(condition: bool, message: String):
	if not condition:
		failures.append(message)
		push_error(message)

func _inside(control: Control, bounds: Rect2, context: String):
	_check(bounds.grow(2).encloses(control.get_global_rect()), context + " in bounds: " + str(control.get_path()))

func _run():
	print("QA_USER_DIR: ", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	var menu := _load_scene("res://Scenes/MainMenu.tscn")
	await _capture("main-menu")
	menu.get_node("MenuColumn/Footer/SettingsButton").pressed.emit()
	await _settle()
	var dialog: AcceptDialog = menu.get_node("SettingsDialog")
	_check(dialog.visible and dialog.borderless, "Settings has integrated chrome")
	var options: Control = dialog.get_node("DialogBody/Content")
	_check(options.get_node("Display/Resolution").get_item_count() == 2, "Resolution options retained")
	for dimensions in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		dialog.popup_centered()
		await _capture("settings-%dx%d" % [dimensions.x, dimensions.y])
		var rect := Rect2(Vector2.ZERO, Vector2(dialog.size))
		_inside(dialog.get_node("DialogBody"), rect, "Dialog body")
		_inside(dialog.get_ok_button(), rect, "Dialog action")
		_check(dialog.get_ok_button().size.x >= 132, "Dialog action has comfortable width")
		_check(not dialog.get_node("DialogBody").get_global_rect().intersects(dialog.get_ok_button().get_global_rect()), "Dialog content above actions")
	options.get_node("Audio/Volume").value = 65
	_check(options.get_node("Audio/Value").text == "65%", "Volume updates")
	var resolution: OptionButton = options.get_node("Display/Resolution")
	resolution.select(1)
	resolution.item_selected.emit(1)
	_check(root.size == Vector2i(1920, 1080), "Resolution action resizes window")
	resolution.select(0)
	resolution.item_selected.emit(0)
	resolution.show_popup()
	await _capture("settings-dropdown")
	_check(resolution.get_popup().visible, "Resolution dropdown opens")
	resolution.get_popup().hide()
	dialog.get_node("DialogBody").get_child(0).get_node("Close").pressed.emit()
	_check(not dialog.visible and not menu.get_node("ModalShade").visible, "Close dismisses modal shade")
	menu.get_node("Utilities/DevButton").pressed.emit()
	await _capture("developer")
	menu.get_node("DeveloperDialog").hide()
	menu.get_node("ClearSaveDialog").popup_centered()
	await _capture("confirmation")
	_check(menu.get_node("ClearSaveDialog").get_cancel_button().has_focus(), "Destructive dialog focuses cancel")
	menu.get_node("ClearSaveDialog").hide()

	root.size = Vector2i(1600, 900)
	root.get_node("GameState").run_gold = 20
	var camp := _load_scene("res://Scenes/CampShop.tscn")
	for dimensions in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		await _capture("camp-%dx%d" % [dimensions.x, dimensions.y])
		for path in ["Content/Infrastructure", "Content/Hospital", "Content/Recruitment"]:
			_inside(camp.get_node(path), camp.get_global_rect(), "Camp section")
		var infra: Control = camp.get_node("Content/Infrastructure")
		var hospital: Control = camp.get_node("Content/Hospital")
		_check(not infra.get_global_rect().intersects(hospital.get_global_rect()), "Camp sidebar sections separated")
		for item in camp.shop_container.get_children():
			_inside(item, camp.get_node("Content/Recruitment").get_global_rect(), "Recruit card")
		_check(camp.find_children("*", "VSeparator", true, false).is_empty(), "No camp divider lines")

	root.size = Vector2i(1600, 900)
	var barracks := _load_scene("res://Scenes/Barracks.tscn")
	barracks._on_all_units_button_pressed()
	for dimensions in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		await _capture("barracks-%dx%d" % [dimensions.x, dimensions.y])
		_inside(barracks.get_node("RootLayout"), barracks.get_global_rect(), "Barracks")
		var grid: GridContainer = barracks.all_grid
		_check(grid.columns >= 2 and grid.columns <= 4, "Readable card columns")
		for wrapper in grid.get_children():
			if wrapper.is_queued_for_deletion(): continue
			var slot: Control = wrapper.get_child(0)
			_check(slot.size.x * slot.scale.x <= wrapper.size.x + 1, "Card fits its grid cell")
		_check(barracks.all_page.get_node("Toolbar").size.x <= barracks.all_page.size.x + 1, "Filters fit page")
	barracks.all_search.text = "三河"
	await _settle()
	_check(barracks.all_grid.get_child_count() > 0, "Card search works")
	barracks._on_tags_button_pressed()
	await _capture("barracks-tags")
	barracks._on_synergy_button_pressed()
	await _capture("barracks-synergy")

	for scene in ["SettingsMenu", "SaveSlots", "MetaShop", "LevelSelect"]:
		_load_scene("res://Scenes/" + scene + ".tscn")
		await _capture(scene.to_lower())
	print("WAR_ROOM_SMOKE: ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
