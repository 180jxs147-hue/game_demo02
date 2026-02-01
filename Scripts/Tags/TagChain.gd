extends TagDefinition

@export var range_limit: float = 300.0
@export var damage_percent: float = 0.6
@export var max_targets: int = 1

func on_post_attack(unit, target):
	if not is_instance_valid(target): return
	if not unit.battle_manager: return
	
	var current_source = target
	var hit_count = 0
	var exclude = [target]
	var target_faction = target.faction
	
	while hit_count < max_targets:
		var next_target = unit.battle_manager.find_closest_unit(current_source.global_position, target_faction, exclude)
		
		if next_target and current_source.global_position.distance_to(next_target.global_position) <= range_limit:
			var dmg = unit.current_attack_damage * damage_percent
			next_target.take_damage(dmg)
			next_target._pop_text("连锁", Color.CYAN)
			exclude.append(next_target)
			current_source = next_target
			hit_count += 1
		else:
			break
