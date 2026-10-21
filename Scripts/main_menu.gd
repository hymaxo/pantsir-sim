extends Control

const GAME_SCENE: String = "res://Scenes/main_system.tscn"

@onready var _cards: Array[Node] = %Cards.get_children()
@onready var _play_button: Button = %PlayButton
@onready var _settings_menu: Control = %SettingsMenu

func _ready() -> void:
	for card in _cards:
		card.card_pressed.connect(_select_card)
	%SettingsButton.pressed.connect(_settings_menu.open)
	_play_button.pressed.connect(_on_play_pressed)
	%QuitButton.pressed.connect(get_tree().quit)
	_settings_menu.closed.connect(_play_button.grab_focus)

	var initial_card = _cards[0]
	for card in _cards:
		if card.complex_id == GameSettings.selected_complex:
			initial_card = card
	_select_card(initial_card)

func _select_card(selected_card: Node) -> void:
	for card in _cards:
		card.set_selected(card == selected_card)
	GameSettings.selected_complex = selected_card.complex_id
	GameSettings.save_settings()
	# Only finished complexes can be played; WIP ones are selectable for later.
	_play_button.disabled = selected_card.work_in_progress
	_play_button.text = "В РАЗРАБОТКЕ" if selected_card.work_in_progress else "ИГРАТЬ"

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
