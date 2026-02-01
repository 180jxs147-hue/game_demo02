extends TagDefinition

func on_death(unit, manager):
	if unit.faction == 0: # FRIENDLY
		# 造成 300% 攻击力的伤害
		var dmg = unit.current_attack_damage * 3.0
		# 改为对随机敌人造成伤害
		if manager.has_method("deal_damage_to_random_enemy"):
			manager.deal_damage_to_random_enemy(dmg, true)
		unit._pop_text("BOOM!", Color.RED)
