extends Node

const GUIDE_SCRIPT = preload("res://Scripts/Tutorials/TutorialGuide.gd")

enum Phase { INTRO, DEPLOY_UNIT, WRAP_UP }
var phase: Phase = Phase.INTRO
var guide
var _tutorial_skipped: bool = false

func start(bm: BattleManager) -> void:
	guide = GUIDE_SCRIPT.new()
	guide.name = "TutorialGuide"
	add_child(guide)
	guide.closed.connect(_on_guide_closed)
	guide.initialize(bm, "部署一名友军")
	if not GridManager.unit_placed.is_connected(_on_unit_placed):
		GridManager.unit_placed.connect(_on_unit_placed)
	call_deferred("_run_tutorial")

func _run_tutorial() -> void:
	await guide.show_info_step(
		1, 3, "备战区", "这里存放尚未上阵的单位卡。拖动卡牌可以把单位部署到战场。",
		"CanvasLayer/HUD/BenchPanel/VBox/Scroll/Grid"
	)
	if not is_inside_tree() or _tutorial_skipped:
		return

	phase = Phase.DEPLOY_UNIT
	await guide.show_action_step(
		2, 3, "部署一名友军", "把备战区里的任意一张友军卡拖到我方网格。放置成功后会自动继续。",
		"Battlefield/FriendlyField/GridVisualizer"
	)
	if not is_inside_tree() or _tutorial_skipped:
		return

	phase = Phase.WRAP_UP
	await guide.show_info_step(
		3, 3, "留意民力", "单位行动会消耗民力；营帐等补给单位可以恢复民力。阵型准备好后，点击“开始战斗”。",
		"CanvasLayer/HUD/ManpowerLabel", "完成引导"
	)
	if is_inside_tree():
		queue_free()

func _on_unit_placed(unit: Node, _grid_pos: Vector2i) -> void:
	if phase != Phase.DEPLOY_UNIT or not is_instance_valid(unit):
		return
	if unit.get("faction") == 0:
		phase = Phase.WRAP_UP
		guide.complete_action_step()

func _on_guide_closed() -> void:
	_tutorial_skipped = true
	queue_free()
