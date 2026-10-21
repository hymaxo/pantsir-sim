extends PanelContainer

# One launcher tube or gun in the reload menu: an icon of what is loaded and
# a drop-down to choose the munition or leave the slot empty.
signal changed

enum Kind { MISSILE, GUN }

const EMPTY_LABEL: String = "Пусто"
const COL_ICON = Color(0.86, 0.88, 0.82, 1.0)
const COL_ICON_DIM = Color(0.4, 0.42, 0.38, 1.0)

var kind: int = Kind.MISSILE
# Index 0 is always the empty choice ("").
var _values: Array[String] = [""]

@onready var _title: Label = %Title
@onready var _icon: Control = %Icon
@onready var _choice: OptionButton = %Choice

func _ready() -> void:
	_icon.draw.connect(_draw_icon)
	_choice.item_selected.connect(func(_index): _icon.queue_redraw(); changed.emit())

func setup(title: String, slot_kind: int, types: Array) -> void:
	kind = slot_kind
	_title.text = title
	_values = [""]
	_choice.clear()
	_choice.add_item(EMPTY_LABEL)
	for munition in types:
		_values.append(munition)
		_choice.add_item(munition)
	_icon.queue_redraw()

func get_value() -> String:
	return _values[maxi(_choice.selected, 0)]

func set_value(value: String) -> void:
	_choice.select(maxi(_values.find(value), 0))
	_icon.queue_redraw()

func set_loaded(loaded: bool) -> void:
	set_value(_values[1] if loaded and _values.size() > 1 else "")

func _draw_icon() -> void:
	var center = _icon.size * 0.5
	var radius = minf(_icon.size.x, _icon.size.y) * 0.42
	if get_value().is_empty():
		_icon.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), COL_ICON_DIM, false, 1.0)
		return
	if kind == Kind.MISSILE:
		# Canister seen from the front: rim, missile nose and a crosshair.
		_icon.draw_arc(center, radius, 0.0, TAU, 32, COL_ICON, 2.0, true)
		_icon.draw_circle(center, radius * 0.35, COL_ICON)
		for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var direction = Vector2(cos(angle), sin(angle))
			_icon.draw_line(center + direction * radius * 0.55, center + direction * radius * 0.9, COL_ICON, 1.5, true)
	else:
		# Ammunition box seen from the end: rows of rounds.
		_icon.draw_arc(center, radius, 0.0, TAU, 32, COL_ICON, 2.0, true)
		for ring in [0.0, 0.45, 0.78]:
			var count = 1 if ring == 0.0 else (6 if ring < 0.5 else 12)
			for i in range(count):
				var angle = TAU * i / count
				_icon.draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * ring, radius * 0.11, COL_ICON)
