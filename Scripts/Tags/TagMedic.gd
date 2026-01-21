extends TagDefinition

func on_attack_start(unit, manager) -> bool:
	# 贞德特殊处理
	if unit.data.name == "圣女贞德":
		return false # 贞德正常攻击 (光环逻辑在 adj rules)
	
	# 治疗逻辑
	var heal_val = unit.current_attack_damage
	if manager.has_method("heal_lowest_hp_ally"):
		manager.heal_lowest_hp_ally(heal_val, unit.faction == 0) # 0 is FRIENDLY
	
	unit._pop_text("Heal!")
	
	# 消耗民力
	if unit.faction == 0: # FRIENDLY
		manager.modify_manpower(-unit.data.manpower_cost)
	else:
		if manager.has_method("modify_enemy_manpower"):
			manager.modify_enemy_manpower(-unit.data.manpower_cost)
			
	return true # Handled
