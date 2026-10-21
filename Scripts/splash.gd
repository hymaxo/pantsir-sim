extends Control

# Start-up logo: the Pantsir photo fills with colour, then the main menu opens.
# Any key or click skips it.
const MAIN_MENU_SCENE: String = "res://Scenes/MainMenu.tscn"
const FILL_TIME_S: float = 1.6
const HOLD_TIME_S: float = 0.5
const FADE_TIME_S: float = 0.35

var _leaving: bool = false

func _ready() -> void:
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(%Photo, "material:shader_parameter/fill", 1.0, FILL_TIME_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(HOLD_TIME_S)
	tween.tween_callback(_leave)

func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_leave()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME_S)
	tween.tween_callback(get_tree().change_scene_to_file.bind(MAIN_MENU_SCENE))
