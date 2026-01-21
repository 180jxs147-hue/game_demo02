class_name TagDefinition extends Resource

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""

# --- Virtual Methods for Logic ---

# 在战斗开始时调用 (重置状态等)
func on_battle_start(unit):
	pass

# 攻击前调用。返回 true 表示该标签接管了攻击行为（不再进行普通攻击）
func on_attack_start(unit, manager) -> bool:
	return false

# 修改造成的伤害 (return modified damage)
func modify_damage(unit, target, damage: float) -> float:
	return damage

# 攻击后调用 (例如消耗层数)
func on_post_attack(unit, target):
	pass

# 友军死亡时调用
func on_ally_died(unit, ally_unit):
	pass

# 自身死亡时调用 (亡语)
func on_death(unit, manager):
	pass
