extends CanvasLayer

## 场景切换淡入淡出动效。
## 使用: await SceneTransition.fade_out(); get_tree().change_scene_to_file(path); SceneTransition.fade_in()
## 或: SceneTransition.change_scene("res://Scenes/SomeScene.tscn")

@export var fade_color: Color = Color(0.02, 0.02, 0.04, 1.0)
@export var default_duration: float = 0.3
var _overlay: ColorRect
var _fade_tween: Tween
var _is_fading := false

func _ready():
	layer = 256
	_overlay = ColorRect.new()
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

func _input(event):
	if _is_fading:
		get_viewport().set_input_as_handled()

func fade_out(duration: float = -1.0) -> void:
	if _is_fading:
		return
	if duration < 0.0:
		duration = default_duration
	_is_fading = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_overlay.color.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_overlay, "color:a", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _fade_tween.finished

func fade_in(duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = default_duration
	_is_fading = true
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_overlay, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _fade_tween.finished
	_is_fading = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func change_scene(scene_path: String, duration: float = -1.0) -> void:
	if _is_fading:
		return
	if duration < 0.0:
		duration = default_duration
	await fade_out(duration)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	fade_in(duration)
