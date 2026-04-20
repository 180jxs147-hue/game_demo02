extends Resource
class_name RelicData

@export var id: String
@export var name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var rarity: String = "common" # common, rare, legendary

## Effect type strings to be interpreted by BattleManager/GameState
## e.g., "start_manpower", "global_atk", "global_def"
@export var effect_type: String 
@export var effect_value: float
