extends Panel

## 单张卡牌 UI（用于图鉴与卡牌列表）。
## 交互约定：
## - ClickButton 覆盖整个卡面，统一发射 pressed(UnitData)
## - setup_stacked 用于显示“xN”堆叠数量

@onready var name_label = $VBoxContainer/NameLabel
@onready var icon_texture = $IconTexture # <--- 新增
@onready var card_bg = $CardBackground
@onready var rarity_badge = $RarityBadge
@onready var footprint_preview = $FootprintPreview
@onready var civ_icon = $CivIcon
@onready var class_icon = $ClassIcon

@onready var cost_icon = $VBoxContainer/StatsLine/CostGroup/CostIcon
@onready var cost_label = $VBoxContainer/StatsLine/CostGroup/CostLabel
@onready var atk_icon = $VBoxContainer/StatsLine/AtkGroup/AtkIcon
@onready var atk_label = $VBoxContainer/StatsLine/AtkGroup/AtkLabel
@onready var cd_icon = $VBoxContainer/StatsLine/CdGroup/CdIcon
@onready var cd_label = $VBoxContainer/StatsLine/CdGroup/CdLabel
@onready var count_label = $CountLabel
@onready var click_button = $ClickButton
@onready var synergy_info_label = $SynergyInfoLabel

signal pressed(data: UnitData)
signal drag_requested(data: UnitData)

var _unit_data: UnitData
var _connected_click: bool = false

@export var use_card_base: bool = true
@export var drag_on_press: bool = false

const CARD_BASE_PATH := "res://Assets/UI/Cards/card_base.png"
const ICON_COST_PATH := "res://Assets/UI/Cards/icon_cost.png"
const ICON_ATK_PATH := "res://Assets/UI/Cards/icon_atk.png"
const ICON_CD_PATH := "res://Assets/UI/Cards/icon_cd.png"
const RARITY_BADGE_PATHS := {
	"common": "res://Assets/UI/Cards/rarity_common.png",
	"rare": "res://Assets/UI/Cards/rarity_rare.png",
	"epic": "res://Assets/UI/Cards/rarity_epic.png",
	"legendary": "res://Assets/UI/Cards/rarity_legendary.png"
}
const CIV_ICON_PATHS := {
	"han": "res://Assets/UI/Cards/civ_han.png",
	"roman": "res://Assets/UI/Cards/civ_roman.png",
	"greek": "res://Assets/UI/Cards/civ_greek.png",
	"neutral": "res://Assets/UI/Cards/civ_neutral.png"
}
const CLASS_ICON_PATHS := {
	"infantry": "res://Assets/UI/Cards/class_infantry.png",
	"archer": "res://Assets/UI/Cards/class_archer.png",
	"cavalry": "res://Assets/UI/Cards/class_cavalry.png",
	"shield": "res://Assets/UI/Cards/class_shield.png",
	"spear": "res://Assets/UI/Cards/class_spear.png",
	"support": "res://Assets/UI/Cards/class_support.png",
	"building": "res://Assets/UI/Cards/class_building.png",
	"civilian": "res://Assets/UI/Cards/class_civilian.png",
	"siege": "res://Assets/UI/Cards/class_siege.png"
}

func _ready():
	if click_button and not _connected_click:
		_connected_click = true
		click_button.pressed.connect(func():
			if _unit_data:
				pressed.emit(_unit_data)
		)
		click_button.gui_input.connect(func(event):
			if not drag_on_press:
				return
			if not _unit_data:
				return
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				drag_requested.emit(_unit_data)
		)
	_apply_card_skin(null)

func _apply_card_skin(data: UnitData):
	var has_base := false
	if use_card_base and card_bg and ResourceLoader.exists(CARD_BASE_PATH):
		var tex = load(CARD_BASE_PATH)
		if tex:
			card_bg.texture = tex
			has_base = true
	else:
		if card_bg:
			card_bg.texture = null
	
	if has_base:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.35)
		sb.border_color = Color(1, 1, 1, 0.08)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.set_corner_radius_all(10)
		add_theme_stylebox_override("panel", sb)
	
	if rarity_badge:
		if data and "rarity" in data:
			var key = String(data.rarity).to_lower()
			var badge_path = RARITY_BADGE_PATHS.get(key, RARITY_BADGE_PATHS["common"])
			if badge_path != "" and ResourceLoader.exists(badge_path):
				var badge_tex = load(badge_path)
				rarity_badge.texture = badge_tex
				rarity_badge.visible = badge_tex != null
			else:
				rarity_badge.visible = false
		else:
			rarity_badge.visible = false

	if cost_icon:
		cost_icon.texture = load(ICON_COST_PATH) if ResourceLoader.exists(ICON_COST_PATH) else null
	if atk_icon:
		atk_icon.texture = load(ICON_ATK_PATH) if ResourceLoader.exists(ICON_ATK_PATH) else null
	if cd_icon:
		cd_icon.texture = load(ICON_CD_PATH) if ResourceLoader.exists(ICON_CD_PATH) else null

	if civ_icon:
		if data:
			var civ_key = String(data.civilization).to_lower()
			var civ_path = CIV_ICON_PATHS.get(civ_key, CIV_ICON_PATHS.get("neutral", ""))
			if civ_path != "" and ResourceLoader.exists(civ_path):
				civ_icon.texture = load(civ_path)
				civ_icon.visible = civ_icon.texture != null
			else:
				civ_icon.visible = false
		else:
			civ_icon.visible = false

	if class_icon:
		if data:
			var cls_key = String(data.unit_class).to_lower()
			var cls_path = CLASS_ICON_PATHS.get(cls_key, "")
			if cls_path == "" or not ResourceLoader.exists(cls_path):
				cls_path = CLASS_ICON_PATHS.get("spear", "")
			if cls_path != "" and ResourceLoader.exists(cls_path):
				class_icon.texture = load(cls_path)
				class_icon.visible = class_icon.texture != null
			else:
				class_icon.visible = false
		else:
			class_icon.visible = false

func setup(data: UnitData):
	if not data: return
	_unit_data = data
	_apply_card_skin(data)
	
	name_label.text = data.name
	if data.manpower_cost < 0:
		cost_label.text = "产%.1f" % absf(data.manpower_cost)
	else:
		cost_label.text = "耗%.1f" % data.manpower_cost
	atk_label.text = "攻%.0f" % data.attack_damage
	cd_label.text = "CD%.1fs" % data.cooldown
	# 已移除对 ColorRect 的依赖
	
	if icon_texture:
		icon_texture.texture = data.icon
	if footprint_preview and footprint_preview.has_method("set_unit_data"):
		footprint_preview.set_unit_data(data)
		
	count_label.visible = false
	
	# 显示羁绊信息
	if synergy_info_label:
		# 简单的翻译映射 (也可以用 TranslationServer)
		var civ_map = {
			"han": "汉", "roman": "罗马", "greek": "希腊", "neutral": "中立", "french": "法兰西"
		}
		var cls_map = {
			"infantry": "步兵", "archer": "弓兵", "cavalry": "骑兵", "shield": "盾兵", "support": "辅助", "building": "建筑", "spear": "枪兵", "civilian": "平民", "siege": "攻城"
		}
		
		var civ_str = civ_map.get(data.civilization, data.civilization)
		var cls_str = cls_map.get(data.unit_class, data.unit_class)
		synergy_info_label.text = "%s\n%s" % [civ_str, cls_str]

func setup_stacked(data: UnitData, count: int):
	setup(data)
	if count > 1:
		count_label.visible = true
		count_label.text = "x%d" % count
