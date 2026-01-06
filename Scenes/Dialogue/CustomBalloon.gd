class_name DialogueManagerExampleBalloon extends CanvasLayer
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
	var exts = ["png", "jpg", "jpeg", "webp"]
	var base_norm = base.to_lower().replace(" ", "").replace("-", "").replace("_", "")
	var d = DirAccess.open(dir)
	if d:
		d.list_dir_begin()
		var f = d.get_next()
		while f != "":
			if not d.current_is_dir():
				var lower = f.to_lower()
				var name_no_ext = lower.rsplit(".", false, 1)[0]
				var name_norm = name_no_ext.replace(" ", "").replace("-", "").replace("_", "")
				for ext in exts:
					if lower == (base + "." + ext).to_lower() or name_norm == base_norm or name_norm.find(base_norm) != -1:
						d.list_dir_end()
						return dir + f
			f = d.get_next()
		d.list_dir_end()
	for ext in exts:
		var path = dir + base + "." + ext
		if ResourceLoader.exists(path):
			return path
	return ""

func _load_texture_any(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() == 0:
		return null
	var image := Image.new()
	var ok := false
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		ok = image.load_png_from_buffer(bytes) == OK
	elif bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		ok = image.load_jpg_from_buffer(bytes) == OK
	elif bytes.size() >= 12 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		ok = image.load_webp_from_buffer(bytes) == OK
	if not ok:
		return null
	return ImageTexture.create_from_image(image)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	balloon.hide()
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)
	_left_base_pos = left_portrait.position
	_right_base_pos = right_portrait.position

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
	character_label.text = tr(dialogue_line.character, "dialogue")

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
		await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.has_tag("voice"):
		audio_stream_player.stream = load(dialogue_line.get_tag_value("voice"))
		audio_stream_player.play()
		await audio_stream_player.finished
		next(dialogue_line.next_id)
	elif dialogue_line.responses.size() > 0:
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


#endregion
