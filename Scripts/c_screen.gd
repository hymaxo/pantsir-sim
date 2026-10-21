extends Control

const COL_BG_PANEL = Color(0.76, 0.76, 0.76, 1.0)
const COL_BG_RADAR = Color(0.0, 0.0, 0.25, 1.0)
const COL_GRID_BLUE = Color(0.0, 0.3, 0.6, 1.0)
const COL_TEXT_MAIN = Color(0.0, 0.0, 0.0, 1.0)
const COL_TEXT_WHITE = Color(1.0, 1.0, 1.0, 1.0)
const COL_TEXT_CYAN = Color(0.0, 1.0, 1.0, 1.0)
const COL_TEXT_YELLOW = Color(1.0, 1.0, 0.0, 1.0)

const COL_BTN_SHADOW = Color(0.4, 0.4, 0.4, 1.0)
const COL_BTN_HIGHLIGHT = Color(1.0, 1.0, 1.0, 1.0)
const COL_IND_GREEN = Color(0.0, 0.8, 0.0, 1.0)
const COL_IND_YELLOW = Color(0.9, 0.8, 0.2, 1.0)
const COL_IND_GREY = Color(0.6, 0.6, 0.6, 1.0)
const COL_IND_CYAN = Color(0.0, 0.8, 1.0, 1.0)
const COL_IND_RED = Color(0.8, 0.2, 0.2, 1.0)

const COL_TARGET_RED = Color(1.0, 0.2, 0.2, 1.0)
const COL_SELECTION_RED = Color(0.8, 0.0, 0.0, 1.0)

const COL_GRAPH_BG = Color(0.08, 0.03, 0.16, 1.0)
const COL_GRAPH_FRAME = Color(0.78, 0.75, 0.88, 1.0)
const COL_GRAPH_LABEL = Color(0.15, 0.85, 0.3, 1.0)
const COL_GRAPH_TURRET = Color(0.1, 0.45, 0.85, 1.0)
const COL_GRAPH_BEAM = Color(0.95, 0.6, 0.1, 1.0)
const GRAPH_H_MAX = 16000.0

const COL_FORM_TITLE = Color(0.64, 0.64, 0.66, 1.0)
const COL_FORM_HEAD = Color(0.6, 0.6, 0.6, 1.0)
const COL_FORM_HEAD_TEXT = Color(0.05, 0.05, 0.12, 1.0)
const COL_FORM_CELL = Color(0.11, 0.2, 0.4, 1.0)
const COL_FORM_CELL_SEL = Color(0.2, 0.36, 0.68, 1.0)
const COL_FORM_TROUGH = Color(0.84, 0.84, 0.84, 1.0)

var MAX_RANGE = 30000.0
var RANGE_RINGS = 6

var default_font: Font
var bold_font: FontVariation
var table_scroll_offset: int = 0
var max_visible_rows: int = 8
var row_height: float = 16.0
var table_rows_top: float = 0.0
var selected_track_id: int = -1

var rect_table_area: Rect2 = Rect2()
var rect_table_scroll: Rect2 = Rect2()
var rect_buttons: Dictionary = {}

const COL_SPZ_ACTIVE = Color(0.1, 0.25, 0.7, 1.0)
const SPZ_PRESS_ANIMATION_S: float = 0.18
var _spz_press_ms: int = -100000

func _ready():
	default_font = ThemeDB.get_fallback_font()
	bold_font = FontVariation.new()
	bold_font.base_font = default_font
	bold_font.variation_embolden = 0.7

func _process(_delta):
	MAX_RANGE = GlobalPantsirSystem.MAX_RANGE
	RANGE_RINGS = MAX_RANGE/5000
	if GlobalPantsirSystem.master_power_on:
		queue_redraw()

