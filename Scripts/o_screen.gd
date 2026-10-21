extends Control

const COL_BG_PANEL = Color(0.76, 0.76, 0.76, 1.0)
const COL_BG_PANEL_DARK = Color(0.55, 0.55, 0.55, 1.0)
const COL_BG_RADAR_SECTOR = Color(0.65, 0.35, 0.75, 1.0)
const COL_RADAR_ACTIVE = Color(0.95, 0.95, 0.2, 1.0)
const COL_GRID = Color(0.34, 0.34, 0.36, 0.78)
const COL_DIAGRAM_BG = Color(0.82, 0.82, 0.80, 1.0)
const COL_TEXT_MAIN = Color(0.0, 0.0, 0.0, 1.0)
const COL_TEXT_GUI = Color(0.85, 0.85, 0.85, 1.0)
const COL_TEXT_CYAN = Color(0.0, 1.0, 1.0, 1.0)
const COL_TEXT_GREEN = Color(0.0, 1.0, 0.0, 1.0)
const COL_TEXT_YELLOW = Color(1.0, 1.0, 0.0, 1.0)
const COL_RED_DOT = Color(1.0, 0.0, 0.0, 1.0)
const COL_RED_BTN = Color(0.85, 0.1, 0.1, 1.0)
const COL_GREEN_BOX = Color(0.0, 0.6, 0.0, 1.0)

const COL_BTN_SHADOW = Color(0.4, 0.4, 0.4, 1.0)
const COL_BTN_HIGHLIGHT = Color(1.0, 1.0, 1.0, 1.0)
const COL_IND_GREY = Color(0.6, 0.6, 0.6, 1.0)
const COL_IND_GREEN = Color(0.0, 0.8, 0.0, 1.0)
const COL_IND_YELLOW = Color(0.75, 0.7, 0.0, 1.0)
const COL_LAUNCH_ALLOWED = Color(0.16, 0.58, 0.20, 1.0)
const COL_LAUNCH_INNER_RANGE = Color(0.95, 0.12, 0.10, 1.0)
const COL_LAUNCH_SHADOW = Color(0.08, 0.11, 0.08, 0.45)
const COL_LAUNCH_HIGHLIGHT = Color(0.88, 0.88, 0.82, 0.55)
const COL_TARGET_MAGENTA = Color(0.85, 0.0, 0.55, 1.0)
const COL_GRID_LABEL = Color(0.22, 0.22, 0.32, 1.0)
const COL_ANGLE_BOX = Color(0.96, 0.96, 0.94, 1.0)

# Vertical-plane zone (Д/Н) proportions taken from the reference console.
const ZONE_RANGE_M = 36000.0
const ZONE_HEIGHT_M = 20000.0
const ZONE_CEILING_M = 12500.0
const ZONE_MAX_ELEVATION = 1.3613568 # 78 degrees

const OPTIC_BASE_FOV: float = 60.0
const OPTIC_MIN_FOV: float = 1.0
const ZOOM_SMOOTH_SPEED: float = 12.0
const OBJECT_FRAME_PADDING: float = 2.0
const OBJECT_FRAME_MIN_SIZE: float = 8.0
const OBJECT_FRAME_CORNER_RATIO: float = 0.18
const OBJECT_FRAME_MAX_CORNER_LENGTH: float = 10.0
const LAUNCH_FLASH_DURATION_S: float = 1.8
const LAUNCH_FLASH_PEAK_ALPHA: float = 0.85

var default_font: Font
var rect_buttons: Dictionary = {}

var thermal_shader_code = preload("res://Thermal.gdshader")

@onready var camera_container = $CameraContainer
@onready var viewport = $CameraContainer/SubViewport
@onready var camera_3d = $CameraContainer/SubViewport/OpticCamera

func _ready():
	default_font = ThemeDB.get_fallback_font()

	camera_container.stretch = true
	viewport.size_2d_override_stretch = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	camera_container.show_behind_parent = true

	camera_3d.far = 100000.0
	camera_3d.near = 0.1
	camera_3d.cull_mask = 4294967295
	camera_3d.current = true

	var world_node = get_tree().root.find_child("World3D", true, false)
	if world_node:
		viewport.world_3d = world_node.get_world_3d()

	setup_thermal_vision()

func setup_thermal_vision():
	var mat = ShaderMaterial.new()
	mat.shader = thermal_shader_code
	mat.set_shader_parameter("contrast", 2.5)
	mat.set_shader_parameter("noise_amount", 0.08)
	mat.set_shader_parameter("brightness", -0.05)
	camera_container.material = mat

	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	camera_3d.environment = env

func _process(delta):
	if !visible or !GlobalPantsirSystem.master_power_on:
		return

	if Input.is_action_pressed("fire"):
		GlobalPantsirSystem.fire_active_weapon()

	update_camera_transform()
	update_camera_zoom(delta)
	queue_redraw()

func update_camera_transform():
	var pos = GlobalPantsirSystem.pantsir_position + Vector3(0, 3.5, 0)
	camera_3d.global_position = pos

	camera_3d.rotation = Vector3.ZERO
	camera_3d.rotation.y = -GlobalPantsirSystem.optic_current_angle
	camera_3d.rotation.x = GlobalPantsirSystem.optic_current_pitch

func update_camera_zoom(delta: float):
	var target_fov = clampf(
		OPTIC_BASE_FOV / GlobalPantsirSystem.manual_zoom_factor,
		OPTIC_MIN_FOV,
		OPTIC_BASE_FOV
	)
	var smoothing_weight = 1.0 - exp(-ZOOM_SMOOTH_SPEED * delta)
	camera_3d.fov = lerpf(camera_3d.fov, target_fov, smoothing_weight)

func _gui_input(event):
	if !GlobalPantsirSystem.master_power_on: return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		handle_button_click(event.position)

func _unhandled_input(event):
	if !visible or !GlobalPantsirSystem.master_power_on: return

	if event.is_action_pressed("zoom_inc"):
		GlobalPantsirSystem.zoom_inc()
	elif event.is_action_pressed("zoom_dec"):
		GlobalPantsirSystem.zoom_dec()

	if event.is_action_pressed("fire") and GlobalPantsirSystem.selected_weapon == "MISSILES":
		GlobalPantsirSystem.fire_active_weapon()

func handle_button_click(pos: Vector2):
	for key in rect_buttons:
		if rect_buttons[key].has_point(pos):
			match key:
				"BTN_SOC": GlobalPantsirSystem.scan_radar_power_switch()
				"BTN_MRLS": GlobalPantsirSystem.soc_switch()
				"BTN_MASTER": GlobalPantsirSystem.toggle_master_power()
				"BTN_WPN_GUNS": GlobalPantsirSystem.select_weapon_guns()
				"BTN_WPN_MISSILES": GlobalPantsirSystem.select_weapon_missiles()

