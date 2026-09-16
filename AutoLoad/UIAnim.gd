extends Node

## UI 动效增强工具
## 为按钮添加悬停放大、按压缩小动效
## 为面板添加入场动画

const HOVER_SCALE: float = 1.03
const PRESS_SCALE: float = 0.97
const PRESS_DURATION: float = 0.06
const HOVER_DURATION: float = 0.12

static func animate_button(btn: Button, hover_scale: float = HOVER_SCALE) -> void:
	var orig_scale := btn.scale if btn.scale != Vector2.ZERO else Vector2.ONE
	btn.mouse_entered.connect(func():
		var tw = btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", orig_scale * hover_scale, HOVER_DURATION)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", orig_scale, HOVER_DURATION)
	)
	btn.button_down.connect(func():
		var tw = btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", orig_scale * PRESS_SCALE, PRESS_DURATION)
	)
	btn.button_up.connect(func():
		var tw = btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(btn, "scale", orig_scale * hover_scale, PRESS_DURATION)
	)

static func slide_in(control: Control, from_direction: Vector2 = Vector2(0, 30), duration: float = 0.3, delay: float = 0.0) -> void:
	var target_pos := control.position
	control.modulate.a = 0.0
	control.position = target_pos + from_direction
	var tw = control.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(control, "position", target_pos, duration)
	tw.tween_property(control, "modulate:a", 1.0, duration)

static func pop_in(control: Control, duration: float = 0.3, delay: float = 0.0) -> void:
	control.modulate.a = 0.0
	control.scale = Vector2(0.85, 0.85)
	control.pivot_offset = control.size * 0.5
	var tw = control.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(control, "scale", Vector2.ONE, duration)
	tw.tween_property(control, "modulate:a", 1.0, duration)

static func shimmer_label(label: Label, accent_color: Color = Color(0.95, 0.9, 0.65), duration: float = 2.0) -> void:
	var tw = label.create_tween().set_loops()
	var orig_color := label.get_theme_color("font_color") if label.has_theme_color("font_color") else Color.WHITE
	tw.tween_property(label, "modulate", accent_color, duration * 0.5)
	tw.tween_property(label, "modulate", orig_color, duration * 0.5)

static func apply_all_button_animations(root: Node, hover_scale: float = HOVER_SCALE) -> void:
	for child in root.find_children("*", "Button", true, false):
		if child is Button:
			animate_button(child, hover_scale)
