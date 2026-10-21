extends PanelContainer

# СПЗ «РУЧНАЯ НАСТРОЙКА»: СОЦ target filters and, on the С1, the upper
# boundary its elevation sectors are planned from. The window sits on the
# commander screen and is dragged by its title bar.
const OPEN_ANIMATION_S: float = 0.12
const CLOSED_SCALE: Vector2 = Vector2(0.92, 0.92)

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _tween: Tween

@onready var _spin_boxes: Dictionary = {
	"speed_limit_mps": %SpeedSpin,
	"lower_height_m": %HeightSpin,
	"lower_angle_deg": %AngleSpin,
	"upper_height_m": %UpperSpin,
}
@onready var _reset_buttons: Dictionary = {
	"lower_height_m": %HeightReset,
	"lower_angle_deg": %AngleReset,
	"upper_height_m": %UpperReset,
}
@onready var _rcs_buttons: Array = [%Rcs0, %Rcs1, %Rcs2]

func _ready() -> void:
	theme = ConsoleTheme.build()
	hide()
	%TitleBar.gui_input.connect(_on_title_bar_gui_input)
	%CloseButton.pressed.connect(close)
	%ExitButton.pressed.connect(close)
	%AutoCheck.toggled.connect(_on_auto_toggled)
	for key in _spin_boxes:
		_spin_boxes[key].value_changed.connect(_on_value_changed.bind(key))
	for key in _reset_buttons:
		_reset_buttons[key].pressed.connect(_on_reset_pressed.bind(key))
	for i in range(_rcs_buttons.size()):
		_rcs_buttons[i].toggled.connect(_on_rcs_toggled.bind(i))

func _process(_delta: float) -> void:
	if !visible:
		return
	if !GlobalPantsirSystem.master_power_on:
		hide()
		return
	if %SectorGroup.visible:
		%SectorInfo.text = "Секторов: %d    Обзор: %.0f с    Д ЗУР: %.0f км" % [
			GlobalPantsirSystem.soc_sectors.size(),
			GlobalPantsirSystem.get_soc_revisit_s(),
			GlobalPantsirSystem.missile_flight_config.maximum_distance_m / 1000.0,
		]

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	_sync_from_system()
	show()
	reset_size()
	_keep_inside_parent()
	pivot_offset = size / 2.0
	scale = CLOSED_SCALE
	modulate.a = 0.0
	_animate(Vector2.ONE, 1.0)

func close() -> void:
	_dragging = false
	GameSettings.save_settings()
	_animate(CLOSED_SCALE, 0.0).finished.connect(hide)

func _animate(target_scale: Vector2, target_alpha: float) -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", target_scale, OPEN_ANIMATION_S)
	_tween.tween_property(self, "modulate:a", target_alpha, OPEN_ANIMATION_S)
	return _tween

func _sync_from_system() -> void:
	var auto = GlobalPantsirSystem.spz_auto
	%AutoCheck.set_pressed_no_signal(auto)
	for key in _spin_boxes:
		_spin_boxes[key].set_value_no_signal(GlobalPantsirSystem.get_spz_value(key))
		_spin_boxes[key].editable = !auto
	for key in _reset_buttons:
		_reset_buttons[key].disabled = auto
	var threshold = GlobalPantsirSystem.get_spz_value("rcs_threshold_m2")
	for i in range(_rcs_buttons.size()):
		_rcs_buttons[i].set_pressed_no_signal(is_equal_approx(GlobalPantsirSystem.SPZ_RCS_THRESHOLDS[i], threshold))
		_rcs_buttons[i].disabled = auto
	# Only the С1 plans its elevation sectors from an upper boundary.
	var sector_scan = GlobalPantsirSystem.uses_soc_sector_scan()
	%UpperGroup.visible = sector_scan
	%SectorGroup.visible = sector_scan

func _on_auto_toggled(enabled: bool) -> void:
	GlobalPantsirSystem.set_spz_auto(enabled)
	_sync_from_system()

func _on_value_changed(value: float, key: String) -> void:
	GlobalPantsirSystem.set_spz_value(key, value)

func _on_reset_pressed(key: String) -> void:
	_spin_boxes[key].value = GlobalPantsirSystem.SPZ_DEFAULTS[key]

func _on_rcs_toggled(pressed: bool, index: int) -> void:
	if pressed:
		GlobalPantsirSystem.set_spz_value("rcs_threshold_m2", GlobalPantsirSystem.SPZ_RCS_THRESHOLDS[index])

func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = get_local_mouse_position()
	elif event is InputEventMouseMotion and _dragging:
		position = get_parent_control().get_local_mouse_position() - _drag_offset
		_keep_inside_parent()

func _keep_inside_parent() -> void:
	var parent = get_parent_control()
	if parent:
		position = position.clamp(Vector2.ZERO, (parent.size - size).max(Vector2.ZERO))
