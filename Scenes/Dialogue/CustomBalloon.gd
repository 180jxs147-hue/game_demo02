extends CanvasLayer
## A basic dialogue balloon for use with Dialogue Manager.


## The dialogue resource
@export var dialogue_resource: DialogueResource

## Start from a given title when using balloon as a [Node] in a scene.
@export var start_from_title: String = ""

## If running as a [Node] in a scene then auto start the dialogue.
@export var auto_start: bool = false

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"

## A sound player for voice lines (if they exist).
@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			if not Engine.is_editor_hint() and is_inside_tree():
				get_tree().paused = false
			if owner == null:
				queue_free()
			else:
				hide()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

## The base balloon anchor
@onready var balloon: Control = %Balloon

## The label showing the name of the currently speaking character
@onready var character_label: RichTextLabel = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

## Indicator to show that player can progress dialogue.
@onready var progress: Polygon2D = %Progress

## The background texture rect
@onready var background_rect: TextureRect = %Background

## The left portrait texture rect
@onready var left_portrait: TextureRect = %LeftPortrait

## The right portrait texture rect
@onready var right_portrait: TextureRect = %RightPortrait

## The fast forward button
@onready var fast_forward_button: Button = %FastForwardButton

var is_fast_forwarding: bool = false

const CHARACTER_NAMES_ZH = {
	"XiaoBingZhang": "小兵张",
	"GongShouLi": "弓手李",
	"RefugeeLeader": "流民首领",
	"WuZhang": "伍长",
	"YellowTurban": "黄巾军",
	"Player01": "指挥官",
	"Huangfusong": "皇甫嵩",
	"System": "系统",
	"Guide": "引导者",
	"HanScout": "汉军斥候",
	"Eunuch": "宦官",
	"ZhuJun": "朱儁",
	"ZhangBao": "张宝",
	"ZhangJue": "张角",
	"YellowTurbanGeneral": "黄巾将领",
	"RebelGeneral": "叛军将领",
	"ZhangLiang": "张梁",
	"Narrator": "旁白"
}

var _left_base_pos: Vector2
var _right_base_pos: Vector2

func _parse_offset_tag(prefix: String, tags: PackedStringArray) -> Vector2:
	for t in tags:
		if t.begins_with(prefix):
			var raw := t.substr(prefix.length())
			var parts := raw.split(",", false)
			if parts.size() == 2:
				return Vector2(parts[0].to_float(), parts[1].to_float())
	return Vector2.ZERO

func _parse_float_tag(prefix: String, tags: PackedStringArray) -> float:
	for t in tags:
		if t.begins_with(prefix):
			return t.substr(prefix.length()).to_float()
	return 1.0


func _find_texture_path(dir: String, base: String) -> String:
	# 优先尝试直接加载 (假设 base 已经包含扩展名，或者不包含)
	var exts = ["", ".png", ".jpg", ".jpeg", ".webp", ".tga"]
	for ext in exts:
		var path = dir + base + ext
		if ResourceLoader.exists(path):
			return path
	
	# 如果找不到，尝试不区分大小写的匹配（仅限调试模式或非导出包，导出后 ResourceLoader.exists 通常大小写敏感）
	# 在导出项目中，强烈建议文件名和代码中引用名保持完全一致（包括大小写）
	return ""

func _load_texture_any(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			return tex
	return null


func _exit_tree() -> void:
	var scene_tree := get_tree()
	if not Engine.is_editor_hint() and scene_tree:
		scene_tree.paused = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[CustomBalloon] _ready called")
	
	if not Engine.is_editor_hint():
		get_tree().paused = true # 确保对话时暂停游戏（如果还没暂停）

	balloon.hide()
	
	# 确保输入能穿透
	if not responses_menu.response_template.has_theme_stylebox_override("normal"):
		# 防止样式为空导致无法点击
		pass
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)
	_left_base_pos = left_portrait.position
	_right_base_pos = right_portrait.position

	fast_forward_button.toggled.connect(_on_fast_forward_toggled)

	if auto_start:
		if not is_instance_valid(dialogue_resource):
			assert(false, DMConstants.get_error_message(DMConstants.ERR_MISSING_RESOURCE_FOR_AUTOSTART))
		start()