func _gui_input(event):
	if !GlobalPantsirSystem.master_power_on:
		draw_rect(Rect2(0,0, 2000, 2000),Color(0,0,0))
		
		return

	if event is InputEventMouseButton:
		if rect_table_area.has_point(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				table_scroll_offset += 1
				queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				table_scroll_offset = max(0, table_scroll_offset - 1)
				queue_redraw()

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pos = event.position
			if rect_table_area.has_point(pos):
				handle_table_click(pos)
			else:
				handle_button_click(pos)

func _unhandled_input(event):
	if !GlobalPantsirSystem.master_power_on: return
	
	if event.is_action_pressed("fire"):
		GlobalPantsirSystem.fire_active_weapon()

func get_sorted_tracks():
	var tracks_list = []
	for id in GlobalPantsirSystem.tracks:
		if !GlobalPantsirSystem.is_track_filtered(id):
			tracks_list.append(GlobalPantsirSystem.tracks[id])
	tracks_list.sort_custom(func(a, b): return a["id"] < b["id"])
	return tracks_list

func handle_table_click(pos: Vector2):
	if rect_table_scroll.has_point(pos):
		if pos.y < rect_table_scroll.get_center().y:
			table_scroll_offset = max(0, table_scroll_offset - 1)
		else:
			table_scroll_offset += 1
		return

	var local_y = pos.y - table_rows_top
	if local_y < 0: return
	
	var tracks_list = get_sorted_tracks()
	var clicked_row_idx = int(local_y / row_height) + table_scroll_offset
	
	if clicked_row_idx >= 0 and clicked_row_idx < tracks_list.size():
		var t = tracks_list[clicked_row_idx]
		selected_track_id = t["id"]
		GlobalPantsirSystem.lock_on_target(t["id"])

func handle_button_click(pos: Vector2):
	for key in rect_buttons:
		if rect_buttons[key].has_point(pos):
			match key:
				"BTN_SOC": GlobalPantsirSystem.soc_switch()
				"BTN_SEARCH": GlobalPantsirSystem.scan_radar_power_switch()
				"BTN_MASTER": GlobalPantsirSystem.toggle_master_power()
				"BTN_WPN_GUNS": GlobalPantsirSystem.select_weapon_guns()
				"BTN_WPN_MISSILES": GlobalPantsirSystem.select_weapon_missiles()
				"BTN_SPZ": _press_spz_button()

# The СПЗ key sinks in briefly, then the settings window opens or closes.
func _press_spz_button() -> void:
	_spz_press_ms = Time.get_ticks_msec()
	await get_tree().create_timer(SPZ_PRESS_ANIMATION_S).timeout
	var window = get_node_or_null("%SpzWindow")
	if window:
		window.toggle()

func _is_spz_window_open() -> bool:
	var window = get_node_or_null("%SpzWindow")
	return window != null and window.visible

func _draw():
	draw_rect(Rect2(Vector2.ZERO, get_size()), COL_BG_PANEL, true)
	
	if !GlobalPantsirSystem.master_power_on:
		draw_rect(Rect2(Vector2.ZERO, get_size()), Color.BLACK, true)
		return

	var w = get_size().x
	var h = get_size().y
	
	var top_h = 35.0
	var bottom_h = 30.0
	var right_panel_w = 320.0 
	var radar_w = w - right_panel_w
	
	draw_top_bar(Rect2(0, 0, w, top_h))
	draw_radar_area(Rect2(5, top_h + 5, radar_w - 10, h - top_h - bottom_h - 10))
	draw_right_panel(Rect2(radar_w, top_h, right_panel_w, h - top_h - bottom_h))
	draw_bottom_bar(Rect2(0, h - bottom_h, w, bottom_h))

func draw_top_bar(r: Rect2):
	var time_r = Rect2(r.position.x + 5, r.position.y + 2, 110, r.size.y - 4)
	draw_3d_panel(time_r, true)
	var time_str = Time.get_time_string_from_system()
	var date_str = "08.11.18"
	draw_string(default_font, time_r.position + Vector2(5, 14), date_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT_MAIN)
	draw_string(default_font, time_r.position + Vector2(60, 14), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT_MAIN)
	
	var start_x = 120
	var btn_w = 60
	var labels = ["ТР", "БР", "АБД", "ОИ", "ЗИ-СОЦ", "ЗИ-МРЛС", "ЦУ-АВТО", "ПУСК П-АВТ", "БСО", "ЛТ", "0"]
	var label_colors = [COL_IND_GREY, COL_IND_GREEN, COL_IND_GREEN, COL_IND_GREEN, COL_IND_GREY, COL_IND_GREY, COL_IND_GREY, COL_IND_YELLOW, COL_IND_GREY, COL_IND_YELLOW, COL_IND_GREY]
	var labels_width = [0.7, 4, 1, 1, 2, 2, 2, 3, 1, 1, 0.6]
	var current_x = start_x
	for i in range(labels.size()):
		var rect_width = btn_w * labels_width[i]
		var rect = Rect2(current_x, r.position.y + 2, rect_width, r.size.y - 4)
		draw_3d_panel(rect, false, label_colors[i])
		draw_string_centered(rect, labels[i], COL_TEXT_MAIN)
		current_x += rect_width + 2

func draw_radar_area(r: Rect2):
	draw_rect(r, COL_BG_RADAR, true)
	draw_rect_stroke(r, COL_BTN_SHADOW, COL_BTN_HIGHLIGHT)
	
	var center = r.get_center()
	var radius = min(r.size.x, r.size.y) / 2.0 * 0.85

	var info_pos = r.position + Vector2(10, 20)
	draw_string(default_font, info_pos, "Д = WIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_WHITE)
	draw_string(default_font, info_pos + Vector2(0, 15), "B = WIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_WHITE)
	draw_string(default_font, info_pos + Vector2(0, 30), "МАСШТАБ " + str(int(MAX_RANGE)) + " м", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_YELLOW)

	for i in range(0, 360, 30):
		var angle = deg_to_rad(i)
		var vec = Vector2(sin(angle), -cos(angle))
		var end = center + vec * radius
		draw_line(center, end, COL_GRID_BLUE, 1.0)
		var txt_pos = center + vec * (radius + 15)
		draw_string(default_font, txt_pos - Vector2(10, -5), str(i), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, COL_TEXT_CYAN)

	for i in range(1, RANGE_RINGS + 1):
		var rad = (float(i) / RANGE_RINGS) * radius
		draw_arc(center, rad, 0, TAU, 64, COL_GRID_BLUE, 1.0)
		if i <= RANGE_RINGS:
			draw_string(default_font, center + Vector2(5, -rad), str(i*5), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0.5, 0, 1))

	if GlobalPantsirSystem.search_radar_on:
		var beam_ang = GlobalPantsirSystem.search_radar_angle
		var sweep_end_1 = center + Vector2(sin(beam_ang), -cos(beam_ang)) * radius
		draw_line(center, sweep_end_1, Color.ORANGE, 3.0)
		
		var beam_ang_2 = beam_ang + PI
		var sweep_end_2 = center + Vector2(sin(beam_ang_2), -cos(beam_ang_2)) * radius
		draw_line(center, sweep_end_2, Color.ORANGE, 3.0)

	if GlobalPantsirSystem.sector_radar_on:
		var tur_ang = GlobalPantsirSystem.turret_current_angle
		var half = deg_to_rad(45)
		var p1 = center + Vector2(sin(tur_ang - half), -cos(tur_ang - half)) * radius
		var p2 = center + Vector2(sin(tur_ang + half), -cos(tur_ang + half)) * radius
		draw_line(center, p1, Color.YELLOW, 1.5)
		draw_line(center, p2, Color.YELLOW, 1.5)
		draw_arc(center, radius, tur_ang-half-PI/2, tur_ang+half-PI/2, 32, Color.YELLOW, 1.5)

	for channel in GlobalPantsirSystem.guidance_channels:
		if channel == null: continue
		var m = channel["missile"]
		if !is_instance_valid(m): continue
		
		var rel = m.global_position - GlobalPantsirSystem.pantsir_position
		var dist = rel.length()
		
		if dist < MAX_RANGE:
			var az = atan2(rel.x, -rel.z)
			var screen_pos = center + Vector2(sin(az), -cos(az)) * ((dist/MAX_RANGE)*radius)
			
			draw_circle(screen_pos, 2, Color.YELLOW)
			
			var vel = m.velocity
			if vel.length() > 1.0:
				var v_az = atan2(vel.x, -vel.z)
				var line_len = 15.0
				var end_pos = screen_pos + Vector2(sin(v_az), -cos(v_az)) * line_len
				draw_line(screen_pos, end_pos, Color.YELLOW, 1.5)

	for id in GlobalPantsirSystem.tracks:
		var t = GlobalPantsirSystem.tracks[id]
		var track_state = GlobalPantsirSystem.get_predicted_track_state(id)
		if track_state.is_empty() or GlobalPantsirSystem.is_track_filtered(id):
			continue
		var rel = track_state["position"] - GlobalPantsirSystem.pantsir_position
		var dist = rel.length()
		
		if dist < MAX_RANGE:
			var az = atan2(rel.x, -rel.z)
			var screen_pos = center + Vector2(sin(az), -cos(az)) * ((dist/MAX_RANGE)*radius)
			
			var draw_col = Color.WHITE
			
			if t["stable"]:
				draw_col = COL_TARGET_RED
			
			draw_circle(screen_pos, 3, draw_col)
			
			if t["stable"]:
				var vel: Vector3 = track_state["velocity"]
				if vel.length() > 1.0:
					var v_az = atan2(vel.x, -vel.z)
					var arrow_len = clamp(vel.length() * 0.1, 10, 40)
					var arrow_end = screen_pos + Vector2(sin(v_az), -cos(v_az)) * arrow_len
					draw_line(screen_pos, arrow_end, draw_col, 1.5)
			
			draw_string(default_font, screen_pos + Vector2(5, 0), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_WHITE)

func draw_right_panel(r: Rect2):
	var pad = 4.0
	var inner_w = r.size.x - pad*2
	
	var matrix_h = 160.0
	var matrix_rect = Rect2(r.position.x + pad, r.position.y + pad, inner_w, matrix_h)
	draw_status_matrix(matrix_rect)
	
	var mid_y = r.position.y + matrix_h + 8
	var btn_col_w = 80.0
	var btn_labels = ["ФДК", "РО", "ВЧ", "СПЗ", "Док БУСА", "ОПУ", "Излуч", "НРЗ"]
	var btn_h = 24.0
	for i in range(btn_labels.size()):
		var br = Rect2(r.position.x + pad, mid_y + i*(btn_h+2), btn_col_w, btn_h)
		if btn_labels[i] == "СПЗ":
			rect_buttons["BTN_SPZ"] = br
			draw_spz_button(br)
			continue
		draw_3d_panel(br, false)
		draw_string_centered(br, btn_labels[i], COL_TEXT_MAIN)
	
	var graph_x = r.position.x + pad + btn_col_w + 4
	var graph_w = inner_w - btn_col_w - 4
	var graph_rect = Rect2(graph_x, mid_y + 40, graph_w, 120)
	draw_azimuth_graph(graph_rect)
	
	var table_y = mid_y + (btn_labels.size() * (btn_h+2)) + 10
	var table_h = (r.position.y + r.size.y) - table_y - 5
	rect_table_area = Rect2(r.position.x + pad, table_y, inner_w, table_h)
	draw_target_formular(rect_table_area)

# Sunken while pressed; lit like a selected console key while its window is open.
func draw_spz_button(br: Rect2):
	var press_age_s = (Time.get_ticks_msec() - _spz_press_ms) / 1000.0
	var pressing = press_age_s < SPZ_PRESS_ANIMATION_S
	var open = _is_spz_window_open()
	var bg = COL_SPZ_ACTIVE if open else COL_BG_PANEL
	if pressing:
		# Flash between the key colours while it is held down.
		bg = COL_BG_PANEL.lerp(COL_SPZ_ACTIVE, 0.5 + 0.5 * sin(press_age_s * TAU / SPZ_PRESS_ANIMATION_S * 2.0))
	draw_3d_panel(br, pressing or open, bg)
	var text_rect = br
	if pressing or open:
		text_rect.position += Vector2(1, 1)
	draw_string_centered(text_rect, "СПЗ", COL_TEXT_WHITE if open else COL_TEXT_MAIN)

func draw_status_matrix(r: Rect2):
	draw_3d_panel(r, true)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 16), Color(0.5, 0.5, 0.5), true)
	draw_string_centered(Rect2(r.position.x, r.position.y, r.size.x, 16), "СОСТОЯНИЕ 1РС1-2", COL_TEXT_MAIN)
	
	var grid_y = r.position.y + 18
	var cell_w = r.size.x / 4
	var cell_h = (r.size.y - 20) / 4
	
	var statuses = ["М", "Л", "ФС", "ЗАЗ", "ЦСЗ", "СОЦ", "ОПУ", "ФИЛЬТР", "РАЗ", "ЗИ", "БИС-А", "ВРАЩ", "РО", "ПЦ", "СБР", "НРЗ"]
	var idx = 0
	for y in range(4):
		for x in range(4):
			if idx >= statuses.size(): break
			var cr = Rect2(r.position.x + x*cell_w, grid_y + y*cell_h, cell_w-1, cell_h-1)
			var col = COL_IND_GREY
			if statuses[idx] == "СОЦ" and GlobalPantsirSystem.sector_radar_on: col = COL_IND_GREEN
			if statuses[idx] == "ВРАЩ" and GlobalPantsirSystem.search_radar_on: col = COL_IND_GREEN
			
			draw_rect(cr, col, true)
			draw_rect(cr, Color.BLACK, false, 1.0)
			draw_string_centered(cr, statuses[idx], COL_TEXT_MAIN, 10)
			idx += 1

