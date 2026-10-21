@tool
class_name BevelStyleBox
extends StyleBox

# Raised or sunken frame of the console's Windows-style controls, drawn like
# draw_3d_panel on the commander screen.
@export var bg_color: Color = Color(0.76, 0.76, 0.76, 1.0)
@export var sunken: bool = false
@export var light_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var shadow_color: Color = Color(0.4, 0.4, 0.4, 1.0)
@export var dark_color: Color = Color(0.1, 0.1, 0.1, 1.0)

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	RenderingServer.canvas_item_add_rect(to_canvas_item, rect, bg_color)
	var top_left = dark_color if sunken else light_color
	var bottom_right = light_color if sunken else dark_color
	var inner_top_left = shadow_color if sunken else bg_color
	var inner_bottom_right = bg_color if sunken else shadow_color
	_add_frame(to_canvas_item, rect, top_left, bottom_right)
	_add_frame(to_canvas_item, rect.grow(-1.0), inner_top_left, inner_bottom_right)

func _add_frame(canvas_item: RID, rect: Rect2, top_left: Color, bottom_right: Color) -> void:
	RenderingServer.canvas_item_add_rect(canvas_item, Rect2(rect.position, Vector2(rect.size.x, 1.0)), top_left)
	RenderingServer.canvas_item_add_rect(canvas_item, Rect2(rect.position, Vector2(1.0, rect.size.y)), top_left)
	RenderingServer.canvas_item_add_rect(canvas_item, Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1.0), bottom_right)
	RenderingServer.canvas_item_add_rect(canvas_item, Rect2(rect.end.x - 1.0, rect.position.y, 1.0, rect.size.y), bottom_right)
