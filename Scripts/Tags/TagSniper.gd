extends TagDefinition

func modify_damage(unit, target, damage: float) -> float:
	if unit.faction != 0: return damage # Only friendly snipers
	
	var dist = 0.0
	if target:
		dist = abs(unit.global_position.x - target.global_position.x)
	else:
		# 如果打基地，假设距离是到屏幕边缘
		dist = abs(unit.global_position.x - GameConst.BATTLE_FIELD_WIDTH)
		
	# 每 100 像素增加 10% 伤害
	var bonus = (dist / 100.0) * 0.1
	return damage * (1.0 + bonus)
