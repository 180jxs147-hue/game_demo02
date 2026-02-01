extends TagDefinition

@export var radius: float = 150.0
@export var damage_percent: float = 0.5

func on_post_attack(unit, target):
	# If target died, we use its last position if possible, or just skip if invalid
	# But target is a node, if it's freed, is_instance_valid is false.
	# However, usually on_post_attack is called immediately.
	# If target is dead (queue_free called but not executed), it's still valid but hp <= 0.
	
	if not is_instance_valid(target): return
	
	var center = target.global_position
	# We want to hit enemies of the attacker, so friends of the target.
	# Assuming target is an enemy of unit.
	var target_faction = target.faction
	var manager = unit.battle_manager
	
	if not manager or not manager.units_container: return
	
	for other in manager.units_container.get_children():
		if not is_instance_valid(other): continue
		if other == target: continue
		if "faction" in other and other.faction != target_faction: continue
		if "current_hp" in other and other.current_hp <= 0: continue
		if "is_deployed" in other and not other.is_deployed: continue
		
		if center.distance_to(other.global_position) <= radius:
			var dmg = unit.current_attack_damage * damage_percent
			other.take_damage(dmg)
			other._pop_text("溅射", Color.ORANGE)
