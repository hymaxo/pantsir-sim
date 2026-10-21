extends Button


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_pressed() -> void:
	GlobalPantsirSystem.toggle_master_power()
	pass # Replace with function body.




func _on_button_scan_pressed() -> void:
	GlobalPantsirSystem.scan_radar_power_switch()
	pass # Replace with function body.


func _on_auto_fire_pressed() -> void:
	GlobalPantsirSystem.toggle_auto_fire()


func _on_button_soc_pressed() -> void:
	GlobalPantsirSystem.soc_switch()
	pass # Replace with function body.
