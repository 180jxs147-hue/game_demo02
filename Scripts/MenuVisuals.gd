extends RefCounted

## Shared war-room palette, including controls, popups and window chrome.
const INK := Color("191613")
const PAPER := Color("e9dfca")
const MUTED := Color("aa9982")
const GOLD := Color("c5a369")
const BORDER := Color("65533c")
const ASSET_DIR := "res://Assets/UI/WarRoom/"
static var _textures: Dictionary = {}

static func _texture(accent: bool) -> Texture2D:
	if not _textures.has(accent):
		var source: Texture2D = load(ASSET_DIR + ("command.png" if accent else "panel_opaque.png"))
		var pixels := source.get_image()
		# Cache UI-sized textures so nine-slice corners stay small at any resolution.
		pixels.resize(768 if accent else 512, 256 if accent else 512, Image.INTERPOLATE_LANCZOS)
		_textures[accent] = ImageTexture.create_from_image(pixels)
	return _textures[accent]

static func cloth(accent: bool = false, tint: Color = Color.WHITE, padding: int = 24) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _texture(accent)
	style.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 24)
		style.set_content_margin(side, padding)
	return style

static func inset(tint: Color = Color.WHITE, padding: int = 14) -> StyleBoxTexture:
	var style := cloth(false, tint, padding)
	# Quiet cloth center gives secondary controls texture without another frame.
	style.region_rect = Rect2(48, 48, 416, 416)
	return style

static func surface(fill: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func primary(button: Button):
	button.theme_type_variation = "CommandButton"

static func create_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	result.default_font = font
	result.default_font_size = 20
	for type in ["Label", "Button", "OptionButton", "CheckButton", "PopupMenu", "LineEdit", "ItemList"]:
		result.set_color("font_color", type, PAPER)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, PAPER)
		result.set_color("font_focus_color", type, PAPER)
		result.set_color("font_disabled_color", type, Color("807463"))
	for type in ["Button", "OptionButton", "CheckButton"]:
		result.set_stylebox("normal", type, inset(Color("d1c4b3"), 12))
		result.set_stylebox("hover", type, inset(Color(1.5, 1.32, 1.12), 12))
		result.set_stylebox("pressed", type, inset(Color("9e8266"), 12))
		result.set_stylebox("disabled", type, inset(Color("70675a"), 12))
		result.set_stylebox("focus", type, surface(Color.TRANSPARENT, GOLD))
		result.set_constant("outline_size", type, 0)
	result.set_type_variation("CommandButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var tint := Color.WHITE
		if state == "hover": tint = Color(1.2, 1.12, 1.02)
		if state == "pressed": tint = Color("b79778")
		if state == "disabled": tint = Color("70645a")
		result.set_stylebox(state, "CommandButton", cloth(true, tint, 12))
	result.set_stylebox("panel", "PanelContainer", cloth())
	result.set_stylebox("panel", "AcceptDialog", cloth(false, Color.WHITE, 28))
	result.set_stylebox("panel", "PopupMenu", cloth(false, Color.WHITE, 16))
	result.set_stylebox("hover", "PopupMenu", inset(Color(1.7, 1.3, 1.05), 10))
	result.set_constant("v_separation", "PopupMenu", 16)
	result.set_constant("buttons_separation", "AcceptDialog", 18)
	result.set_constant("buttons_min_width", "AcceptDialog", 132)
	result.set_constant("buttons_min_height", "AcceptDialog", 48)
	# Fallback for windows that do not use style_dialog(). Never green.
	var border := surface(INK, BORDER)
	border.content_margin_top = 42
	result.set_stylebox("embedded_border", "Window", border)
	result.set_stylebox("embedded_unfocused_border", "Window", border)
	result.set_color("title_color", "Window", PAPER)
	result.set_font_size("title_font_size", "Window", 22)
	for type in ["HSeparator", "VSeparator"]:
		result.set_stylebox("separator", type, StyleBoxEmpty.new())
		result.set_constant("separation", type, 8)
	var track := surface(Color("3a3025"))
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	result.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = GOLD
	result.set_stylebox("grabber_area", "HSlider", filled)
	result.set_stylebox("grabber_area_highlight", "HSlider", filled)
	for type in ["LineEdit", "ItemList"]:
		result.set_stylebox("normal" if type == "LineEdit" else "panel", type, inset(Color("c8b9a4"), 14))
		result.set_stylebox("focus", type, surface(Color.TRANSPARENT, GOLD))
	result.set_stylebox("read_only", "LineEdit", inset(Color("807465"), 14))
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", GOLD)
	result.set_color("selection_color", "LineEdit", Color("684535"))
	result.set_stylebox("selected", "ItemList", inset(Color(1.8, 1.35, 1.05), 10))
	result.set_stylebox("selected_focus", "ItemList", inset(Color(2.0, 1.5, 1.15), 10))
	result.set_color("guide_color", "ItemList", Color.TRANSPARENT)
	result.set_constant("v_separation", "ItemList", 12)
	for type in ["VScrollBar", "HScrollBar"]:
		var rail := surface(Color(0.1, 0.08, 0.06, 0.25))
		rail.set_content_margin_all(3)
		result.set_stylebox("scroll", type, rail)
		result.set_stylebox("scroll_focus", type, rail)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var thumb := surface(GOLD if state != "grabber" else BORDER)
			thumb.set_content_margin_all(3)
			result.set_stylebox(state, type, thumb)
	result.set_color("default_color", "RichTextLabel", PAPER)
	result.set_constant("line_separation", "RichTextLabel", 6)
	return result

static func style_dialog(dialog: AcceptDialog, destructive: bool = false):
	if dialog.has_meta("war_room_chrome"): return
	dialog.set_meta("war_room_chrome", true)
	dialog.theme = create_theme()
	dialog.exclusive = true
	dialog.borderless = true
	dialog.get_label().hide()
	var content := dialog.get_node_or_null("Content")
	var body := VBoxContainer.new()
	body.name = "DialogBody"
	body.add_theme_constant_override("separation", 24)
	dialog.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title := Label.new()
	title.text = dialog.title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	heading.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = "×"
	close.tooltip_text = "关闭"
	close.custom_minimum_size = Vector2(44, 44)
	heading.add_child(close)
	close.pressed.connect(func(): dialog.canceled.emit(); dialog.hide())
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 440
	body.add_child(message)
	if content:
		content.reparent(body)
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.about_to_popup.connect(func():
		title.text = dialog.title
		message.text = dialog.dialog_text
		message.visible = not message.text.is_empty()
		dialog.get_label().hide()
	)
	message.visible = false
	dialog.get_ok_button().custom_minimum_size = Vector2(132, 46)
	if dialog is ConfirmationDialog:
		dialog.min_size = Vector2i(560, 240)
		dialog.dialog_autowrap = true
		dialog.get_cancel_button().text = "取消"
		dialog.get_cancel_button().custom_minimum_size = Vector2(132, 46)
	if destructive:
		primary(dialog.get_ok_button())
		dialog.about_to_popup.connect(func(): dialog.get_cancel_button().grab_focus.call_deferred())