func _draw():
	if !GlobalPantsirSystem.master_power_on:
		draw_rect(Rect2(Vector2.ZERO, get_size()), Color.BLACK, true)
		camera_container.visible = false
		return

	camera_container.visible = true

	var w = get_size().x
	var h = get_size().y

	var top_h = 31.0
	var toolbar2_h = 35.0
	var bottom_bar_h = 26.0
	var bottom_panels_h = 140.0
	# The reference console gives the diagrams a little over a quarter of the CRT.
	# Keeping a minimum width also prevents the polar grids from collapsing.
	var right_panel_w = clamp(w * 0.265, 310.0, 340.0)
	var main_view_w = w - right_panel_w

	draw_top_bar(Rect2(0, 0, w, top_h))
	draw_icon_toolbar(Rect2(0, top_h, w, toolbar2_h))

	var view_top = top_h + toolbar2_h
	var view_bottom = h - bottom_bar_h - bottom_panels_h
	var view_rect = Rect2(0, view_top, main_view_w, view_bottom - view_top)
	draw_optic_view(view_rect)

	var right_rect = Rect2(main_view_w, view_top, right_panel_w, view_bottom - view_top)
	draw_right_panel(right_rect)

	var panels_rect = Rect2(0, view_bottom, w, bottom_panels_h)
	draw_bottom_panels(panels_rect)

	draw_bottom_bar(Rect2(0, h - bottom_bar_h, w, bottom_bar_h))