func _process(delta: float) -> void:
	if is_instance_valid(dialogue_line):
		progress.visible = not dialogue_label.is_typing and dialogue_line.responses.size() == 0 and not dialogue_line.has_tag("voice")


func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio = dialogue_label.visible_ratio
		dialogue_line = await dialogue_resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## Start some dialogue
func start(with_dialogue_resource: DialogueResource = null, title: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not title.is_empty():
		start_from_title = title
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_title, temporary_game_states)
	show()


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	progress.hide()
	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()
	var char_text = dialogue_line.character
	if CHARACTER_NAMES_ZH.has(char_text):
		char_text = CHARACTER_NAMES_ZH[char_text]
	else:
		char_text = tr(char_text, "dialogue")
	character_label.text = char_text

	for tag in dialogue_line.tags:
		if tag.begins_with("bg:"):
			var bg_name = tag.substr(3)
			var bg_path = _find_texture_path("res://Assets/Backgrounds/", bg_name)
			if bg_path != "":
				var bg_tex = _load_texture_any(bg_path)
				if bg_tex:
					background_rect.texture = bg_tex

	var char_name = dialogue_line.character
	if not char_name.is_empty():
		var portrait_path = _find_texture_path("res://Assets/Portraits/", char_name)
		var texture: Texture2D = null
		if portrait_path != "":
			texture = _load_texture_any(portrait_path)
		
		var is_right = dialogue_line.tags.has("pos:right") or dialogue_line.tags.has("right")
		var portrait_offset := _parse_offset_tag("portrait_offset:", dialogue_line.tags)
		var portrait_scale := _parse_float_tag("portrait_scale:", dialogue_line.tags)
		
		if is_right:
			if texture:
				right_portrait.texture = texture
				right_portrait.visible = true
			right_portrait.position = _right_base_pos + portrait_offset
			right_portrait.scale = Vector2(portrait_scale, portrait_scale)
			right_portrait.modulate = Color(1, 1, 1, 1)      # Highlight
			left_portrait.modulate = Color(0.5, 0.5, 0.5, 1) # Dim
		else:
			if texture:
				left_portrait.texture = texture
				left_portrait.visible = true
			left_portrait.position = _left_base_pos + portrait_offset
			left_portrait.scale = Vector2(portrait_scale, portrait_scale)
			left_portrait.modulate = Color(1, 1, 1, 1)       # Highlight
			right_portrait.modulate = Color(0.5, 0.5, 0.5, 1)# Dim

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# Show our balloon
	balloon.show()
	will_hide_balloon = false

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		if is_fast_forwarding:
			dialogue_label.skip_typing()
		
		if dialogue_label.is_typing:
			await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.has_tag("voice"):
		audio_stream_player.stream = load(dialogue_line.get_tag_value("voice"))
		audio_stream_player.play()
		await audio_stream_player.finished
		next(dialogue_line.next_id)
	elif dialogue_line.responses.size() > 0:
		# Stop fast forward on choices
		if is_fast_forwarding:
			is_fast_forwarding = false
			fast_forward_button.set_pressed_no_signal(false)
			
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()
		if is_fast_forwarding:
			_attempt_fast_forward_next()


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()


func _on_mutated(_mutation: Dictionary) -> void:
	if not _mutation.is_inline:
		is_waiting_for_input = false
		will_hide_balloon = true
		mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


func _on_fast_forward_toggled(toggled_on: bool) -> void:
	is_fast_forwarding = toggled_on
	if is_fast_forwarding:
		if dialogue_label.is_typing:
			dialogue_label.skip_typing()
		elif is_waiting_for_input:
			next(dialogue_line.next_id)


func _attempt_fast_forward_next() -> void:
	await get_tree().create_timer(0.1).timeout
	if is_fast_forwarding and is_waiting_for_input:
		next(dialogue_line.next_id)


#endregion
