extends PanelContainer

# One air-defense complex on the main menu. The selected card is shown in
# color with a bright frame, the others in grayscale.
signal card_pressed(card: Node)

const COL_FRAME_SELECTED = Color(0.95, 0.85, 0.25, 1.0)
const COL_FRAME_IDLE = Color(0.25, 0.27, 0.22, 1.0)
const COL_CARD_BG = Color(0.12, 0.13, 0.11, 1.0)
const COLOR_FADE_SPEED: float = 8.0

@export var complex_id: String = ""
@export var title: String = ""
@export var subtitle: String = ""
@export var photo: Texture2D
# Author and license line required by freely licensed photos.
@export var photo_credit: String = ""
@export var work_in_progress: bool = false

var selected: bool = false
var _saturation: float = 0.0

@onready var _photo_rect: TextureRect = %Photo
@onready var _no_photo_label: Label = %NoPhotoLabel
@onready var _wip_plate: PanelContainer = %WipPlate
@onready var _title_label: Label = %Title
@onready var _subtitle_label: Label = %Subtitle
@onready var _credit_label: Label = %CreditLabel

func _ready() -> void:
	_photo_rect.texture = photo
	_no_photo_label.visible = photo == null
	_credit_label.text = photo_credit
	_credit_label.visible = !photo_credit.is_empty()
	_wip_plate.visible = work_in_progress
	_title_label.text = title
	_subtitle_label.text = subtitle
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_frame()
	_apply_saturation()

func _process(delta: float) -> void:
	var target = 1.0 if selected else 0.0
	if is_equal_approx(_saturation, target):
		return
	_saturation = move_toward(_saturation, target, COLOR_FADE_SPEED * delta)
	_apply_saturation()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		card_pressed.emit(self)
		accept_event()

func set_selected(value: bool) -> void:
	selected = value
	if is_node_ready():
		_apply_frame()

func _apply_frame() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = COL_CARD_BG
	style.border_color = COL_FRAME_SELECTED if selected else COL_FRAME_IDLE
	style.set_border_width_all(4 if selected else 2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

func _apply_saturation() -> void:
	var shader_material := _photo_rect.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("saturation", _saturation)
	_title_label.modulate = Color.WHITE.lerp(Color(0.6, 0.6, 0.6), 1.0 - _saturation)