func azimuth_deg(rel: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(rel.x, -rel.z)), 360.0)

# Azimuth / height plot: β 0..360 on X, Н (km) on Y.
func draw_azimuth_graph(r: Rect2):
	draw_rect(r, COL_GRAPH_BG, true)
	draw_rect_stroke(r, COL_BTN_SHADOW, COL_BTN_HIGHLIGHT)

	var plot = Rect2(r.position.x + 16, r.position.y + 4, r.size.x - 21, r.size.y - 18)
	draw_rect(plot, COL_GRAPH_FRAME, false, 1.0)

	for i in range(1, 5):
		var y = plot.end.y - plot.size.y * (i * 4000.0 / GRAPH_H_MAX)
		var lbl = "Н" if i == 4 else str(i * 4)
		draw_string(bold_font, Vector2(r.position.x + 2, y + 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_GRAPH_LABEL)

	var x_labels = ["0", "90", "180", "270", "β"]
	for i in range(x_labels.size()):
		var x = plot.position.x + plot.size.x * i / 4.0
		var sz = bold_font.get_string_size(x_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		var lx = clamp(x - sz.x / 2.0, plot.position.x - 2, plot.end.x - sz.x + 2)
		draw_string(bold_font, Vector2(lx, r.end.y - 2), x_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_GRAPH_LABEL)

	var turret_x = plot.position.x + plot.size.x * fposmod(rad_to_deg(GlobalPantsirSystem.turret_current_angle), 360.0) / 360.0
	draw_line(Vector2(turret_x, plot.position.y + 1), Vector2(turret_x, plot.end.y - 1), COL_GRAPH_TURRET, 2.0)

	if GlobalPantsirSystem.search_radar_on:
		var beam_x = plot.position.x + plot.size.x * fposmod(rad_to_deg(GlobalPantsirSystem.search_radar_angle), 360.0) / 360.0
		draw_line(Vector2(beam_x, plot.position.y + 1), Vector2(beam_x, plot.end.y - 1), COL_GRAPH_BEAM, 1.0)

	for id in GlobalPantsirSystem.tracks:
		var t = GlobalPantsirSystem.tracks[id]
		var track_state = GlobalPantsirSystem.get_predicted_track_state(id)
		if track_state.is_empty() or GlobalPantsirSystem.is_track_filtered(id):
			continue
		var pos: Vector3 = track_state["position"]
		var rel = pos - GlobalPantsirSystem.pantsir_position
		if rel.length() >= MAX_RANGE:
			continue

		var px = plot.position.x + plot.size.x * azimuth_deg(rel) / 360.0
		var py = plot.end.y - plot.size.y * clamp(pos.y / GRAPH_H_MAX, 0.0, 1.0)
		var p = Vector2(px, clamp(py, plot.position.y + 3, plot.end.y - 3))

		if t["stable"]:
			draw_target_mark(p, COL_TARGET_RED)
			draw_string(bold_font, p + Vector2(3, -4), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TARGET_RED)
		else:
			draw_rect(Rect2(p.x - 1, p.y - 1, 3, 2), COL_TEXT_WHITE, true)

# Small "bow-tie" target symbol used on the plot and in the ТЦ column.
func draw_target_mark(c: Vector2, col: Color, s: float = 3.5):
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.8), c, c + Vector2(-s, s * 0.8)]), col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(s, -s * 0.8), c, c + Vector2(s, s * 0.8)]), col)
	draw_line(c + Vector2(s, 0), c + Vector2(s * 2.0, 0), col, 1.0)

