extends Control

# Reload request: choose a munition (or empty) for every launcher tube and
# both gun belts, laid out like the launcher on the operator console.
signal closed

const SLOT_SCENE: PackedScene = preload("res://Scenes/LoadoutSlot.tscn")
# Tube numbers per row, top to bottom; each column is one launcher arm.
const LEFT_BANK_ROWS: Array = [[9, 10], [5, 6], [1, 2]]
const RIGHT_BANK_ROWS: Array = [[11, 12], [7, 8], [3, 4]]

var _tube_slots: Dictionary = {}
var _gun_slots: Array = []

@onready var _mass_label: Label = %MassLabel
@onready var _status_label: Label = %StatusLabel

func _ready() -> void:
	_build_bank(%LeftBank, LEFT_BANK_ROWS)
	_build_bank(%RightBank, RIGHT_BANK_ROWS)
	for gun in range(2):
		var slot = SLOT_SCENE.instantiate()
		(%LeftGun if gun == 0 else %RightGun).add_child(slot)
		slot.setup("Пушка %d" % (gun + 1), slot.Kind.GUN, GlobalPantsirSystem.GUN_BELT_TYPES)
		slot.changed.connect(_update_mass)
		_gun_slots.append(slot)
	%LoadAllButton.pressed.connect(_set_all.bind(true))
	%UnloadAllButton.pressed.connect(_set_all.bind(false))
	%CancelButton.pressed.connect(close)
	%ApplyButton.pressed.connect(_on_apply_pressed)
	%TimeLabel.text = "Перезарядка займёт %d с — всё это время стрельба невозможна" % int(GlobalPantsirSystem.RELOAD_TIME_S)

func _build_bank(container: GridContainer, rows: Array) -> void:
	for row in rows:
		for tube_number in row:
			var slot = SLOT_SCENE.instantiate()
			container.add_child(slot)
			slot.changed.connect(_update_mass)
			_tube_slots[tube_number] = slot

# Shows the current loadout of the complex.
func open() -> void:
	var missile_types = GlobalPantsirSystem.get_missile_types()
	for tube_number in _tube_slots:
		var slot = _tube_slots[tube_number]
		slot.setup("ЗУР №%d" % tube_number, slot.Kind.MISSILE, missile_types)
		var tube_index = tube_number - 1
		var current = GlobalPantsirSystem.missile_tube_types[tube_index] if tube_index < GlobalPantsirSystem.missile_tube_types.size() else ""
		slot.set_value(current)
	for gun in range(_gun_slots.size()):
		var current = GlobalPantsirSystem.gun_belt_types[gun] if gun < GlobalPantsirSystem.gun_belt_types.size() else ""
		_gun_slots[gun].set_value(current)
	_status_label.text = ""
	_update_mass()
	show()

func close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _set_all(loaded: bool) -> void:
	for slot in _tube_slots.values():
		slot.set_loaded(loaded)
	for slot in _gun_slots:
		slot.set_loaded(loaded)
	_update_mass()

func _update_mass() -> void:
	var missiles = 0
	for slot in _tube_slots.values():
		if !slot.get_value().is_empty():
			missiles += 1
	var rounds = 0
	for slot in _gun_slots:
		if !slot.get_value().is_empty():
			rounds += GlobalPantsirSystem.GUN_ROUNDS_PER_BARREL * 2
	var mass = missiles * GlobalPantsirSystem.get_missile_mass_kg() + rounds * GlobalPantsirSystem.GUN_ROUND_MASS_KG
	_mass_label.text = "ЗУР: %d / %d    Снарядов: %d    Масса боекомплекта: %.1f кг" % [missiles, _tube_slots.size(), rounds, mass]

func _on_apply_pressed() -> void:
	var tube_types: Array[String] = []
	for tube_number in range(1, _tube_slots.size() + 1):
		tube_types.append(_tube_slots[tube_number].get_value())
	var belt_types: Array[String] = []
	for slot in _gun_slots:
		belt_types.append(slot.get_value())
	if GlobalPantsirSystem.request_reload(tube_types, belt_types):
		close()
	else:
		_status_label.text = "Идёт пуск — перезарядка невозможна"
