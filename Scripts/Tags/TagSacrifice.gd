extends TagDefinition

func on_ally_died(unit, ally_unit):
	if not unit.timer.is_stopped():
		unit.current_cooldown = max(0.2, unit.current_cooldown * 0.7)
		if unit.timer.time_left > unit.current_cooldown:
			unit.timer.start(unit.current_cooldown)
		if unit.status_label:
			unit.status_label.modulate = Color.RED