func draw_target_formular(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	var title_h = 15.0
	var header_h = 17.0
	var gap = 2.0
	var pad = 3.0
	row_height = 16.0

	# "ФОРМУЛЯР ЦЕЛЕЙ" title strip
	var title_r = Rect2(r.position.x, r.position.y, r.size.x, title_h)
	draw_rect(title_r, COL_FORM_TITLE, true)
	draw_line(title_r.position, title_r.position + Vector2(title_r.size.x, 0), COL_BTN_SHADOW, 1.0)
	draw_line(title_r.position + Vector2(0, 1), title_r.position + Vector2(title_r.size.x, 1), COL_BTN_HIGHLIGHT, 1.0)
	draw_string_centered(title_r, "ФОРМУЛЯР ЦЕЛЕЙ", COL_FORM_HEAD_TEXT, 10, bold_font)

	var body = Rect2(r.position.x + pad, title_r.end.y + 1, r.size.x - pad * 2, r.end.y - title_r.end.y - pad - 1)
	draw_3d_panel(body, true)

	var sb_w = 12.0
	var cells_x = body.position.x + gap
	var cells_w = body.size.x - sb_w - gap * 3
	var weights = [0.75, 1.0, 1.0, 1.0, 1.0, 1.0]
	var total_w = 0.0
	for wt in weights: total_w += wt
	var col_x = []
	var col_w = []
	var cx = cells_x
	for wt in weights:
		var cw = cells_w * wt / total_w - gap
		col_x.append(cx)
		col_w.append(cw)
		cx += cw + gap

	var headers = ["№ Ц", "Аз,°", "Д, м", "Н, м", "V, м/с", "ТЦ"]
	var head_y = body.position.y + gap
	for i in range(headers.size()):
		var hr = Rect2(col_x[i], head_y, col_w[i], header_h)
		draw_3d_panel(hr, false, COL_FORM_HEAD)
		draw_string_centered(hr, headers[i], COL_FORM_HEAD_TEXT, 10, bold_font)

	var start_y = head_y + header_h + gap
	table_rows_top = start_y
	var visible_count = max(0, int((body.end.y - start_y - gap) / row_height))
	max_visible_rows = visible_count

	var tracks_list = get_sorted_tracks()
	var count = tracks_list.size()
	table_scroll_offset = clamp(table_scroll_offset, 0, max(0, count - visible_count))

	for i in range(visible_count):
		var data_idx = i + table_scroll_offset
		if data_idx >= count: break

		var t = tracks_list[data_idx]
		var track_state = GlobalPantsirSystem.get_predicted_track_state(t["id"])
		if track_state.is_empty():
			continue
		var predicted_position: Vector3 = track_state["position"]
		var predicted_velocity: Vector3 = track_state["velocity"]
		var rel = predicted_position - GlobalPantsirSystem.pantsir_position
		var vel_len = predicted_velocity.length() if t["stable"] else 0

		var vals = [
			str(t["id"]),
			str(int(azimuth_deg(rel))),
			str(int(rel.length())),
			str(int(predicted_position.y)),
			str(int(vel_len)),
			""
		]

		var y = start_y + i * row_height
		var cell_bg = COL_FORM_CELL_SEL if t["id"] == selected_track_id else COL_FORM_CELL
		for k in range(vals.size()):
			var cr = Rect2(col_x[k], y, col_w[k], row_height - gap)
			draw_rect(cr, cell_bg, true)
			if k == 0:
				draw_string_centered(cr, vals[k], COL_TARGET_RED, 11, bold_font)
			elif k == 5:
				if t["stable"]:
					draw_target_mark(cr.get_center() - Vector2(2, 0), COL_TARGET_RED, 3.5)
			else:
				draw_string_centered(cr, vals[k], COL_TEXT_WHITE, 10, bold_font)

	# Scrollbar: sunken trough with arrow buttons at both ends
	var sb = Rect2(body.end.x - sb_w - gap, head_y, sb_w, body.end.y - head_y - gap)
	rect_table_scroll = sb
	draw_rect(sb, COL_FORM_TROUGH, true)
	var up_r = Rect2(sb.position, Vector2(sb_w, sb_w))
	var down_r = Rect2(sb.position.x, sb.end.y - sb_w, sb_w, sb_w)
	draw_3d_panel(up_r, false)
	draw_3d_panel(down_r, false)
	var uc = up_r.get_center()
	var dc = down_r.get_center()
	draw_colored_polygon(PackedVector2Array([uc + Vector2(-3, 2), uc + Vector2(3, 2), uc + Vector2(0, -2)]), COL_TEXT_MAIN)
	draw_colored_polygon(PackedVector2Array([dc + Vector2(-3, -2), dc + Vector2(3, -2), dc + Vector2(0, 2)]), COL_TEXT_MAIN)

	if count > visible_count and visible_count > 0:
		var track_y = up_r.end.y
		var track_h = down_r.position.y - track_y
		var thumb_h = max(10.0, track_h * float(visible_count) / count)
		var thumb_y = track_y + (track_h - thumb_h) * table_scroll_offset / float(count - visible_count)
		draw_3d_panel(Rect2(sb.position.x, thumb_y, sb_w, thumb_h), false)

func draw_bottom_bar(r: Rect2):
	var w = r.size.x / 12
	var labels = ["АВТ-П", "ПШК", "ЗУР", "", "", "", "", "", "P", "0 %", "ЗАЛП", "ЗАЗЦ-РЛ"]
	
	for i in range(12):
		var br = Rect2(r.position.x + i*w, r.position.y, w, r.size.y)
		var col = COL_BG_PANEL
		var pressed = false
		var lbl = labels[i]
		
		if lbl == "АВТ-П":
			# Lit red while automatic fire (АО) is on.
			if GlobalPantsirSystem.auto_fire_on:
				col = COL_IND_RED
				pressed = true
		elif lbl == "ПШК":
			rect_buttons["BTN_WPN_GUNS"] = br
			if GlobalPantsirSystem.selected_weapon == "GUNS":
				col = COL_IND_CYAN
				pressed = true
		elif lbl == "ЗУР":
			rect_buttons["BTN_WPN_MISSILES"] = br
			if GlobalPantsirSystem.selected_weapon == "MISSILES":
				col = COL_IND_CYAN
				pressed = true
		elif i == 3 and GlobalPantsirSystem.is_reloading():
			# Перезарядка: firing is locked until the loader is done.
			col = COL_IND_YELLOW
			lbl = "ПЗ %d с" % ceili(GlobalPantsirSystem.reload_time_left_s)
		
		draw_3d_panel(br, pressed, col)
		draw_string_centered(br, lbl, COL_TEXT_MAIN)

func draw_3d_panel(rect: Rect2, pressed: bool, bg_color: Color = COL_BG_PANEL):
	draw_rect(rect, bg_color, true)
	var light = COL_BTN_HIGHLIGHT
	var dark = COL_BTN_SHADOW
	
	if pressed:
		draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), dark, 1.0)
		draw_line(rect.position, rect.position + Vector2(0, rect.size.y), dark, 1.0)
		draw_line(rect.end, rect.end - Vector2(rect.size.x, 0), light, 1.0)
		draw_line(rect.end, rect.end - Vector2(0, rect.size.y), light, 1.0)
	else:
		draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), light, 1.0)
		draw_line(rect.position, rect.position + Vector2(0, rect.size.y), light, 1.0)
		draw_line(rect.end, rect.end - Vector2(rect.size.x, 0), dark, 2.0)
		draw_line(rect.end, rect.end - Vector2(0, rect.size.y), dark, 2.0)

func draw_rect_stroke(rect: Rect2, col_tl: Color, col_br: Color):
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), col_tl)
	draw_line(rect.position, rect.position + Vector2(0, rect.size.y), col_tl)
	draw_line(rect.end, rect.end - Vector2(rect.size.x, 0), col_br)
	draw_line(rect.end, rect.end - Vector2(0, rect.size.y), col_br)

func draw_string_centered(rect: Rect2, text: String, col: Color, size: int = 12, font: Font = null):
	if font == null: font = default_font
	var sz = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	var pos = rect.get_center() + Vector2(-sz.x/2, sz.y/4)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)