func draw_top_bar(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	# One continuous proportional grid, matching the spacing of the operator panel.
	var labels = ["12.09.19", Time.get_time_string_from_system(), "", "БР", "АБД", "ОИ", "", "", "", "ПУСК П-АВТ", "", "ЛТ", ""]
	var colors = [
		COL_BG_PANEL_DARK, COL_BG_PANEL_DARK, COL_IND_GREY,
		COL_IND_GREEN, COL_IND_GREEN, COL_IND_GREEN,
		COL_IND_GREY, COL_IND_GREY, COL_IND_GREY,
		COL_IND_YELLOW, COL_IND_GREY, COL_IND_YELLOW, COL_IND_GREY,
	]
	var weights = [1.05, 1.05, 0.55, 2.35, 1.15, 1.15, 1.45, 1.45, 1.45, 2.40, 0.85, 0.85, 0.55]
	var gap = 2.0
	var outer_margin = 3.0
	var total_weight = 0.0
	for weight in weights:
		total_weight += weight
	var unit = (r.size.x - outer_margin * 2.0 - gap * (weights.size() - 1)) / total_weight
	var x = r.position.x + outer_margin

	for i in range(labels.size()):
		var cell_width = unit * weights[i]
		var cell = Rect2(x, r.position.y + 2.0, cell_width, r.size.y - 4.0)
		draw_3d_panel(cell, i < 2, colors[i])
		if !labels[i].is_empty():
			draw_string_centered(cell, labels[i], COL_TEXT_MAIN, 11)
		x += cell_width + gap

func draw_icon_toolbar(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	var gap = 2.0
	var margin = 4.0
	var left_labels = ["ИД", "", "СИ"]
	var left_widths = [42.0, 30.0, 42.0]
	var alg_w = 42.0
	var empty_count = 18
	var occupied = margin * 2.0 + gap * (left_labels.size() + empty_count + 1) + alg_w * 2.0
	for width in left_widths:
		occupied += width
	var empty_width = (r.size.x - occupied) / empty_count
	var x = r.position.x + margin

	for i in range(left_labels.size()):
		var cell = Rect2(x, r.position.y + 2.0, left_widths[i], r.size.y - 4.0)
		draw_3d_panel(cell, false)
		if !left_labels[i].is_empty():
			draw_string_centered(cell, left_labels[i], COL_TEXT_MAIN, 11)
		x += left_widths[i] + gap

	# Every former icon key is intentionally blank, but keeps its physical slot.
	for i in range(empty_count):
		var cell = Rect2(x, r.position.y + 2.0, empty_width, r.size.y - 4.0)
		draw_3d_panel(cell, false)
		x += empty_width + gap

	for alg_lbl in ["Alg1", "Alg2"]:
		var cell = Rect2(x, r.position.y + 2.0, alg_w, r.size.y - 4.0)
		draw_3d_panel(cell, false)
		draw_string_centered(cell, alg_lbl, COL_TEXT_MAIN, 10)
		x += alg_w + gap

func draw_optic_view(r: Rect2):
	camera_container.position = r.position
	camera_container.size = r.size

	# Launch flare: the thermal picture whites out, then recovers. Symbology is
	# drawn afterwards, so it stays readable on top of the glare.
	var since_launch = GlobalPantsirSystem.get_simulation_time_s() - GlobalPantsirSystem.last_missile_launch_time_s
	if since_launch >= 0.0 and since_launch < LAUNCH_FLASH_DURATION_S:
		var flash_alpha = LAUNCH_FLASH_PEAK_ALPHA * (1.0 - since_launch / LAUNCH_FLASH_DURATION_S)
		draw_rect(r, Color(0.86, 0.86, 0.84, flash_alpha), true)

	var center = r.get_center()
	var cross_size = 70.0
	var gap = 18.0
	var thick = 2.0

	draw_line(center - Vector2(cross_size, 0), center - Vector2(gap, 0), Color.BLACK, thick + 2)
	draw_line(center + Vector2(gap, 0), center + Vector2(cross_size, 0), Color.BLACK, thick + 2)
	draw_line(center - Vector2(0, cross_size), center - Vector2(0, gap), Color.BLACK, thick + 2)
	draw_line(center + Vector2(0, gap), center + Vector2(0, cross_size), Color.BLACK, thick + 2)

	draw_line(center - Vector2(cross_size, 0), center - Vector2(gap, 0), Color.WHITE, thick)
	draw_line(center + Vector2(gap, 0), center + Vector2(cross_size, 0), Color.WHITE, thick)
	draw_line(center - Vector2(0, cross_size), center - Vector2(0, gap), Color.WHITE, thick)
	draw_line(center + Vector2(0, gap), center + Vector2(0, cross_size), Color.WHITE, thick)

	draw_visible_object_markers(r)

	var font_size = 20
	# One mode label, the furthest stage of work on the target:
	# ДПЦ → АС → П-РЛ / ЦУ (last missile's phase). АСЛ has its own place at
	# the bottom right.
	var stage_text = ""
	if GlobalPantsirSystem.locked_track_id != -1 and !GlobalPantsirSystem.mrls_mode.is_empty():
		stage_text = GlobalPantsirSystem.mrls_mode
		var missile_phase = GlobalPantsirSystem.get_missile_phase_for_target(GlobalPantsirSystem.locked_track_id)
		if !missile_phase.is_empty():
			stage_text = missile_phase
	if !stage_text.is_empty():
		draw_string(default_font, r.position + Vector2(40, 270), stage_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)

	var signature_class = GlobalPantsirSystem.get_target_classification(GlobalPantsirSystem.locked_track_id)
	if !signature_class.is_empty():
		draw_string(default_font, r.position + Vector2(40, r.size.y - 100), signature_class, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)
	draw_string(default_font, r.position + Vector2(40, r.size.y - 70), "НС", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)

	var missile_range = GlobalPantsirSystem.get_nearest_guided_missile_range_to_locked_target()
	var missile_range_text = "----" if missile_range < 0.0 else str(int(round(missile_range)))
	# Range to the missile in flight sits on the target range line, as on the console.
	draw_string(default_font, r.position + Vector2(150, r.size.y - 40), missile_range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)

	# Range to the target, right of НС.
	var target_range = GlobalPantsirSystem.get_locked_target_distance()
	var target_range_text = "----" if target_range < 0.0 else str(int(round(target_range)))
	draw_string(default_font, r.position + Vector2(150, r.size.y - 70), target_range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)
	# Время работы в боевом режиме, whole seconds.
	draw_string(default_font, r.position + Vector2(40, r.size.y - 40), "%dБр" % int(GameSettings.combat_mode_time_s), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)

	var right_x = r.position.x + r.size.x - 90
	draw_string(default_font, Vector2(right_x, r.position.y + 50), "117", HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, COL_TEXT_GUI)
	draw_string(default_font, Vector2(right_x, r.position.y + 80), "9", HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, COL_TEXT_GUI)

	var scale_x = r.position.x + r.size.x - 50
	var scale_top_y = r.position.y + 145.0
	var scale_bottom_y = r.end.y - 45.0
	var scale_tick_count = 13
	for i in range(scale_tick_count):
		var tick_ratio = float(i) / float(scale_tick_count - 1)
		var tick_y = lerp(scale_top_y, scale_bottom_y, tick_ratio)
		var tick_length = 10.0 if i == 0 or i == scale_tick_count - 1 else 7.0
		draw_line(Vector2(scale_x, tick_y), Vector2(scale_x + tick_length, tick_y), COL_TEXT_GUI, 1.0)

	# Elevation scale limits and the current visor elevation marker.
	draw_string(default_font, Vector2(scale_x - 42.0, scale_top_y + 6.0), "82", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)
	draw_string(default_font, Vector2(scale_x - 42.0, scale_bottom_y + 6.0), "-10", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)
	var visor_pitch_deg = clamp(rad_to_deg(GlobalPantsirSystem.optic_current_pitch), -10.0, 82.0)
	var marker_ratio = (82.0 - visor_pitch_deg) / 92.0
	var marker_y = lerp(scale_top_y, scale_bottom_y, marker_ratio)
	var marker_points = PackedVector2Array([
		Vector2(scale_x - 2.0, marker_y),
		Vector2(scale_x - 15.0, marker_y - 6.0),
		Vector2(scale_x - 15.0, marker_y + 6.0),
		Vector2(scale_x - 2.0, marker_y),
	])
	draw_polyline(marker_points, Color.BLACK, 3.5)
	draw_polyline(marker_points, Color.WHITE, 1.5)

	draw_string(default_font, Vector2(r.position.x + r.size.x - 275, r.position.y + r.size.y - 40), "255", HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, COL_TEXT_GUI)
	# АСЛ: the visor is locked on the target (its own indicator, separate
	# from the radar stage in the left column).
	if GlobalPantsirSystem.is_visor_auto_tracking():
		draw_string(default_font, Vector2(r.position.x + r.size.x - 228, r.position.y + r.size.y - 40), "АСЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)

	# Р — ракеты, П — пушки. The letter is a separate field left of the scale limit.
	var weapon_letter = "П" if GlobalPantsirSystem.selected_weapon == "GUNS" else "Р"
	draw_string(default_font, Vector2(scale_x - 76.0, scale_bottom_y + 6.0), weapon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_GUI)

	# Missile icon left of the weapon letter: shown only from launch until the
	# missiles in flight are gone, and then blinking.
	if GlobalPantsirSystem.selected_weapon == "MISSILES":
		var in_flight = GlobalPantsirSystem.is_missile_launch_preparing() or _has_missile_in_flight()
		if in_flight and _blink_on():
			_draw_missile_icon(Vector2(scale_x - 98.0, scale_bottom_y + 6.0))

	var ammo_str = ""
	if GlobalPantsirSystem.selected_weapon == "GUNS":
		ammo_str = "ПШК-" + str(GlobalPantsirSystem.ammo_guns)
	else:
		# The small missile has its own counter prefix.
		var missile_prefix = "ТКБ-" if GlobalPantsirSystem.selected_missile_type == GlobalPantsirSystem.MISSILE_TKB_1055 else "ЗУР-"
		ammo_str = missile_prefix + str(GlobalPantsirSystem.ammo_missiles)

	draw_string(default_font, Vector2(r.position.x + r.size.x - 10, r.position.y + 30), ammo_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, COL_TEXT_GUI)
	if GlobalPantsirSystem.locked_track_id != -1:
		var guidance_mode = GlobalPantsirSystem.get_guidance_mode_for_target(GlobalPantsirSystem.locked_track_id)
		var mode_text = "МЕТОД " + guidance_mode
		var mode_position = Vector2(r.position.x + r.size.x - 12, r.position.y + 58)
		draw_string(default_font, mode_position + Vector2(1, 1), mode_text, HORIZONTAL_ALIGNMENT_RIGHT, 150, 18, Color.BLACK)
		draw_string(default_font, mode_position, mode_text, HORIZONTAL_ALIGNMENT_RIGHT, 150, 18, COL_TEXT_CYAN)

func draw_target_corner_markers(rect: Rect2):
	# Black underlay keeps the white acquisition corners visible on hot targets.
	draw_target_corner_lines(rect, Color.BLACK, 3.0)
	draw_target_corner_lines(rect, Color.WHITE, 1.5)

func draw_target_corner_lines(rect: Rect2, color: Color, width: float):
	var corner_length = minf(
		minf(rect.size.x, rect.size.y) * OBJECT_FRAME_CORNER_RATIO,
		OBJECT_FRAME_MAX_CORNER_LENGTH
	)
	var top_left = rect.position
	var top_right = Vector2(rect.end.x, rect.position.y)
	var bottom_left = Vector2(rect.position.x, rect.end.y)
	var bottom_right = rect.end

	draw_line(top_left, top_left + Vector2(corner_length, 0.0), color, width)
	draw_line(top_left, top_left + Vector2(0.0, corner_length), color, width)
	draw_line(top_right, top_right - Vector2(corner_length, 0.0), color, width)
	draw_line(top_right, top_right + Vector2(0.0, corner_length), color, width)
	draw_line(bottom_left, bottom_left + Vector2(corner_length, 0.0), color, width)
	draw_line(bottom_left, bottom_left - Vector2(0.0, corner_length), color, width)
	draw_line(bottom_right, bottom_right - Vector2(corner_length, 0.0), color, width)
	draw_line(bottom_right, bottom_right - Vector2(0.0, corner_length), color, width)

func draw_visible_object_markers(view_rect: Rect2) -> void:
	var marked_instances: Dictionary = {}
	for target in get_tree().get_nodes_in_group("radar_targets"):
		_draw_object_marker(target, view_rect, marked_instances)
	for missile in get_tree().get_nodes_in_group("pantsir_missiles"):
		_draw_object_marker(missile, view_rect, marked_instances)

func _draw_object_marker(object: Node, view_rect: Rect2, marked_instances: Dictionary) -> void:
	if !is_instance_valid(object) or !(object is Node3D):
		return
	var instance_id = object.get_instance_id()
	if marked_instances.has(instance_id):
		return
	marked_instances[instance_id] = true

	var object_3d := object as Node3D
	if !_has_precise_track(object_3d):
		return
	var projected_rect = _projected_visual_rect(object_3d)
	if !projected_rect.has_area():
		return
	projected_rect = _ensure_minimum_frame_size(projected_rect, OBJECT_FRAME_MIN_SIZE)
	projected_rect = projected_rect.grow(OBJECT_FRAME_PADDING)
	projected_rect = projected_rect.intersection(view_rect.grow(-1.0))
	if projected_rect.has_area():
		draw_target_corner_markers(projected_rect)

# Frames mark what the МРЛС actually tracks: targets with a precise (АС) track
# and own missiles once the radar has found them (ЦУ). Nothing is framed while
# допоиск is still running.
func _has_precise_track(object: Node3D) -> bool:
	if "radar_id" in object:
		return GlobalPantsirSystem.is_target_tracked_precisely(object.radar_id)
	for channel in GlobalPantsirSystem.guidance_channels:
		if channel != null and channel["missile"] == object:
			return GlobalPantsirSystem.get_missile_phase(channel) == GlobalPantsirSystem.MISSILE_PHASE_COMMAND
	return false

func _projected_visual_rect(object: Node3D) -> Rect2:
	var min_point = Vector2(INF, INF)
	var max_point = Vector2(-INF, -INF)
	var has_projected_point = false
	var meshes: Array[Node] = []
	if object is MeshInstance3D:
		meshes.append(object)
	meshes.append_array(object.find_children("*", "MeshInstance3D", true, false))

	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or !mesh_instance.is_visible_in_tree():
			continue
		var mesh_aabb = mesh_instance.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var local_corner = mesh_aabb.position + mesh_aabb.size * Vector3(x, y, z)
					var world_corner = mesh_instance.global_transform * local_corner
					if camera_3d.is_position_behind(world_corner):
						continue
					var screen_corner = _world_to_optic_screen(world_corner)
					min_point = min_point.min(screen_corner)
					max_point = max_point.max(screen_corner)
					has_projected_point = true

	if !has_projected_point:
		return Rect2()
	return Rect2(min_point, max_point - min_point)

func _world_to_optic_screen(world_position: Vector3) -> Vector2:
	var viewport_size = Vector2(viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return camera_container.position
	var viewport_position = camera_3d.unproject_position(world_position)
	return camera_container.position + viewport_position * (camera_container.size / viewport_size)

func _ensure_minimum_frame_size(rect: Rect2, minimum_size: float) -> Rect2:
	var frame_size = Vector2(maxf(rect.size.x, minimum_size), maxf(rect.size.y, minimum_size))
	return Rect2(rect.get_center() - frame_size * 0.5, frame_size)

func draw_right_panel(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	# Status banner
	var status_text = "ПУСК ЗАПРЕЩЕН"
	var bg_color = Color(0.8, 0.0, 0.0, 1.0)
	var txt_color = Color.WHITE

	var permission = GlobalPantsirSystem.get_launch_permission()
	if permission["allowed"]:
		status_text = "ПУСК РАЗРЕШЕН"
		if GlobalPantsirSystem.selected_weapon == "GUNS":
			bg_color = COL_TEXT_GREEN
			txt_color = Color.BLACK
		else:
			bg_color = COL_LAUNCH_ALLOWED
			txt_color = COL_LAUNCH_INNER_RANGE if permission["inner"] else Color.WHITE

	# The reference console uses a compact lamp at the upper-left, not a full-width strip.
	var banner_h = 25.0
	var banner_w = clampf(r.size.x * 0.48, 148.0, 164.0)
	var banner_rect = Rect2(r.position + Vector2(6.0, 3.0), Vector2(banner_w, banner_h))
	var shadow_rect = banner_rect.grow(1.0)
	draw_rect(shadow_rect, COL_LAUNCH_SHADOW, true)
	draw_rect(banner_rect, bg_color, true)
	draw_line(banner_rect.position, Vector2(banner_rect.end.x, banner_rect.position.y), COL_LAUNCH_HIGHLIGHT, 1.0)
	draw_line(banner_rect.position, Vector2(banner_rect.position.x, banner_rect.end.y), COL_LAUNCH_HIGHLIGHT, 1.0)
	draw_line(banner_rect.end, Vector2(banner_rect.position.x, banner_rect.end.y), COL_BTN_SHADOW, 1.0)
	draw_line(banner_rect.end, Vector2(banner_rect.end.x, banner_rect.position.y), COL_BTN_SHADOW, 1.0)
	draw_string_centered(banner_rect, status_text, txt_color, 11)

	# Sector diagrams
	var diag_y = banner_rect.end.y + 3.0
	var diagrams_h = r.size.y - (diag_y - r.position.y) - 154.0
	var elevation_h = diagrams_h * 0.46
	var azimuth_h = diagrams_h - elevation_h - 4.0

	var elevation_rect = Rect2(r.position.x + 6, diag_y, r.size.x - 12, elevation_h)
	draw_elevation_quadrant(elevation_rect)

	var pi_rect = Rect2(r.position.x + 6, elevation_rect.end.y + 4, r.size.x - 12, azimuth_h)
	draw_pi_sector(pi_rect)

	# Channels table (bottom)
	var table_h = 150.0
	var table_y = r.position.y + r.size.y - table_h
	var table_rect = Rect2(r.position.x, table_y, r.size.x, table_h)
	draw_channels_table(table_rect)

func draw_elevation_quadrant(r: Rect2):
	draw_rect(r, COL_DIAGRAM_BG, true)
	draw_rect(r, COL_BTN_SHADOW, false, 1.0)

	# Vertical-plane engagement zone: horizontal range Д against height Н, one
	# scale for both axes. The vehicle sits at the bottom-right corner. The zone
	# is bounded by the ground, the far slant-range arc (left), the ceiling (top)
	# and the maximum elevation line (right). Yellow is below the zone ceiling.
	var px_per_m = minf((r.size.x - 64.0) / ZONE_RANGE_M, (r.size.y - 30.0) / ZONE_HEIGHT_M)
	var zone_size = Vector2(ZONE_RANGE_M, ZONE_HEIGHT_M) * px_per_m
	var frame = {
		"origin": Vector2(r.get_center().x + zone_size.x * 0.5 - 4.0, r.get_center().y + zone_size.y * 0.5 - 1.0),
		"scale": px_per_m,
	}

	draw_colored_polygon(_zone_band(frame, 0.0, ZONE_CEILING_M), COL_RADAR_ACTIVE)
	draw_colored_polygon(_zone_band(frame, ZONE_CEILING_M, ZONE_HEIGHT_M), COL_BG_RADAR_SECTOR)

	# Range verticals every 5 km and height lines every 2.5 km, clipped to the zone.
	var range_step = 5000.0
	var d = range_step
	while d < ZONE_RANGE_M:
		var top_h = minf(ZONE_HEIGHT_M, minf(sqrt(ZONE_RANGE_M * ZONE_RANGE_M - d * d), d * tan(ZONE_MAX_ELEVATION)))
		draw_line(_zone_point(frame, d, 0.0), _zone_point(frame, d, top_h), COL_GRID, 1.0)
		d += range_step
	var h = 2500.0
	while h < ZONE_HEIGHT_M:
		draw_line(_zone_point(frame, h / tan(ZONE_MAX_ELEVATION), h), _zone_point(frame, sqrt(ZONE_RANGE_M * ZONE_RANGE_M - h * h), h), COL_GRID, 1.0)
		h += 2500.0

	# Elevation rays fanning out of the vehicle position.
	for elevation_deg in [5, 10, 15, 20, 25, 30, 40, 55]:
		var angle = deg_to_rad(float(elevation_deg))
		var slant = minf(ZONE_RANGE_M, ZONE_HEIGHT_M / sin(angle))
		var ray_end = _zone_point(frame, slant * cos(angle), slant * sin(angle))
		draw_line(frame["origin"], ray_end, COL_GRID, 1.0)
		if elevation_deg == 10 or elevation_deg == 20:
			draw_string(default_font, ray_end + Vector2(-22, 4), "%d°" % elevation_deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_GRID_LABEL)

	var outline = _zone_band(frame, 0.0, ZONE_HEIGHT_M)
	outline.append(outline[0])
	draw_polyline(outline, COL_BTN_SHADOW, 1.0)

	# Axis labels: range under the ground line, height to the right of the vehicle.
	for km in [10, 20, 30]:
		var p = _zone_point(frame, km * 1000.0, 0.0)
		draw_string(default_font, p + Vector2(-6, 11), str(km), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_GRID_LABEL)
	draw_string(default_font, _zone_point(frame, ZONE_RANGE_M, 0.0) + Vector2(-24, 11), "Д, км", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_GRID_LABEL)
	for km in [10, 20]:
		var p = Vector2(frame["origin"].x + 6.0, _zone_point(frame, 0.0, km * 1000.0).y)
		draw_string(default_font, p + Vector2(0, 3), str(km), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_GRID_LABEL)
	draw_string(default_font, Vector2(frame["origin"].x + 6.0, _zone_point(frame, 0.0, ZONE_HEIGHT_M).y - 6.0), "Н, км", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_GRID_LABEL)

	# Known tracks at their horizontal range and height.
	for track_id in GlobalPantsirSystem.tracks:
		var track_state = GlobalPantsirSystem.get_predicted_track_state(track_id)
		if track_state.is_empty() or GlobalPantsirSystem.is_track_filtered(track_id):
			continue
		var relative = track_state["position"] - GlobalPantsirSystem.pantsir_position
		var track_range = Vector2(relative.x, relative.z).length()
		if track_range > ZONE_RANGE_M or relative.y < 0.0 or relative.y > ZONE_HEIGHT_M:
			continue
		var is_locked = track_id == GlobalPantsirSystem.locked_track_id
		draw_circle(_zone_point(frame, track_range, relative.y), 3.0 if is_locked else 2.5, COL_TARGET_MAGENTA if is_locked else COL_TEXT_MAIN)

func _zone_point(frame: Dictionary, range_m: float, height_m: float) -> Vector2:
	return frame["origin"] + Vector2(-range_m, -height_m) * frame["scale"]

# Zone slice between two heights: max-elevation line on the near side, the
# slant-range arc on the far side.
func _zone_band(frame: Dictionary, low_m: float, high_m: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	points.append(_zone_point(frame, low_m / tan(ZONE_MAX_ELEVATION), low_m))
	var steps = 16
	for i in range(steps + 1):
		var height_m = lerpf(low_m, high_m, float(i) / steps)
		points.append(_zone_point(frame, sqrt(ZONE_RANGE_M * ZONE_RANGE_M - height_m * height_m), height_m))
	points.append(_zone_point(frame, high_m / tan(ZONE_MAX_ELEVATION), high_m))
	return points

func draw_pi_sector(r: Rect2):
	draw_rect(r, COL_DIAGRAM_BG, true)
	draw_rect(r, COL_BTN_SHADOW, false, 1.0)

	# Relative azimuth view. The yellow acquisition sector is fixed around the
	# forward axis; targets and the fine cursor move inside this coordinate frame.
	var c = Vector2(r.get_center().x, r.end.y - 18.0)
	var radius = min(r.size.x * 0.46, r.size.y - 28.0)

	# filled half-disk background
	var seg = 48
	var sector_pts = make_sector_polygon(c, radius, PI, TAU, seg)
	draw_colored_polygon(sector_pts, COL_BG_RADAR_SECTOR)

	# SECTOR_WIDTH_RAD is the half-width used by radar logic (±45 degrees).
	# Deliberately do not add optic/turret angle here: this wedge must not rotate.
	var beam_center = PI * 1.5
	var beam_half_width = GlobalPantsirSystem.SECTOR_WIDTH_RAD
	var beam_pts = make_sector_polygon(c, radius, beam_center - beam_half_width, beam_center + beam_half_width, 24)
	draw_colored_polygon(beam_pts, COL_RADAR_ACTIVE)

	# Polar grid: concentric range arcs and relative-bearing rays.
	for ring in range(1, 5):
		draw_arc(c, radius * ring / 4.0, PI, TAU, 24, COL_GRID, 1.0)
	for bearing_deg in range(-90, 91, 15):
		var angle = beam_center + deg_to_rad(float(bearing_deg))
		var ray_end = c + Vector2(cos(angle), sin(angle)) * radius
		draw_line(c, ray_end, COL_GRID, 1.0)

	draw_arc(c, radius, PI, TAU, seg, COL_TEXT_MAIN, 1.0)
	draw_line(c - Vector2(radius, 0), c + Vector2(radius, 0), COL_TEXT_MAIN, 1.0)

	# Current optic bearing is shown independently from the stationary yellow sector.
	var relative_optic = clamp(GlobalPantsirSystem.angle_difference(GlobalPantsirSystem.turret_current_angle, GlobalPantsirSystem.optic_current_angle), -PI / 2.0, PI / 2.0)
	var cursor_angle = beam_center + relative_optic
	draw_line(c, c + Vector2(cos(cursor_angle), sin(cursor_angle)) * radius, Color(COL_RED_BTN, 0.82), 1.2)
	draw_circle(c, 2.5, COL_RED_BTN)

	# Tick marks and compact relative-bearing labels.
	for i in range(13):
		var ang = PI + i * PI / 12.0
		var p1 = c + Vector2(cos(ang), sin(ang)) * radius
		var p2 = c + Vector2(cos(ang), sin(ang)) * (radius + 4.0)
		draw_line(p1, p2, COL_TEXT_MAIN, 1.0)
	for bearing_deg in [-90, -45, 0, 45, 90]:
		var label_angle = beam_center + deg_to_rad(float(bearing_deg))
		var label_pos = c + Vector2(cos(label_angle), sin(label_angle)) * (radius + 11.0)
		var label_x = clamp(label_pos.x - 9.0, r.position.x + 2.0, r.end.x - 24.0)
		draw_string(default_font, Vector2(label_x, label_pos.y + 4.0), "%+d" % bearing_deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_MAIN)

	# Tracks are displayed relative to the turret, so the scope remains stable.
	for track_id in GlobalPantsirSystem.tracks:
		var track_state = GlobalPantsirSystem.get_predicted_track_state(track_id)
		if track_state.is_empty() or GlobalPantsirSystem.is_track_filtered(track_id):
			continue
		var relative = track_state["position"] - GlobalPantsirSystem.pantsir_position
		var target_azimuth = atan2(relative.x, -relative.z)
		var relative_azimuth = GlobalPantsirSystem.angle_difference(GlobalPantsirSystem.turret_current_angle, target_azimuth)
		if abs(relative_azimuth) > PI / 2.0:
			continue
		var range_ratio = clamp(Vector2(relative.x, relative.z).length() / float(GlobalPantsirSystem.MAX_RANGE), 0.0, 1.0)
		var blip_angle = beam_center + relative_azimuth
		var blip = c + Vector2(cos(blip_angle), sin(blip_angle)) * radius * range_ratio
		draw_circle(blip, 3.0, COL_TARGET_MAGENTA if track_id == GlobalPantsirSystem.locked_track_id else COL_TEXT_MAIN)

	# Sight azimuth readout, a small white plate with red text as on the console.
	var azimuth_deg = int(round(fposmod(rad_to_deg(GlobalPantsirSystem.optic_current_angle), 360.0)))
	var angle_rect = Rect2(r.position + Vector2(4.0, 4.0), Vector2(46.0, 15.0))
	draw_rect(angle_rect, COL_ANGLE_BOX, true)
	draw_rect(angle_rect, COL_BTN_SHADOW, false, 1.0)
	draw_string_centered(angle_rect, "α=%d°" % azimuth_deg, COL_RED_BTN, 10)

func make_sector_polygon(center: Vector2, radius: float, start_angle: float, end_angle: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array([center])
	for i in range(segments + 1):
		var angle = lerp(start_angle, end_angle, float(i) / float(segments))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

func draw_channels_table(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	var rows = 7
	var cols = 5

	var row_h = r.size.y / rows
	var col_w = r.size.x / cols

	var headers = ["НЦ", "ТЦ", "РЕЖ/ЗУР", "P, м", "H, м", "D, м", "V, м/с"]

	for i in range(rows + 1):
		var y = r.position.y + i * row_h
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), COL_GRID)

	for j in range(cols + 1):
		var x = r.position.x + j * col_w
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), COL_GRID)

	for i in range(rows):
		var header_rect = Rect2(r.position.x, r.position.y + i * row_h, col_w, row_h)
		draw_string_centered(header_rect, headers[i], COL_TEXT_MAIN, 11)

	# Each column is a target channel. It is taken as soon as a target is put
	# on tracking; НЦ blinks while missiles are flying at that target.
	for j in range(1, cols):
		var channel_idx = j - 1
		var ch_x_center = r.position.x + j * col_w + col_w/2
		var target_id: int = GlobalPantsirSystem.target_channels[channel_idx]
		var under_attack = GlobalPantsirSystem.is_target_under_attack(target_id)

		var r_num = Rect2(r.position.x + j*col_w, r.position.y, col_w, row_h)
		var center_pos = r_num.get_center()
		if target_id == -1 or !under_attack or _blink_on():
			draw_circle(center_pos, 10, COL_TEXT_GREEN if target_id != -1 else COL_IND_GREY)
			draw_string(default_font, center_pos + Vector2(-3, 4), str(channel_idx + 1), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.BLACK)

		if target_id == -1:
			var empty_box = Rect2(ch_x_center - 5, r.position.y + 2*row_h + row_h/2 - 5, 10, 10)
			draw_rect(empty_box, Color(0.3, 0.3, 0.3), false, 1.0)
			continue

		if target_id == GlobalPantsirSystem.locked_track_id:
			var r_tc = Rect2(r.position.x + j*col_w, r.position.y + row_h, col_w, row_h)
			draw_circle(r_tc.get_center(), 3.5, COL_RED_DOT)

		# One missile icon per missile in flight; it blinks after launch.
		var missile_count = 0
		for guidance_channel in GlobalPantsirSystem.guidance_channels:
			if guidance_channel != null and guidance_channel["target_id"] == target_id and is_instance_valid(guidance_channel["missile"]):
				missile_count += 1
		var icon_y = r.position.y + 2*row_h + row_h/2 - 5
		var icons_w = maxi(missile_count, 1) * 12 - 2
		for k in range(maxi(missile_count, 1)):
			var r_box = Rect2(ch_x_center - icons_w * 0.5 + k * 12, icon_y, 10, 10)
			if missile_count == 0:
				draw_rect(r_box, Color(0.3, 0.3, 0.3), false, 1.0)
			elif _blink_on():
				draw_rect(r_box, COL_GREEN_BOX, true)

		var target_state = GlobalPantsirSystem.get_predicted_track_state(target_id)
		if target_state.is_empty():
			continue
		var t_pos: Vector3 = target_state["position"] - GlobalPantsirSystem.pantsir_position
		var t_vel: Vector3 = target_state["velocity"]
		# P is the course parameter: the closest horizontal pass distance.
		var horizontal_velocity = Vector2(t_vel.x, t_vel.z)
		var course_parameter = 0.0
		if horizontal_velocity.length() > 1.0:
			course_parameter = absf(Vector2(t_pos.x, t_pos.z).cross(horizontal_velocity.normalized()))
		draw_cell_text(j, 3, str(int(course_parameter)), r, row_h, col_w)
		draw_cell_text(j, 4, str(int(t_pos.y)), r, row_h, col_w)
		draw_cell_text(j, 5, str(int(t_pos.length())), r, row_h, col_w)
		draw_cell_text(j, 6, str(int(t_vel.length())), r, row_h, col_w)

func _has_missile_in_flight() -> bool:
	for channel in GlobalPantsirSystem.guidance_channels:
		if channel != null and is_instance_valid(channel["missile"]):
			return true
	return false

# Outlined upright missile standing on the text baseline, about one and a half
# letter heights tall: rounded nose, body, fins.
func _draw_missile_icon(baseline_center: Vector2) -> void:
	var c = baseline_center
	var outline = PackedVector2Array()
	# Rounded nose: half circle over the body.
	for i in range(9):
		var angle = PI + PI * i / 8.0
		outline.append(c + Vector2(cos(angle) * 4.0, -21.0 + sin(angle) * 4.0))
	outline.append_array([
		c + Vector2(4.0, -8.0),
		c + Vector2(8.0, -2.0),
		c + Vector2(8.0, 2.0),
		c + Vector2(-8.0, 2.0),
		c + Vector2(-8.0, -2.0),
		c + Vector2(-4.0, -8.0),
		c + Vector2(-4.0, -21.0),
	])
	draw_polyline(outline, COL_TEXT_GUI, 1.6, true)

func _blink_on(rate_hz: float = 2.0) -> bool:
	return fmod(Time.get_ticks_msec() / 1000.0 * rate_hz, 1.0) < 0.5

func draw_cell_text(col_idx, row_idx, text, r, row_h, col_w):
	var rect = Rect2(r.position.x + col_idx * col_w, r.position.y + row_idx * row_h, col_w, row_h)
	draw_string_centered(rect, text, COL_TEXT_MAIN, 11)

func draw_bottom_panels(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	var w_blok = r.size.x * 0.42
	var w_meteo = r.size.x * 0.25
	var w_otkaz = r.size.x - w_blok - w_meteo

	var blok_rect = Rect2(r.position.x + 2, r.position.y + 2, w_blok - 4, r.size.y - 4)
	draw_blokirovki(blok_rect)

	var otkaz_rect = Rect2(r.position.x + w_blok, r.position.y + 2, w_otkaz - 4, r.size.y - 4)
	draw_otkazy(otkaz_rect)

	var meteo_rect = Rect2(r.position.x + w_blok + w_otkaz, r.position.y + 2, w_meteo - 4, r.size.y - 4)
	draw_meteo(meteo_rect)

func draw_blokirovki(r: Rect2):
	draw_3d_panel(r, true)

	# Power switches: red is off, green is on.
	var lb_w = 38.0
	var lb_h = (r.size.y - 12.0) * 0.5 - 2.0
	var soc_r = Rect2(r.position.x + 5.0, r.position.y + 5.0, lb_w, lb_h)
	draw_system_button(soc_r, "СОЦ", GlobalPantsirSystem.search_radar_on)
	rect_buttons["BTN_SOC"] = soc_r

	var mrls_r = Rect2(r.position.x + 5.0, soc_r.end.y + 4.0, lb_w, lb_h)
	draw_system_button(mrls_r, "МРЛС", GlobalPantsirSystem.sector_radar_on)
	rect_buttons["BTN_MRLS"] = mrls_r

	# The blockings list is intentionally empty.
	var list_x = soc_r.end.x + 5.0
	var list_w = clamp(r.size.x * 0.18, 86.0, 106.0)
	draw_string(default_font, Vector2(list_x + 4.0, r.position.y + 13.0), "БЛОКИРОВКИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_MAIN)
	var list_rect = Rect2(list_x, r.position.y + 17.0, list_w, r.size.y - 22.0)
	draw_3d_panel(list_rect, true, Color(0.70, 0.70, 0.69))
	var scrollbar = Rect2(list_rect.end.x - 11.0, list_rect.position.y, 11.0, list_rect.size.y)
	draw_3d_panel(scrollbar, false, Color(0.66, 0.66, 0.65))
	draw_string_centered(Rect2(scrollbar.position, Vector2(scrollbar.size.x, 13.0)), "▲", COL_TEXT_MAIN, 8)
	draw_string_centered(Rect2(Vector2(scrollbar.position.x, scrollbar.end.y - 13.0), Vector2(scrollbar.size.x, 13.0)), "▼", COL_TEXT_MAIN, 8)

	# Ammunition/readiness module, laid out like the original console.
	var module_rect = Rect2(list_rect.end.x + 5.0, r.position.y + 4.0, r.end.x - list_rect.end.x - 10.0, r.size.y - 8.0)
	var slot_w = 21.0
	var slot_h = 22.0
	var slot_gap = 2.0
	var bank_w = slot_w * 2.0 + slot_gap
	var gun_w = 42.0
	var ready_w = 73.0
	var group_gap = 5.0
	var content_w = bank_w * 2.0 + gun_w * 2.0 + ready_w + group_gap * 4.0
	var x = module_rect.position.x + max(0.0, (module_rect.size.x - content_w) * 0.5)
	var bank_y = module_rect.position.y + 24.0

	draw_missile_bank(Vector2(x, bank_y), [[9, 10], [5, 6], [1, 2]], [0, 1], slot_w, slot_h, slot_gap)
	x += bank_w + group_gap
	draw_gun_pair(Rect2(x, module_rect.position.y + 35.0, gun_w, 57.0), 0)
	x += gun_w + group_gap
	draw_readiness_stack(Rect2(x, module_rect.position.y, ready_w, 100.0))
	x += ready_w + group_gap
	draw_gun_pair(Rect2(x, module_rect.position.y + 35.0, gun_w, 57.0), 1)
	x += gun_w + group_gap
	draw_missile_bank(Vector2(x, bank_y), [[11, 12], [7, 8], [3, 4]], [2, 3], slot_w, slot_h, slot_gap)

func draw_system_button(r: Rect2, label: String, active: bool):
	var color = COL_IND_GREEN if active else COL_RED_BTN
	draw_rect(r, color, true)
	draw_rect(r, Color(0.16, 0.16, 0.16), false, 1.5)
	draw_string_centered(r, label, Color.WHITE, 11)

func draw_missile_bank(position: Vector2, rows: Array, launcher_arms: Array, slot_w: float, slot_h: float, gap: float):
	var selected_tube = GlobalPantsirSystem.get_selected_missile_tube_number()
	var selected_arm = GlobalPantsirSystem.get_selected_launcher_arm()
	for row_index in range(rows.size()):
		for column_index in range(rows[row_index].size()):
			var slot_number: int = rows[row_index][column_index]
			var launcher_arm: int = launcher_arms[column_index]
			var lift_offset = -4.0 if GlobalPantsirSystem.is_launcher_arm_raised(launcher_arm) else 0.0
			var slot_rect = Rect2(position + Vector2(column_index * (slot_w + gap), row_index * (slot_h + gap) + lift_offset), Vector2(slot_w, slot_h))
			var loaded = GlobalPantsirSystem.is_missile_tube_loaded(slot_number)
			draw_3d_panel(slot_rect, false, COL_BG_PANEL)
			draw_string_centered(slot_rect, str(slot_number), Color.BLACK if loaded else Color.WHITE, 9)
			# A ТКБ-1055 container shows how many of its four missiles are left.
			var tube_type = GlobalPantsirSystem.get_missile_tube_type(slot_number)
			if loaded and GlobalPantsirSystem.get_missiles_per_tube(tube_type) > 1:
				var count_text = str(GlobalPantsirSystem.get_missile_tube_count(slot_number))
				draw_string(default_font, slot_rect.position + Vector2(slot_rect.size.x - 6.0, slot_rect.size.y - 2.0), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.05, 0.15, 0.6))
			if loaded and slot_number == selected_tube:
				var diamond_center = slot_rect.get_center()
				var diamond_radius = minf(slot_w, slot_h) * 0.43
				var diamond = PackedVector2Array([
					diamond_center + Vector2(0.0, -diamond_radius),
					diamond_center + Vector2(diamond_radius, 0.0),
					diamond_center + Vector2(0.0, diamond_radius),
					diamond_center + Vector2(-diamond_radius, 0.0),
				])
				# The next missile to launch is marked by a blinking white diamond.
				if _blink_on():
					draw_polyline(diamond, Color.BLACK, 4.0, true)
					draw_line(diamond[3], diamond[0], Color.BLACK, 4.0, true)
					draw_polyline(diamond, Color.WHITE, 2.0, true)
					draw_line(diamond[3], diamond[0], Color.WHITE, 2.0, true)

	# Each vertical column is one launcher arm. The selected arm has the green line.
	var arm_bar_y = position.y + rows.size() * (slot_h + gap) + 1.0
	for column_index in range(launcher_arms.size()):
		var launcher_arm: int = launcher_arms[column_index]
		var bar_rect = Rect2(position.x + column_index * (slot_w + gap), arm_bar_y, slot_w, 5.0)
		draw_rect(bar_rect, COL_IND_GREEN if launcher_arm == selected_arm else Color(0.08, 0.08, 0.08), true)

func draw_gun_pair(r: Rect2, pair_index: int):
	var first_barrel = pair_index * 2
	var pair_ammo = GlobalPantsirSystem.gun_ammo_by_barrel[first_barrel] + GlobalPantsirSystem.gun_ammo_by_barrel[first_barrel + 1]
	var counter = Rect2(r.position.x + 4.0, r.position.y, r.size.x - 8.0, 22.0)
	draw_3d_panel(counter, false, Color(0.91, 0.91, 0.88))
	draw_string_centered(counter, str(pair_ammo), COL_TEXT_MAIN, 10)

	for local_index in range(2):
		var barrel_index = first_barrel + local_index
		var center = Vector2(r.position.x + 13.0 + local_index * 17.0, r.position.y + 38.0)
		var has_ammo = GlobalPantsirSystem.gun_ammo_by_barrel[barrel_index] > 0
		draw_circle(center, 6.0, COL_IND_GREEN if has_ammo else Color.BLACK)
		draw_arc(center, 6.0, 0.0, TAU, 20, COL_BTN_SHADOW, 1.0)

func draw_readiness_stack(r: Rect2):
	var lamp = Rect2(r.position.x + 8.0, r.position.y, r.size.x - 16.0, 21.0)
	draw_3d_panel(lamp, false, COL_IND_GREEN if GlobalPantsirSystem.complex_ready else COL_RED_BTN)

	var labels = ["ГО", "ГБР", "ГБП"]
	var states = [
		GlobalPantsirSystem.complex_ready,
		GlobalPantsirSystem.ammo_missiles > 0,
		GlobalPantsirSystem.ammo_guns > 0,
	]
	for i in range(labels.size()):
		var row = Rect2(r.position.x, r.position.y + 25.0 + i * 23.0, r.size.x, 21.0)
		var row_color = COL_IND_GREEN if states[i] else COL_RED_BTN
		draw_3d_panel(row, true, row_color)
		draw_string(default_font, row.position + Vector2(5.0, 14.0), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_MAIN)
		var indicator_center = Vector2(row.end.x - 13.0, row.get_center().y)
		draw_circle(indicator_center, 3.0, Color.BLACK)

func draw_otkazy(r: Rect2):
	draw_3d_panel(r, true)
	draw_string(default_font, r.position + Vector2(8, 12), "ОТКАЗЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_MAIN)
	# empty list area
	var lst = Rect2(r.position.x + 4, r.position.y + 18, r.size.x - 8, r.size.y - 22)
	draw_3d_panel(lst, true, Color(0.7, 0.7, 0.7))
	# scrollbar
	var sb = Rect2(lst.position.x + lst.size.x - 10, lst.position.y, 10, lst.size.y)
	draw_3d_panel(sb, false)

func draw_meteo(r: Rect2):
	draw_3d_panel(r, true)
	draw_string(default_font, r.position + Vector2(8, 12), "МЕТЕОДАННЫЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_MAIN)

	var rows = [
		["ТВ, °C", "+29"],
		["ВВ, %", "42"],
		["АД, мм рт.ст", "759"],
		["СВ, м/с", "4"],
		["НВ, °", "6"],
	]
	var y0 = r.position.y + 22
	var rh = (r.size.y - 26) / rows.size()
	for i in range(rows.size()):
		var y = y0 + i * rh
		var lbl_x = r.position.x + 6
		var val_x = r.position.x + r.size.x - 8
		draw_string(default_font, Vector2(lbl_x, y + rh*0.7), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_MAIN)
		draw_string(default_font, Vector2(val_x, y + rh*0.7), rows[i][1], HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, COL_TEXT_MAIN)

func draw_bottom_bar(r: Rect2):
	draw_rect(r, COL_BG_PANEL, true)

	# camera/optics control row mimicking reference: contrast/brightness, P/N, Stat, Stab
	var x = r.position.x + 4
	var y = r.position.y + 2
	var h = r.size.y - 4

	# weapon select - keep buttons for ПШК / ЗУР on the very left (replaces an icon group)
	var wpn_w = 50.0
	var gun_btn = Rect2(x, y, wpn_w, h)
	var col = COL_BG_PANEL
	var pressed = false
	if GlobalPantsirSystem.selected_weapon == "GUNS": col = COL_TEXT_CYAN; pressed = true
	draw_3d_panel(gun_btn, pressed, col)
	draw_string_centered(gun_btn, "ПШК", COL_TEXT_MAIN, 11)
	rect_buttons["BTN_WPN_GUNS"] = gun_btn
	x += wpn_w + 2

	var mis_btn = Rect2(x, y, wpn_w, h)
	col = COL_BG_PANEL
	pressed = false
	if GlobalPantsirSystem.selected_weapon == "MISSILES": col = COL_TEXT_CYAN; pressed = true
	draw_3d_panel(mis_btn, pressed, col)
	draw_string_centered(mis_btn, "ЗУР", COL_TEXT_MAIN, 11)
	rect_buttons["BTN_WPN_MISSILES"] = mis_btn
	x += wpn_w + 8

	# icons mimicking the camera control row
	var icon_w = 30.0
	var icon_count = 7
	for i in range(icon_count):
		var br = Rect2(x, y, icon_w, h)
		draw_3d_panel(br, false)
		var c = br.get_center()
		match i:
			0:
				# camera icon
				draw_rect(Rect2(c - Vector2(8, 4), Vector2(16, 8)), COL_TEXT_MAIN, false, 1.0)
				draw_circle(c, 3, COL_TEXT_MAIN)
			1:
				draw_string(default_font, c + Vector2(-4, 4), "◐", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_MAIN)
			2:
				draw_string(default_font, c + Vector2(-4, 4), "◑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_MAIN)
			3:
				draw_string(default_font, c + Vector2(-5, 4), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXT_MAIN)
			4:
				draw_string(default_font, c + Vector2(-5, 4), "−", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXT_MAIN)
			5:
				draw_string(default_font, c + Vector2(-4, 4), "✱", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_MAIN)
			6:
				draw_string(default_font, c + Vector2(-4, 4), "◌", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_MAIN)
		x += icon_w + 2

	# P/N toggle
	x += 6
	var pn_w = 50.0
	var pn_btn = Rect2(x, y, pn_w, h)
	draw_3d_panel(pn_btn, false)
	draw_string_centered(pn_btn, "P/N", COL_TEXT_MAIN, 11)
	x += pn_w + 2

	# spacer / extra icons
	for i in range(2):
		var br = Rect2(x, y, icon_w, h)
		draw_3d_panel(br, false)
		x += icon_w + 2

	# Stat / Stab on the right
	var stab_w = 50.0
	var stab_btn = Rect2(r.position.x + r.size.x - stab_w - 4, y, stab_w, h)
	draw_3d_panel(stab_btn, false)
	draw_string_centered(stab_btn, "× Stab", COL_TEXT_MAIN, 11)

	var stat_btn = Rect2(stab_btn.position.x - stab_w - 4, y, stab_w, h)
	draw_3d_panel(stat_btn, false)
	draw_string_centered(stat_btn, "Stat", COL_TEXT_MAIN, 11)

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

func draw_string_centered(rect: Rect2, text: String, col: Color, size: int = 12):
	var sz = default_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	var pos = rect.get_center() + Vector2(-sz.x/2, sz.y/4)
	draw_string(default_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)
