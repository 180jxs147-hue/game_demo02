extends Node

const GUIDE_SCRIPT = preload("res://Scripts/Tutorials/TutorialGuide.gd")

enum Phase { INTRO, DEPLOY_FRONT, WRAP_UP }
var phase: Phase = Phase.INTRO
var guide
var _tutorial_skipped: bool = false

func start(bm: BattleManager) -> void:
	guide = GUIDE_SCRIPT.new()
	guide.name = "TutorialGuide"
	add_child(guide)
	guide.closed.connect(_on_guide_closed)
	guide.initialize(bm, "前排抗线与营帐补给")
	if not GridManager.unit_placed.is_connected(_on_unit_placed):
		GridManager.unit_placed.connect(_on_unit_placed)
	call_deferred("_run_tutorial")

func _run_tutorial() -> void:
	await guide.show_info_step(
		1, 3, "先稳住前排", "汉家材官适合站在前方承受攻击。先把前排站稳，再考虑后排输出。",
		"Battlefield/FriendlyField/GridVisualizer"
	)
	if not is_inside_tree() or _tutorial_skipped:
		return

	phase = Phase.DEPLOY_FRONT
	await guide.show_action_step(
		2, 3, "部署汉家材官", "从备战区拖出汉家材官，放到我方网格的前排。成功部署后自动继续。",
		"Battlefield/FriendlyField/GridVisualizer"
	)
	if not is_inside_tree() or _tutorial_skipped:
		return
	phase = Phase.WRAP_UP

	await guide.show_info_step(
		3, 3, "营帐与民力", "营帐可以持续提供民力。确认材官和营帐都准备好后，点击“开始战斗”。",
		"CanvasLayer/HUD/BenchPanel"
	)
	if not is_inside_tree() or _tutorial_skipped:
		return
	if is_inside_tree():
		queue_free()

func _on_unit_placed(unit: Node, _grid_pos: Vector2i) -> void:
	if phase != Phase.DEPLOY_FRONT or not is_instance_valid(unit):
		return
	if unit.get("faction") == 0:
		phase = Phase.WRAP_UP
		guide.complete_action_step()

func _on_guide_closed() -> void:
	_tutorial_skipped = true
	queue_free()
