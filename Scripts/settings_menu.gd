extends Control

# Settings overlay. For now it only changes the window size.
signal closed

@onready var _window_size_option: OptionButton = %WindowSizeOption

func _ready() -> void:
	for label in GameSettings.get_window_size_labels():
		_window_size_option.add_item(label)
	%ApplyButton.pressed.connect(_on_apply_pressed)
	%BackButton.pressed.connect(close)

func open() -> void:
	_window_size_option.select(GameSettings.window_size_index)
	show()
	_window_size_option.grab_focus()

func close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _on_apply_pressed() -> void:
	GameSettings.set_window_size_index(_window_size_option.selected)
