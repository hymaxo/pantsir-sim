extends Control

# Live state of the С1 СОЦ elevation scan: one row per sector, the sector the
# antenna is in now highlighted with the share of its half-turn already swept.
const ROW_HEIGHT: float = 17.0
const COL_ROW = Color(0.84, 0.84, 0.84, 1.0)
const COL_ROW_ACTIVE = Color(0.0, 0.0, 0.5, 1.0)
const COL_TEXT = Color(0.0, 0.0, 0.0, 1.0)
const COL_TEXT_ACTIVE = Color(1.0, 1.0, 1.0, 1.0)
const COL_TROUGH = Color(0.55, 0.55, 0.55, 1.0)
const COL_SWEEP = Color(0.0, 0.8, 1.0, 1.0)

func _process(_delta: float) -> void:
	if !is_visible_in_tree():
		return
	var height = ROW_HEIGHT * maxi(GlobalPantsirSystem.soc_sectors.size(), 1)
	if custom_minimum_size.y != height:
		custom_minimum_size.y = height
	queue_redraw()

func _draw() -> void:
	var font = get_theme_default_font()
	var font_size = get_theme_default_font_size()
	var sectors: Array = GlobalPantsirSystem.soc_sectors
	var scanning = GlobalPantsirSystem.search_radar_on
	for i in range(sectors.size()):
		var row = Rect2(0.0, i * ROW_HEIGHT, size.x, ROW_HEIGHT - 2.0)
		var active = scanning and i == GlobalPantsirSystem.soc_current_sector
		draw_rect(row, COL_ROW_ACTIVE if active else COL_ROW)
		var label = "%d     %.0f° – %.0f°" % [i + 1, sectors[i][0], sectors[i][1]]
		draw_string(font, row.position + Vector2(6.0, font.get_ascent(font_size) + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT_ACTIVE if active else COL_TEXT)
		var bar = Rect2(row.position.x + row.size.x * 0.5, row.position.y + 5.0, row.size.x * 0.46, 5.0)
		draw_rect(bar, COL_TROUGH)
		if active:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * GlobalPantsirSystem.get_soc_sector_progress(), bar.size.y)), COL_SWEEP)
