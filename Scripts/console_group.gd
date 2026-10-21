@tool
class_name ConsoleGroup
extends MarginContainer

# Etched frame with its caption set into the top edge (Windows group box).
@export var title: String = "":
	set(value):
		title = value
		queue_redraw()

const COL_BACKGROUND = Color(0.76, 0.76, 0.76, 1.0)
const COL_LIGHT = Color(1.0, 1.0, 1.0, 1.0)
const COL_SHADOW = Color(0.45, 0.45, 0.45, 1.0)
const COL_CAPTION = Color(0.0, 0.0, 0.0, 1.0)
const CAPTION_X: float = 10.0
const CAPTION_GAP: float = 3.0

func _ready() -> void:
	add_theme_constant_override("margin_left", 8)
	add_theme_constant_override("margin_top", 18)
	add_theme_constant_override("margin_right", 8)
	add_theme_constant_override("margin_bottom", 7)

func _draw() -> void:
	var font = get_theme_default_font()
	var font_size = get_theme_default_font_size()
	var line_y = floorf(font.get_height(font_size) / 2.0)
	var frame = Rect2(0.0, line_y, size.x - 1.0, size.y - line_y - 1.0)
	draw_rect(frame, COL_SHADOW, false, 1.0)
	draw_rect(Rect2(frame.position + Vector2.ONE, frame.size), COL_LIGHT, false, 1.0)
	if title.is_empty():
		return
	var caption_width = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_rect(Rect2(CAPTION_X - CAPTION_GAP, 0.0, caption_width + CAPTION_GAP * 2.0, line_y * 2.0), COL_BACKGROUND)
	draw_string(font, Vector2(CAPTION_X, font.get_ascent(font_size)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_CAPTION)
