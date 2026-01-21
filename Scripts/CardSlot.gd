extends Panel

## 单张卡牌 UI（用于图鉴与卡牌列表）。
## 交互约定：
## - ClickButton 覆盖整个卡面，统一发射 pressed(UnitData)
## - setup_stacked 用于显示“xN”堆叠数量

@onready var name_label = $NameRow/NameLabel
@onready var icon_texture = $IconTexture # <--- 新增
@onready var card_bg = $CardBackground
@onready var rarity_badge = $RarityBadge
@onready var footprint_preview = $FootprintPreview
@onready var type_divider = $TypeDivider
@onready var type_pattern = $TypeDivider/Pattern
@onready var civ_class_label = $NameRow/CivClassLabel
@onready var skill_label = $SkillLabel
@onready var stat_icons = $StatIcons

@onready var cost_icon = $StatIcons/CostGroup/CostIcon
@onready var cost_value = $StatIcons/CostGroup/CostValue
@onready var atk_icon = $StatIcons/AtkGroup/AtkIcon
@onready var atk_value = $StatIcons/AtkGroup/AtkValue
@onready var cd_icon = $StatIcons/CdGroup/CdIcon
@onready var cd_value = $StatIcons/CdGroup/CdValue
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
const PATTERN_BAR_PATHS := {
	"han": "res://Assets/UI/Cards/pattern_bars/bar_pattern_han.png",
	"roman": "res://Assets/UI/Cards/pattern_bars/bar_pattern_roman.png",
	"greek": "res://Assets/UI/Cards/pattern_bars/bar_pattern_greek.png",
	"huangjin": "res://Assets/UI/Cards/pattern_bars/bar_pattern_huangjin.png",
	"neutral": "res://Assets/UI/Cards/pattern_bars/bar_pattern_neutral.png",
	"french": "res://Assets/UI/Cards/pattern_bars/bar_pattern_france.png"
}
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
	
	if _unit_data:
		setup(_unit_data)

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

	if type_divider:
		if data:
			var civ_key = String(data.civilization).to_lower()
			var civ_color := _get_civ_color(civ_key)
			var bg = civ_color
			bg.a = 0.55
			type_divider.color = bg
			type_divider.visible = true
			if type_pattern:
				var p = PATTERN_BAR_PATHS.get(civ_key, "")
				if p != "" and ResourceLoader.exists(p):
					type_pattern.texture = load(p)
					type_pattern.visible = type_pattern.texture != null
					type_pattern.modulate = Color.WHITE
				else:
					type_pattern.texture = null
					type_pattern.visible = false
		else:
			type_divider.visible = false
			if type_pattern:
				type_pattern.visible = false

	if civ_class_label:
		if data:
			var civ_map = {"han": "汉", "roman": "罗马", "greek": "希腊", "neutral": "中立", "french": "法兰西", "huangjin": "黄巾"}
			var cls_map = {"infantry": "步兵", "archer": "弓兵", "cavalry": "骑兵", "shield": "盾兵", "support": "辅助", "building": "建筑", "spear": "长柄", "civilian": "平民", "siege": "攻城"}
			var civ_str = civ_map.get(String(data.civilization).to_lower(), String(data.civilization))
			var cls_str = cls_map.get(String(data.unit_class).to_lower(), String(data.unit_class))
			civ_class_label.text = "%s %s" % [civ_str, cls_str]
		else:
			civ_class_label.text = ""

func setup(data: UnitData):
	if not data: return
	_unit_data = data
	
	if not is_node_ready():
		return

	_apply_card_skin(data)
	
	if data.is_injured:
		modulate = Color(1.0, 0.5, 0.5) # 变红
		if name_label:
			name_label.text = data.name + " (重伤)"
	else:
		modulate = Color.WHITE
		if name_label:
			name_label.text = data.name

	if skill_label:
		skill_label.text = ""
		skill_label.visible = false
		if data.tags and not data.tags.is_empty():
			for t in data.tags:
				if GameConst.TAG_CN_NAMES.has(t):
					skill_label.text = GameConst.TAG_CN_NAMES[t]
					skill_label.visible = true
					break
	if cost_value:
		if data.manpower_cost < 0:
			cost_value.text = "+%.1f" % absf(data.manpower_cost)
		else:
			cost_value.text = "%.1f" % data.manpower_cost
	if atk_value:
		atk_value.text = "%.0f" % data.attack_damage
	if cd_value:
		cd_value.text = "%.1fs" % data.cooldown
	# 已移除对 ColorRect 的依赖
	
	if icon_texture:
		icon_texture.texture = data.icon
	if footprint_preview and footprint_preview.has_method("set_unit_data"):
		footprint_preview.set_unit_data(data)
		
	count_label.visible = false
	

func _get_civ_color(civ_key: String) -> Color:
	match civ_key:
		"han":
			return Color("c83f2b")
		"roman":
			return Color("3b1b5a")
		"greek":
			return Color("1b5ea8")
		"french":
			return Color("234aa5")
		"huangjin":
			return Color("d1a322")
		_:
			return Color("9aa0a6")

func setup_stacked(data: UnitData, count: int):
	setup(data)
	if count > 1:
		count_label.visible = true
		count_label.text = "x%d" % count

func setup_upgrade(title: String, desc: String, icon_tex: Texture2D = null):
	_unit_data = null
	
	if not is_node_ready(): return
	
	_apply_card_skin(null)
	modulate = Color.WHITE
	
	if name_label:
		name_label.text = title
		
	if skill_label:
		skill_label.text = desc
		skill_label.visible = true
		
	if civ_class_label:
		civ_class_label.text = "特殊奖励"
		
	if stat_icons:
		stat_icons.visible = false
		
	if footprint_preview:
		footprint_preview.visible = false
		
	if rarity_badge:
		rarity_badge.visible = false
		
	if count_label:
		count_label.visible = false
		
	if icon_texture:
		icon_texture.texture = icon_tex
		
	if type_divider:
		type_divider.visible = true
		type_divider.color = Color(0.8, 0.7, 0.2, 0.55) # Gold-ish
		if type_pattern:
			type_pattern.visible = false
