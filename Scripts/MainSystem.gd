extends Control

const MAIN_MENU_SCENE: String = "res://Scenes/MainMenu.tscn"
const RELOAD_BUTTON_TEXT: String = "ЗАПРОСИТЬ ПЕРЕЗАРЯДКУ"

@onready var c_screen = %CScreen
@onready var o_screen = %OScreen
var launch_sound_file = preload("res://Sounds/MissileLaunch.wav")
var audio_player: AudioStreamPlayer
func _ready():
	# A session starts fully loaded with the selected complex's missiles.
	GlobalPantsirSystem.load_default_loadout()
	c_screen.visible = true
	o_screen.visible = false
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = launch_sound_file
	add_child(audio_player)

func _process(delta):
	# The reload button shows the countdown and cannot be pressed again meanwhile.
	var reloading = GlobalPantsirSystem.is_reloading()
	%ReloadButton.disabled = reloading
	%ReloadButton.text = "ПЕРЕЗАРЯДКА… %d с" % ceili(GlobalPantsirSystem.reload_time_left_s) if reloading else RELOAD_BUTTON_TEXT
	if audio_player and GlobalPantsirSystem.sound_play_required:
		audio_player.pitch_scale = randf_range(0.9, 1.1)
		audio_player.play()
		GlobalPantsirSystem.sound_play_required = false

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		return_to_menu()
		return
	if event.is_action_pressed("uifocus_next"):
		toggle_screens()
	if event.is_action_pressed("zoom_inc") and c_screen.visible == true:
		GlobalPantsirSystem.MAX_RANGE = clamp(GlobalPantsirSystem.MAX_RANGE-5000, 5000, 50000)
	if event.is_action_pressed("zoom_dec") and c_screen.visible == true:
		GlobalPantsirSystem.MAX_RANGE = clamp(GlobalPantsirSystem.MAX_RANGE+5000, 5000, 50000)


func open_reload_menu():
	%ReloadMenu.open()

func toggle_screens():
	c_screen.visible = !c_screen.visible
	o_screen.visible = !o_screen.visible

	c_screen.set_process_input(c_screen.visible)
	o_screen.set_process_input(o_screen.visible)

# The simulation state lives in an autoload, so it is reset before leaving;
# the next session starts from a cold, fully loaded complex.
func return_to_menu():
	GameSettings.save_settings()
	GlobalPantsirSystem.reset_simulation()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
