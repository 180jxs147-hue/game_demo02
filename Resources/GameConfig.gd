extends Resource
class_name GameConfig

## Initial game configuration for testing and balancing

@export_group("Resources")
@export var initial_gold: int = 20
@export var initial_manpower_bonus: int = 0
@export var initial_prestige: int = 0

@export_group("Grid")
@export var initial_grid_rows: int = 3
@export var initial_grid_cols: int = 3

@export_group("Cards")
@export var initial_cards: Array[Resource] = [] # Array of UnitData

@export_group("Economy")
## Buy prices for cards in the shop based on rarity
@export var rarity_buy_prices: Dictionary = {
	"common": 3,
	"uncommon": 5,
	"rare": 8,
	"epic": 12,
	"legendary": 20
}

## Sell prices for cards (e.g. when sold as reward)
@export var rarity_sell_prices: Dictionary = {
	"common": 2,
	"uncommon": 3,
	"rare": 5,
	"epic": 8,
	"legendary": 12
}
