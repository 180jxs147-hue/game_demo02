extends Node

const GUIDE_SCRIPT = preload("res://Scripts/Tutorials/TutorialGuide.gd")

var battle_manager: BattleManager
var guide
var _tutorial_skipped: bool = false

func start(bm: BattleManager) -> void:
	battle_manager = bm
	guide = GUIDE_SCRIPT.new()
	guide.name = "TutorialGuide"
	add_child(guide)
	guide.closed.connect(_on_guide_closed)
	guide.initialize(bm, "识别敌方威胁与补给目标")
	call_deferred("_run_tutorial")

func _run_tutorial() -> void:
	await guide.show_info_step(
		1, 3, "识别前排威胁", "黄巾力士占地较大、攻击力强。先观察敌方前排，再决定我方材官的站位。",
		_find_enemy_unit("黄巾力士")
	)
	if not is_inside_tree() or _tutorial_skipped:
		return

	var camp: Node = _find_enemy_unit("营帐")
	if not camp:
		camp = battle_manager.get_node_or_null("Battlefield/EnemyField/GridVisualizer")
	await guide.show_info_step(
		2, 3, "优先打击补给", "营帐会持续补充敌方民力。优先处理补给目标，可以削弱敌方高消耗单位持续作战的能力。",
		camp
	)
	if not is_inside_tree() or _tutorial_skipped:
		return

	await guide.show_info_step(
		3, 3, "准备出战", "检查我方阵型与敌方关键目标，准备好后点击“开始战斗”。",
		"CanvasLayer/HUD/StartButton", "完成引导"
	)
	if is_inside_tree():
		queue_free()

func _find_enemy_unit(unit_name: String) -> Node:
	var units: Node = battle_manager.get_node_or_null("Battlefield/EnemyField/UnitsContainer")
	if not units:
		return null
	for unit in units.get_children():
		if not is_instance_valid(unit):
			continue
		var unit_data: Variant = unit.get("data")
		if unit_data is Resource and unit_data.get("name") == unit_name:
			return unit
	return null

func _on_guide_closed() -> void:
	_tutorial_skipped = true
	queue_free()
