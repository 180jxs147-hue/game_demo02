extends TagDefinition

func on_battle_start(unit):
	if unit.data and "charge_count" in unit.data:
		unit.current_charge_stacks = unit.data.charge_count
	else:
		unit.current_charge_stacks = 0

func modify_damage(unit, target, damage: float) -> float:
	if unit.current_charge_stacks > 0:
		unit._pop_text("冲锋!")
		return damage * 2.0
	return damage

func on_post_attack(unit, target):
	if unit.current_charge_stacks > 0:
		unit.current_charge_stacks -= 1
