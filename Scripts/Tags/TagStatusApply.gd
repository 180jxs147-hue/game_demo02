extends TagDefinition

@export_enum("poison", "burn", "stun") var status_type: String = "poison"
@export var duration: float = 3.0
@export var value: float = 10.0 # Damage per tick for poison/burn

func on_post_attack(unit, target):
	if is_instance_valid(target) and target.current_hp > 0:
		target.apply_status_effect(status_type, duration, value)
