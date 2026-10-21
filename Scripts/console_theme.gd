class_name ConsoleTheme
extends RefCounted

# Theme of the console's pop-up windows: grey Windows-style panels, bevelled
# buttons, white sunken fields and black text, matching the commander screen.
const COL_PANEL = Color(0.76, 0.76, 0.76, 1.0)
const COL_FIELD = Color(1.0, 1.0, 1.0, 1.0)
const COL_TEXT = Color(0.0, 0.0, 0.0, 1.0)
const COL_TEXT_DISABLED = Color(0.5, 0.5, 0.5, 1.0)
const COL_SHADOW = Color(0.4, 0.4, 0.4, 1.0)
const COL_DARK = Color(0.1, 0.1, 0.1, 1.0)
const FONT_SIZE: int = 12
const ICON_SIZE: int = 13

static var _theme: Theme = null

static func build() -> Theme:
	if _theme != null:
		return _theme
	var theme = Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", _bevel(COL_PANEL, false, 3.0, 3.0))
	theme.set_color("font_color", "Label", COL_TEXT)

	var raised = _bevel(COL_PANEL, false, 8.0, 3.0)
	var sunken = _bevel(COL_PANEL, true, 8.0, 3.0)
	sunken.content_margin_top += 1.0
	sunken.content_margin_left += 1.0
	for style in ["normal", "hover", "disabled"]:
		theme.set_stylebox(style, "Button", raised)
	for style in ["pressed", "hover_pressed"]:
		theme.set_stylebox(style, "Button", sunken)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color, "Button", COL_TEXT)
	theme.set_color("font_disabled_color", "Button", COL_TEXT_DISABLED)

	for style in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(style, "CheckBox", _empty(2.0))
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color, "CheckBox", COL_TEXT)
	theme.set_color("font_disabled_color", "CheckBox", COL_TEXT_DISABLED)
	theme.set_constant("h_separation", "CheckBox", 5)
	for disabled in [false, true]:
		var suffix = "_disabled" if disabled else ""
		theme.set_icon("checked" + suffix, "CheckBox", _check_icon(true, false, disabled))
		theme.set_icon("unchecked" + suffix, "CheckBox", _check_icon(false, false, disabled))
		theme.set_icon("radio_checked" + suffix, "CheckBox", _check_icon(true, true, disabled))
		theme.set_icon("radio_unchecked" + suffix, "CheckBox", _check_icon(false, true, disabled))

	theme.set_stylebox("normal", "LineEdit", _bevel(COL_FIELD, true, 4.0, 2.0))
	theme.set_stylebox("read_only", "LineEdit", _bevel(COL_PANEL, true, 4.0, 2.0))
	theme.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	theme.set_color("font_color", "LineEdit", COL_TEXT)
	theme.set_color("font_uneditable_color", "LineEdit", COL_TEXT_DISABLED)
	theme.set_color("caret_color", "LineEdit", COL_TEXT)
	theme.set_color("selection_color", "LineEdit", Color(0.0, 0.0, 0.5, 1.0))
	theme.set_color("font_selected_color", "LineEdit", Color.WHITE)

	var arrow_up = _arrow_icon(true)
	var arrow_down = _arrow_icon(false)
	for state in ["", "_hover", "_pressed", "_disabled"]:
		theme.set_icon("up" + state, "SpinBox", arrow_up)
		theme.set_icon("down" + state, "SpinBox", arrow_down)
		var button_style = _bevel(COL_PANEL, state == "_pressed", 2.0, 0.0)
		theme.set_stylebox("up_background" + state, "SpinBox", button_style)
		theme.set_stylebox("down_background" + state, "SpinBox", button_style)
	theme.set_stylebox("field_and_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_stylebox("up_down_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_constant("buttons_width", "SpinBox", 14)
	_theme = theme
	return theme

static func _bevel(bg: Color, is_sunken: bool, margin_x: float, margin_y: float) -> BevelStyleBox:
	var style = BevelStyleBox.new()
	style.bg_color = bg
	style.sunken = is_sunken
	style.shadow_color = COL_SHADOW
	style.dark_color = COL_DARK
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style

static func _empty(margin: float) -> StyleBoxEmpty:
	var style = StyleBoxEmpty.new()
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

# Sunken white box or circle; a tick or a dot when checked.
static func _check_icon(checked: bool, radio: bool, disabled: bool) -> ImageTexture:
	var image = Image.create_empty(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var fill = COL_PANEL if disabled else COL_FIELD
	var mark = COL_TEXT_DISABLED if disabled else COL_TEXT
	var center = Vector2(ICON_SIZE - 1, ICON_SIZE - 1) / 2.0
	for y in range(ICON_SIZE):
		for x in range(ICON_SIZE):
			var color = Color(0, 0, 0, 0)
			if radio:
				var offset = Vector2(x, y) - center
				var distance = offset.length()
				if distance <= 4.6:
					color = fill
				elif distance <= 6.2:
					# Shadow on the upper-left half of the ring, light on the rest.
					color = COL_SHADOW if offset.x + offset.y < 0.0 else Color.WHITE
				if checked and distance <= 1.9:
					color = mark
			else:
				if x == 0 or y == 0:
					color = COL_SHADOW
				elif x == ICON_SIZE - 1 or y == ICON_SIZE - 1:
					color = Color.WHITE
				elif x == 1 or y == 1:
					color = COL_DARK
				else:
					color = fill
			image.set_pixel(x, y, color)
	if checked and !radio:
		for i in range(7):
			var x = 3 + i
			var y = 7 + i if i < 2 else 9 - (i - 2)
			image.set_pixel(x, y - 1, mark)
			image.set_pixel(x, y, mark)
			image.set_pixel(x, y - 2, mark)
	return ImageTexture.create_from_image(image)

static func _arrow_icon(up: bool) -> ImageTexture:
	var image = Image.create_empty(7, 4, false, Image.FORMAT_RGBA8)
	for row in range(4):
		var half_width = row if up else 3 - row
		for x in range(3 - half_width, 4 + half_width):
			image.set_pixel(x, row, COL_TEXT)
	return ImageTexture.create_from_image(image)
