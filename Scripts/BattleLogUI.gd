extends PanelContainer

@onready var rich_text_label = $VBox/RichTextLabel
@onready var close_button = $VBox/Header/CloseButton

var _log_history: Array[String] = []
const MAX_LOG_LINES = 100

func _ready():
	visible = false # Default hidden
	var visuals = preload("res://Scripts/MenuVisuals.gd")
	if visuals:
		theme = visuals.create_theme()
		add_theme_stylebox_override("panel", visuals.cloth(false, Color.WHITE, 14))
	_update_text()
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed():
	visible = false

func toggle():
	visible = not visible

func add_log(message: String, color: Color = Color.WHITE):
	var time_str = Time.get_time_string_from_system()
	var colored_msg = "[color=#%s][%s] %s[/color]" % [color.to_html(), time_str, message]
	_log_history.append(colored_msg)
	
	if _log_history.size() > MAX_LOG_LINES:
		_log_history.pop_front()
		
	_update_text()
	
	# Auto-scroll to bottom
	if rich_text_label:
		# Defer scroll to ensure text update is processed
		call_deferred("_scroll_to_bottom")

func _update_text():
	if rich_text_label:
		rich_text_label.text = "\n".join(_log_history)

func _scroll_to_bottom():
	if rich_text_label:
		# scrollToBottom is not a direct method on RichTextLabel in Godot 4, 
		# but usually handled by auto-scroll if follow is enabled, or manually via scrollbar.
		# For simplicity, we just append text. 
		# If it's inside a ScrollContainer, we might need to adjust the scrollbar.
		# But RichTextLabel handles scrolling itself if scroll_active is true.
		pass

func clear_logs():
	_log_history.clear()
	_update_text()
