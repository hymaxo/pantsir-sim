extends Control

# Start-up: the disclaimer fades in and out, then the Pantsir photo fills with
# colour and the main menu opens. A key or click skips the disclaimer first,
# then the logo.
const MAIN_MENU_SCENE: String = "res://Scenes/MainMenu.tscn"
const DISCLAIMER_FADE_S: float = 0.7
const DISCLAIMER_HOLD_S: float = 3.5
const LOGO_FADE_IN_S: float = 0.3
const FILL_TIME_S: float = 1.6
const HOLD_TIME_S: float = 0.5
const FADE_TIME_S: float = 0.35

var _showing_logo: bool = false
var _leaving: bool = false
var _tween: Tween

func _ready() -> void:
	%Disclaimer.modulate.a = 0.0
	%Center.modulate.a = 0.0
	%Credit.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(%Disclaimer, "modulate:a", 1.0, DISCLAIMER_FADE_S)
	_tween.tween_interval(DISCLAIMER_HOLD_S)
	_tween.tween_property(%Disclaimer, "modulate:a", 0.0, DISCLAIMER_FADE_S)
	_tween.tween_callback(_show_logo)

func _show_logo() -> void:
	if _showing_logo:
		return
	_showing_logo = true
	if _tween:
		_tween.kill()
	%Disclaimer.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(%Center, "modulate:a", 1.0, LOGO_FADE_IN_S)
	_tween.parallel().tween_property(%Credit, "modulate:a", 1.0, LOGO_FADE_IN_S)
	_tween.tween_property(%Photo, "material:shader_parameter/fill", 1.0, FILL_TIME_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(HOLD_TIME_S)
	_tween.tween_callback(_leave)

func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		if _showing_logo:
			_leave()
		else:
			_show_logo()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if _tween:
		_tween.kill()
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME_S)
	tween.tween_callback(get_tree().change_scene_to_file.bind(MAIN_MENU_SCENE))
