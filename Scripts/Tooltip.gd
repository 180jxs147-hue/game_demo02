extends PanelContainer

func update_info(data: UnitData):
	%NameLabel.text = data.name
	var cost_val = data.manpower_cost
	if cost_val < 0:
		%CostLabel.text = "产出: %.1f" % abs(cost_val)
		%CostLabel.modulate = Color(0.4, 1.0, 0.4) # Green
	else:
		%CostLabel.text = "消耗: %.1f" % cost_val
		%CostLabel.modulate = Color(1, 0.8, 0.2) # Yellow
		 
	var stats_text = "生命: %.0f  攻击: %.0f  冷却: %.1fs" % [data.max_hp, data.attack_damage, data.cooldown]
	
	if "defense" in data and data.defense > 0:
		stats_text += "\n防御: %.0f" % data.defense
		
	if "attack_range" in data:
		var r_desc = "近战"
		if data.attack_range >= 2: r_desc = "射程%d" % data.attack_range
		stats_text += "  %s" % r_desc
		
	%StatsLabel.text = stats_text
	
	# 显示文明和兵种
	var civ_map = { 
		"dynasty": "王朝", 
		"warlord": "诸侯", 
		"rebel": "义军", 
		"predator": "虎狼", 
		"neutral": "中立" 
	}
	var cls_map = { "infantry": "步兵", "archer": "弓兵", "cavalry": "骑兵", "shield": "盾兵", "support": "辅助", "building": "建筑", "spear": "枪兵", "civilian": "平民", "siege": "攻城" }
	var civ_str = civ_map.get(data.civilization, data.civilization)
	var cls_str = cls_map.get(data.unit_class, data.unit_class)
	
	%StatsLabel.text += "\n[%s] [%s]" % [civ_str, cls_str]
	
	var desc = data.story
	
	# 追加技能词条说明
	if not data.tags.is_empty():
		if not desc.is_empty():
			desc += "\n\n"
		
		var tag_lines = []
		for t in data.tags:
			var t_desc = ""
			if TagManager:
				t_desc = TagManager.get_tag_description(t)
				# Format charge
				if t == "charge" and "charge_count" in data:
					if "%d" in t_desc:
						t_desc = t_desc % data.charge_count
			
			if t_desc == "":
				t_desc = GameConst.TAG_DESCRIPTIONS.get(t, t)
				
			tag_lines.append("• " + t_desc)
		desc += "\n".join(tag_lines)
	
	if desc.is_empty():
		desc = "暂无简介"
			
	%DescLabel.text = desc
