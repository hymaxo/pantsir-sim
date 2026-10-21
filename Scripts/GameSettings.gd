extends Node

# Player settings that outlive a session. Stored in user://settings.cfg and
# applied on startup.
const SETTINGS_PATH: String = "user://settings.cfg"
const FULLSCREEN_LABEL: String = "Полный экран"
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1900, 1000),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

# Index into WINDOW_SIZES; WINDOW_SIZES.size() means fullscreen.
var window_size_index: int = 2
var selected_complex: String = "SM"
# Время работы в боевом режиме (БР), seconds. Accumulates over all sessions
# like the complex's own counter, shown on the visor before "Бр".
var combat_mode_time_s: float = 0.0
# Saved this often while it runs, so a crash loses little.
const COMBAT_TIME_AUTOSAVE_S: float = 30.0
var _combat_time_since_save_s: float = 0.0

func _ready() -> void:
	load_settings()
	apply_window_size()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()

func add_combat_mode_time(delta: float) -> void:
	combat_mode_time_s += delta
	_combat_time_since_save_s += delta
	if _combat_time_since_save_s >= COMBAT_TIME_AUTOSAVE_S:
		save_settings()

func get_window_size_labels() -> Array[String]:
	var labels: Array[String] = []
	for window_size in WINDOW_SIZES:
		labels.append("%d × %d" % [window_size.x, window_size.y])
	labels.append(FULLSCREEN_LABEL)
	return labels

func set_window_size_index(index: int) -> void:
	window_size_index = clampi(index, 0, WINDOW_SIZES.size())
	apply_window_size()
	save_settings()

func apply_window_size() -> void:
	# Headless runs (tests, CI) have no real window to resize.
	if DisplayServer.get_name() == "headless":
		return
	var window = get_window()
	if window_size_index >= WINDOW_SIZES.size():
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var window_size = WINDOW_SIZES[window_size_index]
	var screen_rect = DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = Vector2i(mini(window_size.x, screen_rect.size.x), mini(window_size.y, screen_rect.size.y))
	window.position = screen_rect.position + (screen_rect.size - window.size) / 2

func load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	window_size_index = clampi(int(config.get_value("display", "window_size_index", window_size_index)), 0, WINDOW_SIZES.size())
	selected_complex = str(config.get_value("game", "selected_complex", selected_complex))
	combat_mode_time_s = maxf(float(config.get_value("complex", "combat_mode_time_s", combat_mode_time_s)), 0.0)
	# СПЗ (ручная настройка СОЦ); unknown keys are ignored.
	GlobalPantsirSystem.spz_auto = bool(config.get_value("spz", "auto", GlobalPantsirSystem.spz_auto))
	for key in GlobalPantsirSystem.SPZ_DEFAULTS:
		GlobalPantsirSystem.spz_settings[key] = float(config.get_value("spz", key, GlobalPantsirSystem.spz_settings[key]))

func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("display", "window_size_index", window_size_index)
	config.set_value("game", "selected_complex", selected_complex)
	config.set_value("complex", "combat_mode_time_s", combat_mode_time_s)
	config.set_value("spz", "auto", GlobalPantsirSystem.spz_auto)
	for key in GlobalPantsirSystem.spz_settings:
		config.set_value("spz", key, GlobalPantsirSystem.spz_settings[key])
	config.save(SETTINGS_PATH)
	_combat_time_since_save_s = 0.0
