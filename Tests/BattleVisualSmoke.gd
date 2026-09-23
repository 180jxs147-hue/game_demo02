extends SceneTree

var failures: Array[String] = []
var battle: Node

func _initialize():
	_run.call_deferred()

func check(value: bool, message: String):
	if not value:
		failures.append(message)
		push_error(message)

func settle():
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw

func capture(file: String):
	await settle()
	root.get_texture().get_image().save_png("res://output/battle/" + file + ".png")

func _run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/battle"))
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	var state = root.get_node("GameState")
	state.current_cols = 3
	state.current_rows = 3
	battle = load("res://Scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	await settle()
	for child in battle.get_children():
		if child.get_script() and "Tutorial" in child.get_script().resource_path: child.free()
	for balloon in root.find_children("*", "CanvasLayer", true, false):
		if "Balloon" in str(balloon.name): balloon.hide()
	# Deterministic QA encounter; the isolated profile protects real saves.
	for container in [battle.units_container, battle.enemy_field.get_node("UnitsContainer")]:
		for unit in container.get_children(): unit.free()
	root.get_node("GridManager").clear_all()
	for spec in [[3, 3, 5, 5], [6, 4, 8, 7], [10, 8, 12, 10]]:
		root.get_node("GridManager").playable_columns = spec[0]
		root.get_node("GridManager").playable_rows = spec[1]
		battle.current_enemy_cols = spec[2]
		battle.current_enemy_rows = spec[3]
		battle.friendly_grid_vis.override_cols = spec[0]
		battle.friendly_grid_vis.override_rows = spec[1]
		battle.enemy_grid_vis.override_cols = spec[2]
		battle.enemy_grid_vis.override_rows = spec[3]
		battle.friendly_grid_vis.queue_redraw()
		battle.enemy_grid_vis.queue_redraw()
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
			root.size = resolution
			battle._apply_layout()
			await settle()
			check(is_equal_approx(battle.friendly_field.global_position.y, battle.enemy_field.global_position.y), "Shared first row")
			check(battle.friendly_field.global_scale == battle.enemy_field.global_scale, "Shared cell scale")
			var bottom: float = battle.enemy_field.global_position.y + spec[3] * 64 * battle.battlefield.scale.y
			check(bottom <= battle.bench_panel.position.y - 12, "Enemy board above dock")
			check(battle.enemy_field.global_position.x + spec[2] * 64 * battle.battlefield.scale.x <= 1600, "Enemy board in viewport")
		await capture("layout-%dx%d-vs-%dx%d" % spec)
	root.size = Vector2i(1600, 900)
	root.get_node("GridManager").playable_columns = 3
	root.get_node("GridManager").playable_rows = 3
	battle.current_enemy_cols = 5
	battle.current_enemy_rows = 5
	battle.friendly_grid_vis.override_cols = 3
	battle.friendly_grid_vis.override_rows = 3
	battle.enemy_grid_vis.override_cols = 5
	battle.enemy_grid_vis.override_rows = 5
	battle.friendly_grid_vis.queue_redraw()
	battle.enemy_grid_vis.queue_redraw()
	battle._apply_layout()
	for entry in [["camp", Vector2i(0, 0)], ["han_caiguan", Vector2i(1, 0)]]:
		var unit = battle.unit_scene.instantiate()
		unit.data = load("res://Resources/DataFiles/" + entry[0] + ".tres")
		battle.units_container.add_child(unit)
		unit.is_deployed = true
		unit.stored_grid_pos = entry[1]
		unit.position = Vector2(entry[1]) * 64
		root.get_node("GridManager").place_unit(unit, entry[1])
	for row in [0, 1]:
		var unit = battle.unit_scene.instantiate()
		unit.data = load("res://Resources/DataFiles/cangtian_qimin.tres")
		unit.faction = 1
		battle.enemy_field.get_node("UnitsContainer").add_child(unit)
		unit.is_deployed = true
		unit.stored_grid_pos = Vector2i(2, row)
		unit.position = Vector2(2, row) * 64
	battle.spawn_unit(load("res://Resources/DataFiles/junguo_bing.tres"))
	battle._refresh_bench_ui()
	battle.show_tooltip(load("res://Resources/DataFiles/junguo_bing.tres"))
	await capture("deployment")
	# The reserve grid is padded with empty Panel slots. The last child is
	# therefore not guaranteed to be a card; locate the wrapped CardSlot that
	# actually owns the drag signal and data property.
	var card: Node = null
	for candidate in battle.bench_grid.find_children("*", "Panel", true, false):
		if candidate.has_signal("drag_requested") and candidate.get("_unit_data") is UnitData:
			card = candidate
			break
	check(card != null, "Reserve card exists in padded grid")
	if card:
		card.drag_requested.emit(card.get("_unit_data"))
	await settle()
	var in_hand := false
	for unit in battle.units_container.get_children():
		if unit.get("in_hand") == true:
			in_hand = true
			unit.in_hand = false
			unit.is_dragging = false
			unit.set_bench_hidden(true)
	check(in_hand, "Reserve card starts original drag flow")
	battle._on_start_button_pressed()
	await create_timer(0.15).timeout
	check(not battle.get_node("CanvasLayer/HUD/StartButton").visible, "Start action hides on combat")
	battle.is_battle_started = false
	battle.battle_ended = true
	battle._show_finish_battle_button()
	await capture("victory")
	var finish: Button = battle.get_node("CanvasLayer/HUD/FinishBattleButton")
	check(finish.visible and finish.position.y > battle.bench_panel.position.y, "Finish action stays in dock")
	print("BATTLE SMOKE: PASS" if failures.is_empty() else "BATTLE SMOKE: FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
