extends Node

var master_power_on: bool = false
const COMPLEX_READY_DELAY: float = 3.0
var master_power_elapsed: float = 0.0
var complex_ready: bool = false
var search_radar_on: bool = false
var sector_radar_on: bool = false
var MAX_RANGE = 30000
var targets: Array = [] 
var tracks: Dictionary = {}

const GUIDANCE_TT: String = "ТТ"
const GUIDANCE_PS: String = "ПС"
const TARGET_TRACK_STALE_TIME_S: float = 0.20
const LOST_COMMAND_HOLD_TIME_S: float = 0.25
const DRONE_MIN_SPEED_MPS: float = 45.0
const DRONE_MAX_SPEED_MPS: float = 70.0
const TOMAHAWK_MIN_SPEED_MPS: float = 230.0
const TOMAHAWK_MAX_SPEED_MPS: float = 280.0
const CRUISE_MISSILE_MIN_CLEARANCE_M: float = 30.0
const CRUISE_MISSILE_MAX_CLEARANCE_M: float = 80.0
const MEASUREMENT_SEED: int = 731947

var missile_flight_config: MissileFlightConfig = preload("res://Resources/PantsirMissileFlightConfig.tres")
var _simulation_time_s: float = 0.0
var _radar_measurement_accumulator_s: float = 0.0
var _measurement_rng := RandomNumberGenerator.new()
var _measurement_noise_states: Dictionary = {}

var pantsir_position: Vector3 = Vector3.ZERO

var search_radar_angle: float = 0.0

var turret_current_angle: float = 0.0
var turret_target_angle: float = 0.0
var turret_current_pitch: float = 0.0
var turret_target_pitch: float = 0.0

var optic_current_angle: float = 0.0
var optic_target_angle: float = 0.0
var optic_current_pitch: float = 0.0
var optic_target_pitch: float = 0.0

const OPTIC_ZOOM_LEVELS: Array[float] = [
	1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0,
	8.0, 10.0, 12.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0, 60.0
]
var manual_zoom_factor: float = OPTIC_ZOOM_LEVELS[0]

var locked_track_id: int = -1 
var selected_weapon: String = "MISSILES"

var sound_play_required: bool = false

const SCAN_SPEED_RPM: float = 30.0
const SOC_SINGLE_BEAM_SCAN_SPEED_RPM: float = 60.0
# Beam angle at the previous СОЦ plot generation; a target is in the beam if
# the beam swept over it since then, whatever the radar tick rate.
var _soc_last_plot_angle: float = 0.0
const TURRET_ROTATION_SPEED: float = 2.25
const TURRET_PITCH_SPEED: float = 1.5
const OPTIC_ROTATION_SPEED: float = 10.0 
const SECTOR_WIDTH_RAD: float = deg_to_rad(45.0)
# Search radar (СОЦ) measurement errors, 1 sigma.
const SEARCH_AZIMUTH_SIGMA_RAD: float = deg_to_rad(0.3)
const SEARCH_ELEVATION_SIGMA_RAD: float = deg_to_rad(1.0)
const SEARCH_RANGE_SIGMA_M: float = 50.0
const SEARCH_RADIAL_VELOCITY_SIGMA_MPS: float = 5.0
# With 3, detection falls from 90% to 10% between 0.83 and 1.2 of the
# reference range.
const DETECTION_CURVE_STEEPNESS: float = 3.0

# Per-radar detection: 50% range on a 1 m² target, Doppler notch half-width
# and how far ground clutter can shorten range on a target at treetop height.
# The millimetre МРЛС has a narrow beam and fine Doppler, so clutter hurts it
# less than the СОЦ.
const SOC_PROFILE: Dictionary = {"r50_1m2_m": 30000.0, "notch_mps": 8.0, "low_altitude_floor": 0.45}
const MRLS_PROFILE: Dictionary = {"r50_1m2_m": 22000.0, "notch_mps": 3.0, "low_altitude_floor": 0.7}
const DOPPLER_NOTCH_RANGE_FACTOR: float = 0.25
const LOW_ALTITUDE_CLUTTER_FULL_M: float = 10.0
const LOW_ALTITUDE_CLUTTER_CLEAR_M: float = 150.0
# Beam hits on a target closer together than this belong to one antenna pass.
const SOC_PASS_GROUPING_S: float = 0.3
# СОЦ resolution cell: echoes closer than this in every coordinate at once
# merge into one plot.
const SOC_RESOLUTION_AZIMUTH_RAD: float = deg_to_rad(3.0)
const SOC_RESOLUTION_ELEVATION_RAD: float = deg_to_rad(5.0)
const SOC_RESOLUTION_RANGE_M: float = 60.0
const SOC_RESOLUTION_VELOCITY_MPS: float = 3.0
# СОЦ track gates (half-widths) around the filter prediction, about 3σ of
# the plot errors plus the prediction error over one antenna turn.
const SOC_GATE_AZIMUTH_RAD: float = deg_to_rad(2.0)
const SOC_GATE_ELEVATION_RAD: float = deg_to_rad(5.0)
const SOC_GATE_RANGE_M: float = 150.0
const SOC_GATE_RANGE_GROWTH_MPS: float = 50.0
const SOC_GATE_RADIAL_VELOCITY_MPS: float = 20.0
const SOC_GATE_MAX_ANGLE_GROWTH_RAD: float = deg_to_rad(3.0)
# A track seen once may have moved anywhere the fastest target could fly.
const SOC_INITIATION_GATE_M: float = 300.0
const SOC_INITIATION_MAX_SPEED_MPS: float = 1100.0
# Track numbers are the system's own, unrelated to the targets.
var _next_track_number: int = 1
var _soc_passes: Dictionary = {}
const BEAM_WIDTH_RAD: float = deg_to_rad(6.0)
const TRACK_DECAY_TIME: float = 5.0
# The search radar revisits a target once per second; a locked track older
# than this has stopped being measured.
const LOCKED_TRACK_COAST_LIMIT_S: float = 1.5
const MIN_TIME_FOR_VELOCITY_CALC: float = 0.1 

const OPTIC_AZIMUTH_LIMIT: float = deg_to_rad(45.0)

const GUN_MUZZLE_VELOCITY: float = 960.0
const GUN_RATE_OF_FIRE: float = 0.024
const GUN_MAX_RANGE_M: float = 3000.0
# Gun muzzle height above the vehicle origin; bullets are spawned from here.
const GUN_MUZZLE_HEIGHT_M: float = 3.0
const GUN_LEAD_SCAN_STEP_S: float = 0.05
const GUN_LEAD_BISECTION_STEPS: int = 20
# Matches the shell lifetime in PantsirBullet.
const GUN_LEAD_MAX_TIME_S: float = 5.0
const GUN_GRAVITY_MPS2: float = 9.8
const GUN_MAX_PITCH_RAD: float = deg_to_rad(85.0)
# A lead more than this far from the line of sight means the target is passing
# overhead; the turret would swing round and drag the visor with it.
const GUN_MAX_LEAD_OFF_LOS_RAD: float = deg_to_rad(60.0)
# False while the guns have no usable firing solution on the locked target.
var gun_solution_valid: bool = false

# АВТ-П (АО switch): the complex engages the designated target by itself.
# Missiles are launched while launch is allowed and none is already flying at
# the target; inside gun range the cannons fire in bursts once laid on the lead.
const AUTO_FIRE_GUN_AIM_TOLERANCE_RAD: float = deg_to_rad(0.1)
const AUTO_FIRE_BURST_S: float = 1.5
const AUTO_FIRE_BURST_PAUSE_S: float = 0.7
# Оценка результатов стрельбы: after a missile at the target ends, wait before
# relaunching so a kill is seen first.
const AUTO_FIRE_KILL_ASSESSMENT_S: float = 2.0
var _last_missile_end_s: Dictionary = {}
var auto_fire_on: bool = false
var _auto_fire_burst_left_s: float = 0.0
var _auto_fire_pause_left_s: float = 0.0
var gun_fire_timer: float = 0.0
var ammo_guns: int = 1200
var gun_ammo_by_barrel: Array[int] = [300, 300, 300, 300]
var next_gun_barrel: int = 0

const MISSILE_COOLDOWN_TIME: float = 2.0
const MISSILE_ARM_RAISE_TIME: float = 1.0
const LAUNCHER_ARM_TUBES: Array = [
	[0, 4, 8],   # 1, 5, 9: left outer arm
	[1, 5, 9],   # 2, 6, 10: left inner arm
	[2, 6, 10],  # 3, 7, 11: right inner arm
	[3, 7, 11],  # 4, 8, 12: right outer arm
]
const LAUNCHER_ARM_LATERAL_OFFSETS_M: Array[float] = [-2.7, -1.45, 1.45, 2.7]
var missile_cooldown_timer: float = 0.0
var ammo_missiles: int = 12
var missile_tubes_loaded: Array[bool] = [
	true, true, true, true,
	true, true, true, true,
	true, true, true, true,
]
# Loadout chosen in the reload menu: missile type and count per tube ("" =
# empty) and belt type per gun (two 2А38М twin cannons, two barrels each).
# The С1 fires the 95Я6; the СМ the 40 km 95Я6М and the small ТКБ-1055, four
# of which fit in one tube.
const MISSILE_95YA6: String = "95Я6"
const MISSILE_95YA6M: String = "95Я6М"
const MISSILE_TKB_1055: String = "ТКБ-1055"
const MISSILE_TYPES_BY_COMPLEX: Dictionary = {
	"S1": [MISSILE_95YA6],
	"SM": [MISSILE_95YA6M, MISSILE_TKB_1055],
	"SM-SV": [MISSILE_95YA6M, MISSILE_TKB_1055],
}
const MISSILES_PER_TUBE: Dictionary = {MISSILE_TKB_1055: 4}
# Loaded container mass where it differs from missiles × launch mass:
# four ТКБ-1055 with their container weigh 115 kg.
const TUBE_LOAD_MASS_KG: Dictionary = {MISSILE_TKB_1055: 115.0}
const GUN_BELT_TYPES: Array[String] = ["30 мм ОФЗ-Т"]
const GUN_ROUNDS_PER_BARREL: int = 300
const GUN_ROUND_MASS_KG: float = 0.84
var missile_tube_types: Array[String] = []
var missile_tube_counts: Array[int] = []
var gun_belt_types: Array[String] = []
# Flight model per missile type, mapped from War Thunder data.
const MISSILE_FLIGHT_CONFIGS: Dictionary = {
	MISSILE_95YA6: preload("res://Resources/PantsirMissileFlightConfig.tres"),
	MISSILE_95YA6M: preload("res://Resources/Missile95Ya6MFlightConfig.tres"),
	MISSILE_TKB_1055: preload("res://Resources/MissileTKB1055FlightConfig.tres"),
}
# Missile type the operator fires; missile_flight_config follows it.
var selected_missile_type: String = MISSILE_95YA6
# A requested reload is carried out by the transport-loader; nothing can be
# fired until it is done.
const RELOAD_TIME_S: float = 30.0
var reload_time_left_s: float = 0.0
var _pending_loadout: Dictionary = {}

# СПЗ (ручная настройка СОЦ): plots outside these limits are filtered out of
# the target picture. "АВТОМАТИЧЕСКАЯ НАСТРОЙКА" uses the defaults.
const SPZ_DEFAULTS: Dictionary = {
	"speed_limit_mps": 15.0,
	"lower_height_m": 50.0,
	"lower_angle_deg": 0.0,
	"rcs_threshold_m2": 0.01,
	"upper_height_m": 10000.0,
}
const SPZ_RCS_THRESHOLDS: Array[float] = [0.0001, 0.001, 0.01]
var spz_settings: Dictionary = SPZ_DEFAULTS.duplicate()
var spz_auto: bool = false
# Spread of the СОЦ RCS estimate from one plot, in decades (about ±3 dB).
const SOC_RCS_ESTIMATE_SIGMA_DECADES: float = 0.3
const SOC_RCS_ESTIMATE_SMOOTHING: float = 0.3

# С1 СОЦ scans elevation in sectors: the antenna covers one sector per half
# turn (both beams together sweep the full azimuth), so a target is revisited
# once per full cycle of sectors. Sectors span from the lower angle up to the
# angle at which the upper height is seen at the missile's maximum range.
const SOC_SECTOR_MAX_WIDTH_DEG: float = 15.0
const SOC_MIN_SPAN_DEG: float = 5.0
const SOC_MAX_ELEVATION_DEG: float = 80.0
const SOC_SECTOR_EDGE_MARGIN_RAD: float = deg_to_rad(1.0)
var soc_sectors: Array = []
var soc_current_sector: int = 0
var _soc_sector_rotation_rad: float = 0.0
var _next_launcher_arm_cursor: int = 0
var _selected_missile_tube_index: int = -1
var _pending_missile_launch: Dictionary = {}
# The motor flare whites out the thermal visor right after launch.
var last_missile_launch_time_s: float = -INF
var _missile_arm_raise_timer: float = 0.0

var missile_scene = preload("res://Scenes/PantsirMissile.tscn")
var bullet_script = preload("res://Scripts/PantsirBullet.gd")

var scene_drone = preload("res://Scenes/Drone_Lutiy.tscn")
var scene_tomahawk = preload("res://Scenes/TOMAHAWK.tscn")
var script_ballistic = preload("res://Scripts/BallisticTarget.gd") 

var guidance_channels: Array = [null, null, null, null]
var launcher_offset: Vector3 = Vector3(0, 3.5, 0)

# The МРЛС (АФАР) runs допоиск on every target in its sector. A target becomes
# a precise track (АС) after three dwells have detected it, and drops back
# to ДПЦ when the return is lost. The search radar is stronger, so a far or
# small target can stay in ДПЦ for a long time. Only precise tracks are shown
# on the visor and can be engaged.
const MRLS_MODE_NONE: String = ""
const MRLS_MODE_ACQUISITION: String = "ДПЦ"
const MRLS_MODE_TRACK: String = "АС"
# The АФАР revisits each target in the sector once per second.
const MRLS_ACQUISITION_DWELL_S: float = 1.0
const MRLS_ACQUISITION_HITS_REQUIRED: int = 3
# Tracking concentrates energy on the target, extending its reference range.
const MRLS_TRACK_RANGE_GAIN: float = 1.6
const MRLS_TRACK_LOSS_TIME_S: float = 0.6
# АС when MRLS_ACQUISITION_HITS_REQUIRED of the last N допоиск dwells found a
# plot in the gate.
const MRLS_ACQUISITION_WINDOW: int = 5
# Agreement between допоиск hits: a few МРЛС range/velocity errors, plus what
# a target's radial acceleration can change between dwells.
const MRLS_CONFIRM_RANGE_TOLERANCE_M: float = 20.0
const MRLS_CONFIRM_RADIAL_VELOCITY_TOLERANCE_MPS: float = 2.0
const MRLS_CONFIRM_ACCELERATION_MPS2: float = 10.0

# Millimetre-band МРЛС. Two targets merge into one plot only when they share a
# resolution cell in angle, range and radial velocity at the same time.
const MRLS_RESOLUTION_ANGLE_RAD: float = deg_to_rad(0.5)
const MRLS_RESOLUTION_RANGE_M: float = 10.0
const MRLS_RESOLUTION_VELOCITY_MPS: float = 0.5
const MRLS_FALSE_ALARM_PER_CELL: float = 0.000001

# Gate half-widths. The допоиск gate spans ±3σ of the СОЦ designation; its
# range part grows with the age of that designation.
const ACQUISITION_GATE_AZIMUTH_RAD: float = deg_to_rad(1.0)
const ACQUISITION_GATE_ELEVATION_RAD: float = deg_to_rad(3.0)
const ACQUISITION_GATE_RANGE_M: float = 150.0
const ACQUISITION_GATE_RANGE_GROWTH_MPS: float = 50.0
const ACQUISITION_GATE_RADIAL_VELOCITY_MPS: float = 15.0
const ACQUISITION_GATE_MAX_ANGLE_GROWTH_RAD: float = deg_to_rad(1.0)
# Tracking gate around the precise МРЛС prediction (АС).
const TRACK_GATE_ANGLE_RAD: float = deg_to_rad(0.2)
const TRACK_GATE_MIN_LINEAR_M: float = 10.0
const TRACK_GATE_RANGE_M: float = 15.0
const TRACK_GATE_RADIAL_VELOCITY_MPS: float = 5.0

# МРЛС measurement errors, 1 sigma (variables so tests can switch noise off).
var mrls_angle_sigma_rad: float = deg_to_rad(0.03)
var mrls_range_sigma_m: float = 3.0
var mrls_velocity_sigma_mps: float = 0.2
const VISOR_AUTO_TRACK_TOLERANCE_RAD: float = deg_to_rad(0.5)

# After launch the МРЛС first searches for the missile (П-РЛ), then guides it (ЦУ).
const MISSILE_PHASE_SEARCH: String = "П-РЛ"
const MISSILE_PHASE_COMMAND: String = "ЦУ"
const MISSILE_CAPTURE_MIN_S: float = 0.6
const MISSILE_CAPTURE_MAX_S: float = 1.4
# Each capture attempt succeeds with this probability while the missile is in
# the МРЛС sector; attempts repeat until the deadline after launch.
const MISSILE_CAPTURE_PROBABILITY: float = 0.6
const MISSILE_CAPTURE_RETRY_S: float = 0.4
const MISSILE_CAPTURE_DEADLINE_S: float = 2.5

const SIGNATURE_CLASSES: Array[String] = ["ВЕРТ", "ДПЛА", "КР", "САМ"]
# Weak, noisy returns read most often as a helicopter.
const SIGNATURE_NOISE_CLASS: String = "ВЕРТ"
const CLASSIFICATION_TIME_CONSTANT_S: float = 4.0
const DETECTION_SEED: int = 284611

# МРЛС mode of the locked target.
var mrls_mode: String = MRLS_MODE_NONE
var target_channels: Array[int] = [-1, -1, -1, -1]
# Per-target МРЛС state: {hits, next_dwell_s, precise, last_detection_s, track_start_s}.
var _mrls_target_states: Dictionary = {}
var _target_classifications: Dictionary = {}
var _detection_rng := RandomNumberGenerator.new()

var _global_target_id_counter: int = 0

# Procedural terrain of the current session; null means flat ground at 0 m.
var terrain: Node = null

func get_ground_height(x: float, z: float) -> float:
	if terrain != null and is_instance_valid(terrain):
		return terrain.get_height(x, z)
	return 0.0

# Factor applied to radar detection ranges on a path through the forest.
func get_radar_range_factor(from: Vector3, to: Vector3) -> float:
	if terrain != null and is_instance_valid(terrain):
		return terrain.radar_range_factor(from, to)
	return 1.0

func _ready() -> void:
	_measurement_rng.seed = MEASUREMENT_SEED
	_detection_rng.seed = DETECTION_SEED
	_select_next_missile_tube()

func _physics_process(delta):
	_process_reload(delta)
	if master_power_on:
		_simulation_time_s += delta
		master_power_elapsed += delta
		complex_ready = master_power_elapsed >= COMPLEX_READY_DELAY
		if complex_ready:
			GameSettings.add_combat_mode_time(delta)

		if missile_cooldown_timer > 0:
			missile_cooldown_timer -= delta
		process_pending_missile_launch(delta)
			
		if search_radar_on:
			process_search_radar(delta)

		# Measurements must be incorporated before any consumer asks for the
		# current target state during this physics tick.
		process_radar_logic(delta)
		process_mrls_target_channel()
		process_auto_tracking(delta)
		process_kinematics(delta)
		# Guidance runs first so missiles that ended this tick are already
		# released and time-stamped when auto fire decides on a relaunch.
		process_missile_guidance(delta)
		process_auto_fire(delta)
		process_gun_fire(delta)

func get_new_uid() -> int:
	_global_target_id_counter += 1
	return _global_target_id_counter

func get_simulation_time_s() -> float:
	return _simulation_time_s

func get_target_node(id: int) -> Node3D:
	var nodes = get_tree().get_nodes_in_group("radar_targets")
	for node in nodes:
		if "radar_id" in node and node.radar_id == id:
			return node
	return null

func get_locked_target_position():
	if locked_track_id == -1:
		return null
	var state = get_predicted_track_state(locked_track_id)
	if !state.is_empty():
		return state["position"]
	return null

func get_predicted_track_state(track_id: int, query_time_s: float = -1.0) -> Dictionary:
	if !tracks.has(track_id):
		return {}
	var track: Dictionary = tracks[track_id]
	var state_time = _simulation_time_s if query_time_s < 0.0 else query_time_s
	var state_age = maxf(state_time - float(track["timestamp"]), 0.0)
	var predicted_position: Vector3 = track["position"]
	var predicted_velocity: Vector3 = track["velocity"]
	var target_filter: KalmanTrack3D = track.get("kalman_filter")
	if target_filter != null:
		predicted_position = target_filter.predicted_position(state_age)
		predicted_velocity = target_filter.velocity
	else:
		predicted_position += predicted_velocity * state_age
	return {
		"position": predicted_position,
		"velocity": predicted_velocity,
		"timestamp": state_time,
		"measurement_timestamp": track["timestamp"],
		"measurement_age_s": state_age,
	}

func get_locked_target_distance() -> float:
	var target_position = get_locked_target_position()
	if target_position == null:
		return -1.0
	return pantsir_position.distance_to(target_position)

func calculate_missile_intercept_range(target_position: Vector3, target_velocity: Vector3) -> float:
	var launch_position = pantsir_position + launcher_offset
	# Use the configured top speed for the operator's simple lead-point estimate.
	var intercept_time = MissileGuidance.intercept_time(
		target_position - launch_position,
		target_velocity,
		missile_flight_config.maximum_speed_mps,
		missile_flight_config.maximum_flight_time_s
	)
	if intercept_time < 0.0:
		return -1.0
	var intercept_position = target_position + target_velocity * intercept_time
	return launch_position.distance_to(intercept_position)

func get_estimated_missile_intercept_range(target_id: int) -> float:
	var target_state = get_predicted_track_state(target_id)
	if target_state.is_empty():
		return -1.0
	return calculate_missile_intercept_range(target_state["position"], target_state["velocity"])

func get_nearest_guided_missile_range_to_locked_target() -> float:
	var target_position = get_locked_target_position()
	if target_position == null:
		return -1.0

	var nearest_missile = null
	var nearest_target_distance = INF
	for channel in guidance_channels:
		if channel == null or channel["target_id"] != locked_track_id:
			continue
		var missile = channel["missile"]
		if !is_instance_valid(missile):
			continue
		if "is_active" in missile and !missile.is_active:
			continue
		var distance_to_target = missile.global_position.distance_to(target_position)
		if distance_to_target < nearest_target_distance:
			nearest_target_distance = distance_to_target
			nearest_missile = missile

	if nearest_missile == null:
		return -1.0
	return pantsir_position.distance_to(nearest_missile.global_position)

func is_locked_target_on_auto_tracking() -> bool:
	return sector_radar_on and mrls_mode == MRLS_MODE_TRACK and get_locked_target_position() != null

# АСЛ: the visor is locked onto the target, i.e. the target is in АС and the
# optic has settled on its line of sight.
func is_visor_auto_tracking() -> bool:
	if !is_locked_target_on_auto_tracking():
		return false
	return (
		absf(angle_difference(optic_current_angle, optic_target_angle)) < VISOR_AUTO_TRACK_TOLERANCE_RAD
		and absf(optic_current_pitch - optic_target_pitch) < VISOR_AUTO_TRACK_TOLERANCE_RAD
	)

func process_mrls_target_channel() -> void:
	if !sector_radar_on:
		_reset_mrls_target_channel()
	else:
		var stale_ids = []
		for uid in _mrls_target_states:
			var state: Dictionary = _mrls_target_states[uid]
			var silence = _simulation_time_s - float(state["last_detection_s"])
			if state["precise"] and silence > MRLS_TRACK_LOSS_TIME_S:
				# Lost the return: fall back to допоиск on the search-radar track.
				state["precise"] = false
				state["hits"] = 0
				state["history"] = []
			elif !state["precise"] and !tracks.has(uid):
				stale_ids.append(uid)
		for uid in stale_ids:
			_mrls_target_states.erase(uid)
	if locked_track_id == -1 or !sector_radar_on:
		mrls_mode = MRLS_MODE_NONE
	else:
		mrls_mode = MRLS_MODE_TRACK if is_track_precise(locked_track_id) else MRLS_MODE_ACQUISITION
	_update_target_classification()
	_release_idle_target_channels()

func _reset_mrls_target_channel() -> void:
	mrls_mode = MRLS_MODE_NONE
	_mrls_target_states.clear()

func is_track_precise(track_id: int) -> bool:
	return sector_radar_on and _mrls_target_states.get(track_id, {}).get("precise", false)

# Simulation-side truth: the target node whose echo a track last took. Used
# for the missile fuze and visor frames, never for plot association.
func get_track_target_node(track_id: int) -> Node3D:
	if !tracks.has(track_id):
		return null
	return get_target_node(int(tracks[track_id].get("source_id", -1)))

func is_target_tracked_precisely(radar_id: int) -> bool:
	for track_id in tracks:
		if int(tracks[track_id].get("source_id", -1)) == radar_id and is_track_precise(track_id):
			return true
	return false

# Probability that one МРЛС dwell detects the target.
func _mrls_detection_probability(t_data: Dictionary, range_gain: float) -> float:
	return _detection_probability(t_data, MRLS_PROFILE, range_gain)

# One draw per СОЦ antenna pass: the beam can cover a target for two radar
# ticks, which must not double its chance.
func _soc_detects(t_data: Dictionary) -> bool:
	var uid = t_data["id"]
	var last_pass: Dictionary = _soc_passes.get(uid, {})
	if !last_pass.is_empty() and _simulation_time_s - float(last_pass["time_s"]) < SOC_PASS_GROUPING_S:
		return last_pass["detected"]
	var detected = _detection_rng.randf() < _detection_probability(t_data, SOC_PROFILE, 1.0)
	_soc_passes[uid] = {"time_s": _simulation_time_s, "detected": detected}
	return detected

# Ground clutter shortens detection range. Echoes with a radial velocity
# inside the Doppler notch (targets flying across the beam) are rejected
# together with the clutter, and low targets compete with ground returns.
func _clutter_range_factor(t_data: Dictionary, profile: Dictionary) -> float:
	var position: Vector3 = t_data["position"]
	var relative = position - pantsir_position
	var radial_velocity = absf(t_data.get("velocity", Vector3.ZERO).dot(relative / maxf(relative.length(), 1.0)))
	var notch = float(profile["notch_mps"])
	var factor = lerpf(DOPPLER_NOTCH_RANGE_FACTOR, 1.0, smoothstep(notch * 0.5, notch, radial_velocity))
	var height_above_ground = position.y - get_ground_height(position.x, position.z)
	factor *= lerpf(profile["low_altitude_floor"], 1.0, smoothstep(LOW_ALTITUDE_CLUTTER_FULL_M, LOW_ALTITUDE_CLUTTER_CLEAR_M, height_above_ground))
	return factor

# 50% detection range follows the radar equation: R50 = R50(1 m²) · σ^¼.
# The RCS fluctuates from look to look (Swerling 1: exponential around its
# aspect mean). Targets without RCS data are always detected.
func _detection_probability(t_data: Dictionary, profile: Dictionary, range_gain: float) -> float:
	var mean_rcs = float(t_data.get("rcs_m2", 0.0))
	if mean_rcs <= 0.0:
		return 1.0
	var look_rcs = mean_rcs * -log(maxf(1.0 - _detection_rng.randf(), 0.000001))
	var effective_range = (
		float(profile["r50_1m2_m"]) * pow(look_rcs, 0.25)
		* range_gain
		* float(t_data.get("radar_range_factor", 1.0))
		* _clutter_range_factor(t_data, profile)
	)
	if effective_range <= 0.0:
		return 0.0
	var range_ratio = pantsir_position.distance_to(t_data["position"]) / effective_range
	# Signal falls as R^4; detection probability is a steep function of signal
	# (about 6–8 dB from 90% to 10%), so the R^4 ratio is raised further.
	return 1.0 / (1.0 + pow(range_ratio, 4.0 * DETECTION_CURVE_STEEPNESS))

func _mrls_state(uid: int) -> Dictionary:
	if !_mrls_target_states.has(uid):
		_mrls_target_states[uid] = {
			"hits": 0,
			"history": [],
			"next_dwell_s": _simulation_time_s,
			"precise": false,
			"last_detection_s": _simulation_time_s,
			"track_start_s": _simulation_time_s,
		}
	return _mrls_target_states[uid]

# Radar coordinates of a point: azimuth, elevation, slant range, radial velocity.
func _to_radar_polar(position: Vector3, velocity: Vector3) -> Dictionary:
	var relative = position - pantsir_position
	var slant_range = maxf(relative.length(), 1.0)
	return {
		"az": atan2(relative.x, -relative.z),
		"el": asin(clampf(relative.y / slant_range, -1.0, 1.0)),
		"range": slant_range,
		"vr": velocity.dot(relative / slant_range),
	}

func _from_radar_polar(azimuth: float, elevation: float, slant_range: float) -> Vector3:
	return pantsir_position + Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		-cos(azimuth) * cos(elevation)
	) * slant_range

# One МРЛС pass over the sector: a plot per detected echo. Plots know nothing
# about which target they came from; echoes inside one resolution cell merge
# into a single plot at their centroid.
func _generate_mrls_plots() -> Array:
	var echoes = []
	for t_data in targets:
		var polar = _to_radar_polar(t_data["position"], t_data.get("velocity", Vector3.ZERO))
		if absf(angle_difference(turret_current_angle, polar["az"])) >= SECTOR_WIDTH_RAD:
			continue
		# Energy is concentrated on directions already held in АС.
		var range_gain = MRLS_TRACK_RANGE_GAIN if is_target_tracked_precisely(t_data["id"]) else 1.0
		if _detection_rng.randf() >= _mrls_detection_probability(t_data, range_gain):
			continue
		polar["velocity"] = t_data.get("velocity", Vector3.ZERO)
		polar["source"] = t_data
		polar["count"] = 1
		echoes.append(polar)

	var plots = _merge_echoes(echoes, MRLS_RESOLUTION_ANGLE_RAD, MRLS_RESOLUTION_ANGLE_RAD, MRLS_RESOLUTION_RANGE_M, MRLS_RESOLUTION_VELOCITY_MPS)

	for i in range(plots.size()):
		var plot: Dictionary = plots[i]
		plot["index"] = i
		plot["az"] += _measurement_rng.randfn(0.0, mrls_angle_sigma_rad)
		plot["el"] += _measurement_rng.randfn(0.0, mrls_angle_sigma_rad)
		plot["range"] += _measurement_rng.randfn(0.0, mrls_range_sigma_m)
		plot["vr"] += _measurement_rng.randfn(0.0, mrls_velocity_sigma_mps)
		plot["velocity"] += Vector3(
			_measurement_rng.randfn(0.0, mrls_velocity_sigma_mps),
			_measurement_rng.randfn(0.0, mrls_velocity_sigma_mps),
			_measurement_rng.randfn(0.0, mrls_velocity_sigma_mps)
		)
		plot["position"] = _from_radar_polar(plot["az"], plot["el"], plot["range"])
	return plots

# Rare noise crossing inside a gate: one random plot with probability equal to
# the expected number of false alarms over the gate's resolution cells.
func _false_alarm_plots(center: Dictionary, gate: Dictionary, velocity: Vector3, first_index: int) -> Array:
	var cells = (
		(2.0 * gate["az"] / MRLS_RESOLUTION_ANGLE_RAD)
		* (2.0 * gate["el"] / MRLS_RESOLUTION_ANGLE_RAD)
		* (2.0 * gate["range"] / MRLS_RESOLUTION_RANGE_M)
		* (2.0 * gate["vr"] / MRLS_RESOLUTION_VELOCITY_MPS)
	)
	if _detection_rng.randf() >= cells * MRLS_FALSE_ALARM_PER_CELL:
		return []
	var plot = {
		"az": center["az"] + _detection_rng.randf_range(-1.0, 1.0) * gate["az"],
		"el": center["el"] + _detection_rng.randf_range(-1.0, 1.0) * gate["el"],
		"range": center["range"] + _detection_rng.randf_range(-1.0, 1.0) * gate["range"],
		"vr": center["vr"] + _detection_rng.randf_range(-1.0, 1.0) * gate["vr"],
		"velocity": velocity,
		"count": 0,
		"index": first_index,
	}
	plot["position"] = _from_radar_polar(plot["az"], plot["el"], plot["range"])
	return [plot]

# Gate prediction for a track at the radar scan time. In АС it is the precise
# МРЛС track; in ДПЦ it is the last СОЦ plot moved along its radial velocity.
func _gate_center(uid: int, scan_time_s: float, precise: bool) -> Dictionary:
	var predicted = get_predicted_track_state(uid, scan_time_s)
	if predicted.is_empty():
		return {}
	if precise:
		return _to_radar_polar(predicted["position"], predicted["velocity"])
	var track: Dictionary = tracks[uid]
	var age = float(predicted["measurement_age_s"])
	var designation = _to_radar_polar(track.get("measured_position", predicted["position"]), Vector3.ZERO)
	designation["vr"] = float(track.get("radial_velocity", 0.0))
	designation["range"] += designation["vr"] * age
	designation["age_s"] = age
	# The target moves across the beam while the designation ages: point the
	# gate along the filter's prediction and widen it by its uncertainty.
	var predicted_polar = _to_radar_polar(predicted["position"], Vector3.ZERO)
	designation["az"] = predicted_polar["az"]
	designation["el"] = predicted_polar["el"]
	designation["angle_growth"] = _track_angle_uncertainty_rad(track, age, designation["range"], ACQUISITION_GATE_MAX_ANGLE_GROWTH_RAD)
	return designation

# Matches the pass's plots to track gates. Each gate takes its nearest plot
# (distance normalised by gate size) and each plot feeds one gate, nearest
# pairs first. A wrong target or a false alarm can be picked when it lies
# closer to the prediction than the designated target.
# Returns uid -> plot for tracks in АС.
func _associate_mrls_plots(plots: Array) -> Dictionary:
	var scan_time_s = float(targets[0].get("measurement_timestamp", _simulation_time_s)) if !targets.is_empty() else _simulation_time_s
	var candidates = []
	var acquisition_dwells = []
	var next_plot_index = plots.size()
	for uid in tracks:
		var precise = is_track_precise(uid)
		var center = _gate_center(uid, scan_time_s, precise)
		if center.is_empty() or absf(angle_difference(turret_current_angle, center["az"])) >= SECTOR_WIDTH_RAD:
			continue
		var state = _mrls_state(uid)
		var gate: Dictionary
		var gate_plots = plots
		if precise:
			var angle_gate = maxf(TRACK_GATE_ANGLE_RAD, TRACK_GATE_MIN_LINEAR_M / center["range"])
			gate = {"az": angle_gate, "el": angle_gate, "range": TRACK_GATE_RANGE_M, "vr": TRACK_GATE_RADIAL_VELOCITY_MPS}
		else:
			# Допоиск: the МРЛС sweeps the sector once per second.
			if _simulation_time_s < float(state["next_dwell_s"]):
				continue
			state["next_dwell_s"] = _simulation_time_s + MRLS_ACQUISITION_DWELL_S
			acquisition_dwells.append(uid)
			gate = {
				"az": ACQUISITION_GATE_AZIMUTH_RAD + center.get("angle_growth", 0.0),
				"el": ACQUISITION_GATE_ELEVATION_RAD + center.get("angle_growth", 0.0),
				"range": ACQUISITION_GATE_RANGE_M + ACQUISITION_GATE_RANGE_GROWTH_MPS * center["age_s"],
				"vr": ACQUISITION_GATE_RADIAL_VELOCITY_MPS,
			}
			var false_alarms = _false_alarm_plots(center, gate, tracks[uid]["velocity"], next_plot_index)
			next_plot_index += false_alarms.size()
			gate_plots = plots + false_alarms
		for plot in gate_plots:
			var d_az = angle_difference(center["az"], plot["az"]) / gate["az"]
			var d_el = (plot["el"] - center["el"]) / gate["el"]
			var d_range = (plot["range"] - center["range"]) / gate["range"]
			var d_vr = (plot["vr"] - center["vr"]) / gate["vr"]
			if absf(d_az) > 1.0 or absf(d_el) > 1.0 or absf(d_range) > 1.0 or absf(d_vr) > 1.0:
				continue
			candidates.append({
				"distance": d_az * d_az + d_el * d_el + d_range * d_range + d_vr * d_vr,
				"uid": uid,
				"plot": plot,
			})

	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])
	var assigned = {}
	var used_plots = {}
	for candidate in candidates:
		if assigned.has(candidate["uid"]) or used_plots.has(candidate["plot"]["index"]):
			continue
		assigned[candidate["uid"]] = candidate["plot"]
		used_plots[candidate["plot"]["index"]] = true

	for uid in acquisition_dwells:
		var state: Dictionary = _mrls_target_states[uid]
		var history: Array = state.get("history", [])
		var hit = {}
		if assigned.has(uid):
			hit = {"time_s": scan_time_s, "range": assigned[uid]["range"], "vr": assigned[uid]["vr"]}
		history.append(hit)
		if history.size() > MRLS_ACQUISITION_WINDOW:
			history.pop_front()
		state["history"] = history
		state["hits"] = _consistent_hit_count(history)
		if state["hits"] >= MRLS_ACQUISITION_HITS_REQUIRED:
			state["precise"] = true
			state["track_start_s"] = _simulation_time_s

	var measurements = {}
	for uid in assigned:
		var state: Dictionary = _mrls_target_states[uid]
		if state["precise"]:
			state["last_detection_s"] = _simulation_time_s
			measurements[uid] = assigned[uid]
	return measurements

# Допоиск hits that belong to one target as the latest hit sees it: each
# earlier hit's range, carried forward by its radial velocity, and its radial
# velocity must agree with the latest one. A false alarm lands anywhere in
# the gate and almost never agrees, so it cannot confirm a track on noise.
func _consistent_hit_count(history: Array) -> int:
	var latest: Dictionary = {}
	for i in range(history.size() - 1, -1, -1):
		if !history[i].is_empty():
			latest = history[i]
			break
	if latest.is_empty():
		return 0
	var count = 0
	for hit in history:
		if hit.is_empty():
			continue
		var dt = float(latest["time_s"]) - float(hit["time_s"])
		var predicted_range = float(hit["range"]) + 0.5 * (float(hit["vr"]) + float(latest["vr"])) * dt
		var range_tolerance = MRLS_CONFIRM_RANGE_TOLERANCE_M + MRLS_CONFIRM_ACCELERATION_MPS2 * 0.5 * dt * dt
		var vr_tolerance = MRLS_CONFIRM_RADIAL_VELOCITY_TOLERANCE_MPS + MRLS_CONFIRM_ACCELERATION_MPS2 * dt
		if absf(predicted_range - float(latest["range"])) <= range_tolerance and absf(float(hit["vr"]) - float(latest["vr"])) <= vr_tolerance:
			count += 1
	return count

func _mrls_measurement_variance(slant_range: float) -> float:
	var sigma = maxf(slant_range * mrls_angle_sigma_rad, mrls_range_sigma_m)
	return maxf(sigma * sigma, 0.000001)

# Signature recognition runs only in АС. Early guesses are noisy and jump
# between classes; confidence grows with tracking time, but a wrong class can
# still flash up now and then.
func _update_target_classification() -> void:
	if mrls_mode != MRLS_MODE_TRACK:
		return
	var info: Dictionary = _target_classifications.get(locked_track_id, {"guess": "", "next_change_s": 0.0})
	if _simulation_time_s < float(info["next_change_s"]):
		return
	var true_class: String = tracks[locked_track_id].get("signature_class", "") if tracks.has(locked_track_id) else ""
	var track_start_s = float(_mrls_target_states.get(locked_track_id, {}).get("track_start_s", _simulation_time_s))
	var confidence = 1.0 - exp(-(_simulation_time_s - track_start_s) / CLASSIFICATION_TIME_CONSTANT_S)
	var true_probability = 0.0 if true_class.is_empty() else lerpf(0.15, 0.9, confidence)
	var guess = true_class
	if _detection_rng.randf() >= true_probability:
		var wrong_classes: Array[String] = []
		for signature_class in SIGNATURE_CLASSES:
			if signature_class != true_class:
				wrong_classes.append(signature_class)
		if SIGNATURE_NOISE_CLASS in wrong_classes and _detection_rng.randf() < lerpf(0.6, 0.3, confidence):
			guess = SIGNATURE_NOISE_CLASS
		else:
			guess = wrong_classes[_detection_rng.randi_range(0, wrong_classes.size() - 1)]
	info["guess"] = guess
	info["next_change_s"] = _simulation_time_s + _detection_rng.randf_range(0.4, 0.9) * lerpf(1.0, 3.5, confidence)
	_target_classifications[locked_track_id] = info

func get_target_classification(track_id: int) -> String:
	return _target_classifications.get(track_id, {}).get("guess", "")

func _target_has_missiles(track_id: int) -> bool:
	for channel in guidance_channels:
		if channel != null and channel["target_id"] == track_id and is_instance_valid(channel["missile"]):
			return true
	return false

func is_target_under_attack(track_id: int) -> bool:
	return track_id != -1 and _target_has_missiles(track_id)

# A target channel is assigned as soon as a target is taken for tracking.
func _assign_target_channel(track_id: int) -> void:
	if track_id in target_channels:
		return
	_release_idle_target_channels()
	for i in range(target_channels.size()):
		if target_channels[i] == -1:
			target_channels[i] = track_id
			return

func _release_idle_target_channels() -> void:
	for i in range(target_channels.size()):
		var track_id = target_channels[i]
		if track_id != -1 and track_id != locked_track_id and !_target_has_missiles(track_id):
			target_channels[i] = -1

func get_target_channel(track_id: int) -> int:
	return target_channels.find(track_id) if track_id != -1 else -1

func get_missile_phase(channel: Dictionary) -> String:
	if !channel.get("missile_captured", true):
		return MISSILE_PHASE_SEARCH
	return MISSILE_PHASE_COMMAND

# Phase of the most recently launched missile still flying at the target.
func get_missile_phase_for_target(track_id: int) -> String:
	var phase = ""
	var latest_launch = -INF
	for channel in guidance_channels:
		if channel == null or channel["target_id"] != track_id or !is_instance_valid(channel["missile"]):
			continue
		if float(channel.get("launch_time_s", 0.0)) > latest_launch:
			latest_launch = float(channel.get("launch_time_s", 0.0))
			phase = get_missile_phase(channel)
	return phase

func _has_radar_return(track_id: int) -> bool:
	if !tracks.has(track_id):
		return false
	var source_id = int(tracks[track_id].get("source_id", track_id))
	for t_data in targets:
		if t_data["id"] == source_id:
			return true
	return false

# Servo-like aim point: it moves with the track velocity and is pulled towards
# each new track position with this time constant. Measurement noise is
# smoothed out while a moving target is followed without lag.
const AIM_SMOOTHING_TIME_S: float = 0.3
var _aim_point := Vector3.ZERO
var _aim_track_id: int = -1

func process_auto_tracking(delta):
	if locked_track_id == -1 or !sector_radar_on:
		turret_target_angle = turret_current_angle
		optic_target_angle = turret_current_angle
		optic_target_pitch = turret_current_pitch
		return

	var target_state = get_predicted_track_state(locked_track_id)
	if target_state.is_empty():
		locked_track_id = -1
		return
	if float(target_state["measurement_age_s"]) > _locked_track_coast_limit_s() or !_has_radar_return(locked_track_id):
		# No echo or no fresh measurements (target destroyed or lost): hold the
		# last pointing instead of following an ever longer extrapolation.
		gun_solution_valid = false
		return
	var target_pos: Vector3 = target_state["position"]
	var target_vel: Vector3 = target_state["velocity"]
	if _aim_track_id != locked_track_id:
		_aim_point = target_pos
		_aim_track_id = locked_track_id
	else:
		_aim_point += target_vel * delta
		_aim_point += (target_pos - _aim_point) * clampf(delta / AIM_SMOOTHING_TIME_S, 0.0, 1.0)
	target_pos = _aim_point

	var rel_los = target_pos - pantsir_position
	optic_target_angle = atan2(rel_los.x, -rel_los.z)
	
	var dist_horiz = Vector2(rel_los.x, rel_los.z).length()
	var height_diff = rel_los.y - launcher_offset.y
	optic_target_pitch = atan2(height_diff, dist_horiz)
	
	if selected_weapon == "GUNS":
		var aim_direction = calculate_gun_aim_direction(target_pos, target_vel, get_gun_muzzle_position(), GUN_MUZZLE_VELOCITY)
		gun_solution_valid = false
		if aim_direction != Vector3.ZERO:
			var aim_azimuth = atan2(aim_direction.x, -aim_direction.z)
			var aim_pitch = atan2(aim_direction.y, Vector2(aim_direction.x, aim_direction.z).length())
			gun_solution_valid = (
				aim_pitch <= GUN_MAX_PITCH_RAD
				and absf(angle_difference(optic_target_angle, aim_azimuth)) <= GUN_MAX_LEAD_OFF_LOS_RAD
			)
			if gun_solution_valid:
				turret_target_angle = aim_azimuth
				turret_target_pitch = aim_pitch
		if !gun_solution_valid:
			# No usable lead: keep the turret on the line of sight instead of
			# chasing a solution over the top or behind the vehicle.
			turret_target_angle = optic_target_angle
			turret_target_pitch = clampf(optic_target_pitch, deg_to_rad(-5.0), GUN_MAX_PITCH_RAD)
	else:
		turret_target_angle = optic_target_angle
		turret_target_pitch = calculate_missile_launch_pitch(optic_target_pitch)

func calculate_missile_launch_pitch(target_line_pitch: float) -> float:
	# During the first boost transient the missile has almost no aerodynamic
	# authority. Aim the canister above the LOS by the thrust angle required to
	# balance gravity normal to that LOS. Treating this as an absolute minimum
	# pitch lets elevated launches sag until timeToGain reaches full authority.
	var clamped_target_pitch = clampf(target_line_pitch, deg_to_rad(-5.0), deg_to_rad(85.0))
	var normal_gravity_to_thrust_ratio = (
		missile_flight_config.launch_mass_kg * PantsirMissile.STANDARD_GRAVITY_MPS2
		* maxf(cos(clamped_target_pitch), 0.0)
		/ maxf(missile_flight_config.thrust_newtons, 1.0)
	)
	var boost_gravity_lead = asin(clampf(normal_gravity_to_thrust_ratio, 0.0, 1.0))
	var launch_pitch = (
		clamped_target_pitch
		+ boost_gravity_lead
		+ deg_to_rad(missile_flight_config.launch_elevation_margin_deg)
	)
	return clampf(launch_pitch, deg_to_rad(-5.0), deg_to_rad(85.0))

func get_gun_muzzle_position() -> Vector3:
	return pantsir_position + Vector3(0.0, GUN_MUZZLE_HEIGHT_M, 0.0)

# Vector the shell must cover by time t to meet the target: the target's
# predicted position, lifted by the gravity drop of a drag-free shell.
func _gun_required_displacement(target_pos: Vector3, target_vel: Vector3, gun_pos: Vector3, time_s: float) -> Vector3:
	var gravity_drop = Vector3(0.0, 0.5 * GUN_GRAVITY_MPS2 * time_s * time_s, 0.0)
	return target_pos + target_vel * time_s - gun_pos + gravity_drop

# Earliest time at which a shell can meet the target, or -1 when there is no
# meeting within the shell lifetime. The meeting time is a root of
# |displacement(t)| - v0·t; it is bracketed by scanning, then bisected. Plain
# fixed-point iteration diverges for targets faster than the shell (MLRS rockets).
func calculate_gun_time_of_flight(target_pos: Vector3, target_vel: Vector3, gun_pos: Vector3, muzzle_speed: float) -> float:
	var previous_time = 0.0
	var time_s = GUN_LEAD_SCAN_STEP_S
	while time_s <= GUN_LEAD_MAX_TIME_S:
		if _gun_required_displacement(target_pos, target_vel, gun_pos, time_s).length() - muzzle_speed * time_s <= 0.0:
			var low = previous_time
			var high = time_s
			for i in range(GUN_LEAD_BISECTION_STEPS):
				var middle = (low + high) * 0.5
				if _gun_required_displacement(target_pos, target_vel, gun_pos, middle).length() - muzzle_speed * middle <= 0.0:
					high = middle
				else:
					low = middle
			return high
		previous_time = time_s
		time_s += GUN_LEAD_SCAN_STEP_S
	return -1.0

# Barrel direction that makes the shell meet the target, gravity included.
# Returns Vector3.ZERO when there is no meeting point.
func calculate_gun_aim_direction(target_pos: Vector3, target_vel: Vector3, gun_pos: Vector3, muzzle_speed: float) -> Vector3:
	var time_of_flight = calculate_gun_time_of_flight(target_pos, target_vel, gun_pos, muzzle_speed)
	if time_of_flight < 0.0:
		return Vector3.ZERO
	return _gun_required_displacement(target_pos, target_vel, gun_pos, time_of_flight).normalized()

# Launch permission shown on the ПУСК lamp. "inner" marks the guaranteed zone.
func get_launch_permission() -> Dictionary:
	var result = {"allowed": false, "inner": false}
	if !is_locked_target_on_auto_tracking():
		return result
	if selected_weapon == "MISSILES":
		var intercept_range = get_estimated_missile_intercept_range(locked_track_id)
		result["allowed"] = intercept_range >= 0.0 and intercept_range <= missile_flight_config.maximum_distance_m
		result["inner"] = result["allowed"] and intercept_range <= missile_flight_config.guaranteed_range_m
	elif selected_weapon == "GUNS":
		var distance = get_locked_target_distance()
		result["allowed"] = distance >= 0.0 and distance <= GUN_MAX_RANGE_M
	return result

func toggle_auto_fire() -> void:
	auto_fire_on = !auto_fire_on
	_auto_fire_burst_left_s = 0.0
	_auto_fire_pause_left_s = 0.0

func _is_turret_laid_on_target() -> bool:
	return (
		absf(angle_difference(turret_current_angle, turret_target_angle)) < AUTO_FIRE_GUN_AIM_TOLERANCE_RAD
		and absf(turret_current_pitch - turret_target_pitch) < AUTO_FIRE_GUN_AIM_TOLERANCE_RAD
	)

func is_target_killed(track_id: int) -> bool:
	return tracks.has(track_id) and tracks[track_id].get("killed", false)

func process_auto_fire(delta: float) -> void:
	if !auto_fire_on or !complex_ready or !is_locked_target_on_auto_tracking() or is_target_killed(locked_track_id):
		_auto_fire_burst_left_s = 0.0
		_auto_fire_pause_left_s = 0.0
		return
	var distance = get_locked_target_distance()
	if distance <= GUN_MAX_RANGE_M and ammo_guns > 0:
		if selected_weapon != "GUNS":
			# The turret re-lays on the gun lead before the first burst.
			selected_weapon = "GUNS"
			return
		if _auto_fire_pause_left_s > 0.0:
			_auto_fire_pause_left_s -= delta
			return
		if !gun_solution_valid or !_is_turret_laid_on_target():
			return
		if _auto_fire_burst_left_s <= 0.0:
			_auto_fire_burst_left_s = AUTO_FIRE_BURST_S
		fire_guns_logic()
		_auto_fire_burst_left_s -= delta
		if _auto_fire_burst_left_s <= 0.0:
			_auto_fire_pause_left_s = AUTO_FIRE_BURST_PAUSE_S
		return
	if selected_weapon != "MISSILES":
		selected_weapon = "MISSILES"
		return
	if _target_has_missiles(locked_track_id) or is_missile_launch_preparing():
		return
	if _simulation_time_s - float(_last_missile_end_s.get(locked_track_id, -INF)) < AUTO_FIRE_KILL_ASSESSMENT_S:
		return
	if get_launch_permission()["allowed"]:
		fire_missile_logic()

func process_kinematics(delta):
	var turret_azimuth_step = clampf(
		angle_difference(turret_current_angle, turret_target_angle),
		-TURRET_ROTATION_SPEED * delta,
		TURRET_ROTATION_SPEED * delta
	)
	turret_current_angle = wrapf(turret_current_angle + turret_azimuth_step, -PI, PI)
	turret_current_pitch = move_toward(turret_current_pitch, turret_target_pitch, TURRET_PITCH_SPEED * delta)
	turret_current_pitch = clamp(turret_current_pitch, deg_to_rad(-5), deg_to_rad(85))
	
	if locked_track_id != -1:
		var optic_azimuth_step = clampf(
			angle_difference(optic_current_angle, optic_target_angle),
			-OPTIC_ROTATION_SPEED * delta,
			OPTIC_ROTATION_SPEED * delta
		)
		optic_current_angle = wrapf(optic_current_angle + optic_azimuth_step, -PI, PI)
		optic_current_pitch = move_toward(
			optic_current_pitch,
			optic_target_pitch,
			OPTIC_ROTATION_SPEED * delta
		)
	else:
		optic_current_angle = lerp_angle(optic_current_angle, optic_target_angle, OPTIC_ROTATION_SPEED * delta)
		optic_current_pitch = move_toward(optic_current_pitch, optic_target_pitch, OPTIC_ROTATION_SPEED * delta)
	
	var az_diff = angle_difference(turret_current_angle, optic_current_angle)
	
	if abs(az_diff) > OPTIC_AZIMUTH_LIMIT:
		var sign_diff = sign(az_diff)
		optic_current_angle = turret_current_angle + (OPTIC_AZIMUTH_LIMIT * sign_diff)
	
	optic_current_pitch = clamp(optic_current_pitch, deg_to_rad(-15), deg_to_rad(85))

func process_search_radar(delta):
	var speed_rad = (get_soc_scan_speed_rpm() * TAU) / 60.0
	search_radar_angle += speed_rad * delta
	if search_radar_angle > TAU: search_radar_angle -= TAU
	_soc_sector_rotation_rad += speed_rad * delta
	var sweep_rad = _soc_full_sweep_rad()
	if _soc_sector_rotation_rad >= sweep_rad:
		_soc_sector_rotation_rad -= sweep_rad
		if !soc_sectors.is_empty():
			soc_current_sector = (soc_current_sector + 1) % soc_sectors.size()

# The СМ antenna has two beams back to back at 30 rpm; the С1 a single beam
# at 60 rpm (360°/s). Either way every azimuth is seen once a second.
func get_soc_beam_count() -> int:
	return 1 if uses_soc_sector_scan() else 2

func get_soc_scan_speed_rpm() -> float:
	return SOC_SINGLE_BEAM_SCAN_SPEED_RPM if get_soc_beam_count() == 1 else SCAN_SPEED_RPM

# Antenna rotation in which the beams together cover the full azimuth.
func _soc_full_sweep_rad() -> float:
	return TAU / get_soc_beam_count()

# Time for the СОЦ to look at every direction once: one full azimuth sweep
# per elevation sector.
func get_soc_revisit_s() -> float:
	return 60.0 / get_soc_scan_speed_rpm() / get_soc_beam_count() * maxf(soc_sectors.size(), 1)

# Fraction of the current sector already swept.
func get_soc_sector_progress() -> float:
	return _soc_sector_rotation_rad / _soc_full_sweep_rad()

func uses_soc_sector_scan() -> bool:
	return GameSettings.selected_complex == "S1"

func _update_soc_sectors() -> void:
	soc_sectors.clear()
	if !uses_soc_sector_scan():
		soc_current_sector = 0
		return
	var low = clampf(get_spz_value("lower_angle_deg"), 0.0, SOC_MAX_ELEVATION_DEG - SOC_MIN_SPAN_DEG)
	var top = rad_to_deg(atan2(get_spz_value("upper_height_m"), missile_flight_config.maximum_distance_m))
	top = clampf(top, low + SOC_MIN_SPAN_DEG, SOC_MAX_ELEVATION_DEG)
	var count = maxi(ceili((top - low) / SOC_SECTOR_MAX_WIDTH_DEG - 0.0001), 1)
	var width = (top - low) / count
	for i in range(count):
		soc_sectors.append([low + width * i, low + width * (i + 1)])
	soc_current_sector = soc_current_sector % count

func _soc_sector_covers(elevation: float) -> bool:
	if soc_sectors.is_empty():
		return true
	var sector: Array = soc_sectors[soc_current_sector]
	return (
		elevation >= deg_to_rad(sector[0]) - SOC_SECTOR_EDGE_MARGIN_RAD
		and elevation <= deg_to_rad(sector[1]) + SOC_SECTOR_EDGE_MARGIN_RAD
	)

# Tracks must survive a full sector cycle without plots.
func _track_decay_time_s() -> float:
	return maxf(TRACK_DECAY_TIME, 2.5 * get_soc_revisit_s())

func _locked_track_coast_limit_s() -> float:
	return maxf(LOCKED_TRACK_COAST_LIMIT_S, get_soc_revisit_s() + 0.5)

func get_spz_value(key: String) -> float:
	return float(SPZ_DEFAULTS[key] if spz_auto else spz_settings[key])

func set_spz_value(key: String, value: float) -> void:
	spz_settings[key] = value
	_update_soc_sectors()

func set_spz_auto(enabled: bool) -> void:
	spz_auto = enabled
	_update_soc_sectors()

# A track the СПЗ limits hide from the operator. The designated target stays.
func is_track_filtered(track_id: int) -> bool:
	if track_id == locked_track_id or !tracks.has(track_id):
		return false
	var state = get_predicted_track_state(track_id)
	if state.is_empty():
		return false
	var relative: Vector3 = state["position"] - pantsir_position
	if relative.y < get_spz_value("lower_height_m"):
		return true
	if asin(clampf(relative.y / maxf(relative.length(), 1.0), -1.0, 1.0)) < deg_to_rad(get_spz_value("lower_angle_deg")):
		return true
	var track: Dictionary = tracks[track_id]
	# Speed is known only once the track has settled.
	if track.get("stable", false) and state["velocity"].length() < get_spz_value("speed_limit_mps"):
		return true
	var rcs_estimate = float(track.get("rcs_estimate", -1.0))
	return rcs_estimate > 0.0 and rcs_estimate < get_spz_value("rcs_threshold_m2")

func process_radar_logic(delta):
	_radar_measurement_accumulator_s += delta
	if _radar_measurement_accumulator_s + 0.000001 < missile_flight_config.radar_measurement_interval_s:
		_remove_expired_tracks()
		return
	var measurement_delta = _radar_measurement_accumulator_s
	# Subtract rather than fmod: an accumulator a hair below the interval passed
	# the tolerance above, and fmod left it there, firing again on the next frame.
	_radar_measurement_accumulator_s = maxf(_radar_measurement_accumulator_s - missile_flight_config.radar_measurement_interval_s, 0.0)
	var scan_time_s = float(targets[0].get("measurement_timestamp", _simulation_time_s)) if !targets.is_empty() else _simulation_time_s

	# Both radars produce plots that carry no target identity; plots reach
	# tracks only through gates. Допоиск dwells only count gate hits; the МРЛС
	# feeds a track once it holds it precisely (АС), and until then the track
	# runs on coarse СОЦ plots.
	if sector_radar_on:
		var mrls_measurements = _associate_mrls_plots(_generate_mrls_plots())
		for track_id in mrls_measurements:
			var plot: Dictionary = mrls_measurements[track_id]
			_apply_track_measurement(
				track_id, plot["position"], plot["velocity"], plot["vr"],
				_mrls_measurement_variance(plot["range"]), true,
				plot.get("source", {}), scan_time_s, measurement_delta
			)
	if search_radar_on:
		var soc_plots = _generate_soc_plots()
		var soc_assignment = _associate_soc_plots(soc_plots, scan_time_s)
		for plot in soc_plots:
			var track_id: int = soc_assignment.get(plot["index"], -1)
			if track_id == -1:
				# A plot no gate claimed starts a new track.
				track_id = _next_track_number
				_next_track_number += 1
			elif is_track_precise(track_id):
				# A precise МРЛС track is not degraded by a coarse search plot.
				continue
			_apply_track_measurement(
				track_id, plot["position"], Vector3.ZERO, plot["vr"],
				_search_measurement_variance(plot["position"]), false,
				plot["source"], scan_time_s, measurement_delta
			)
			if tracks.has(track_id) and plot["rcs"] > 0.0:
				var old_estimate = float(tracks[track_id].get("rcs_estimate", -1.0))
				tracks[track_id]["rcs_estimate"] = plot["rcs"] if old_estimate <= 0.0 else lerpf(old_estimate, plot["rcs"], SOC_RCS_ESTIMATE_SMOOTHING)
	_remove_expired_tracks()

# Kalman update of one track with one plot. "source" is the echo the plot
# came from; it is ground truth kept only for the simulation itself (fuze,
# kill state, signature) and never used to associate plots.
func _apply_track_measurement(
	track_id: int,
	measured_position: Vector3,
	measured_velocity: Vector3,
	measured_radial_velocity: float,
	measurement_variance: float,
	precise: bool,
	source: Dictionary,
	scan_time_s: float,
	measurement_delta: float
) -> void:
	var measurement_timestamp = float(source.get("measurement_timestamp", scan_time_s))
	if tracks.has(track_id) and measurement_timestamp <= float(tracks[track_id]["timestamp"]) + 0.000001:
		return
	var old_track: Dictionary = tracks.get(track_id, {})
	var kalman_filter: KalmanTrack3D
	var hits_count = 1
	if !old_track.is_empty():
		var dt = maxf(measurement_timestamp - float(old_track["timestamp"]), 0.000001)
		kalman_filter = old_track.get("kalman_filter")
		if kalman_filter == null:
			kalman_filter = KalmanTrack3D.new()
			kalman_filter.initialize(
				old_track["position"],
				old_track["velocity"],
				measurement_variance,
				missile_flight_config.kalman_initial_target_velocity_sigma_mps ** 2
			)
		kalman_filter.update(
			measured_position,
			dt,
			measurement_variance,
			missile_flight_config.kalman_target_acceleration_sigma_mps2
		)
		# The МРЛС track holds the target closely enough to use its velocity
		# directly; a position-only filter would trail every turn.
		if precise:
			kalman_filter.velocity = measured_velocity
		hits_count = old_track["hits"] + 1
	else:
		kalman_filter = KalmanTrack3D.new()
		kalman_filter.initialize(
			measured_position,
			measured_velocity,
			measurement_variance,
			missile_flight_config.kalman_initial_target_velocity_sigma_mps ** 2
		)
	tracks[track_id] = {
		"position": kalman_filter.position,
		"measured_position": measured_position,
		"velocity": kalman_filter.velocity,
		"kalman_filter": kalman_filter,
		"kalman_position_variance": kalman_filter.position_variance,
		"kalman_velocity_variance": kalman_filter.velocity_variance,
		"is_threat": source.get("is_threat", old_track.get("is_threat", true)),
		"signature_class": source.get("signature_class", old_track.get("signature_class", "")),
		"killed": source.get("killed", old_track.get("killed", false)),
		"source_id": source.get("id", old_track.get("source_id", -1)),
		"radial_velocity": measured_radial_velocity,
		"rcs_estimate": old_track.get("rcs_estimate", -1.0),
		"timestamp": measurement_timestamp,
		"source_latency_s": maxf(_simulation_time_s - measurement_timestamp, 0.0),
		"id": track_id,
		"hits": hits_count,
		"stable": hits_count >= 3,
	}

# One step of the СОЦ antenna: a coarse plot for every echo the two beams
# cover and detect. Echoes in one СОЦ resolution cell merge.
func _generate_soc_plots() -> Array:
	for uid in _soc_passes.keys():
		if _simulation_time_s - float(_soc_passes[uid]["time_s"]) > 2.0:
			_soc_passes.erase(uid)
	# Arc the beam centre has swept since the previous plot generation. Each
	# target is painted once per pass, when the centre crosses its azimuth;
	# the half-open arcs of successive ticks never overlap.
	var sweep = fposmod(search_radar_angle - _soc_last_plot_angle, TAU)
	if sweep > _soc_full_sweep_rad():
		sweep = 0.0
	var sweep_start = _soc_last_plot_angle
	_soc_last_plot_angle = search_radar_angle
	var echoes = []
	for t_data in targets:
		var polar = _to_radar_polar(t_data["position"], t_data.get("velocity", Vector3.ZERO))
		var in_beam = false
		for beam in range(get_soc_beam_count()):
			var beam_start = sweep_start + _soc_full_sweep_rad() * beam
			if fposmod(polar["az"] - beam_start, TAU) < sweep:
				in_beam = true
		if !in_beam or !_soc_sector_covers(polar["el"]) or !_soc_detects(t_data):
			continue
		polar["rcs"] = float(t_data.get("rcs_m2", 0.0))
		polar["source"] = t_data
		polar["count"] = 1
		echoes.append(polar)
	var plots = _merge_echoes(echoes, SOC_RESOLUTION_AZIMUTH_RAD, SOC_RESOLUTION_ELEVATION_RAD, SOC_RESOLUTION_RANGE_M, SOC_RESOLUTION_VELOCITY_MPS)
	for i in range(plots.size()):
		var plot: Dictionary = plots[i]
		plot["index"] = i
		plot["az"] += _measurement_rng.randfn(0.0, SEARCH_AZIMUTH_SIGMA_RAD)
		plot["el"] += _measurement_rng.randfn(0.0, SEARCH_ELEVATION_SIGMA_RAD)
		plot["range"] += _measurement_rng.randfn(0.0, SEARCH_RANGE_SIGMA_M)
		plot["vr"] += _measurement_rng.randfn(0.0, SEARCH_RADIAL_VELOCITY_SIGMA_MPS)
		plot["position"] = _from_radar_polar(plot["az"], plot["el"], plot["range"])
		if plot["rcs"] > 0.0:
			plot["rcs"] *= pow(10.0, _measurement_rng.randfn(0.0, SOC_RCS_ESTIMATE_SIGMA_DECADES))
	return plots

# Echoes inside one resolution cell (angle, range and radial velocity at
# once) cannot be told apart and become one plot at their centroid. The
# first echo stays the plot's ground-truth source.
func _merge_echoes(echoes: Array, azimuth_cell: float, elevation_cell: float, range_cell: float, velocity_cell: float) -> Array:
	var plots = []
	for echo in echoes:
		var merged = false
		for plot in plots:
			if (
				absf(angle_difference(plot["az"], echo["az"])) < azimuth_cell
				and absf(plot["el"] - echo["el"]) < elevation_cell
				and absf(plot["range"] - echo["range"]) < range_cell
				and absf(plot["vr"] - echo["vr"]) < velocity_cell
			):
				var n = float(plot["count"])
				plot["az"] += angle_difference(plot["az"], echo["az"]) / (n + 1.0)
				plot["el"] = (plot["el"] * n + echo["el"]) / (n + 1.0)
				plot["range"] = (plot["range"] * n + echo["range"]) / (n + 1.0)
				plot["vr"] = (plot["vr"] * n + echo["vr"]) / (n + 1.0)
				if echo.has("velocity"):
					plot["velocity"] = (plot["velocity"] * n + echo["velocity"]) / (n + 1.0)
				plot["count"] = n + 1.0
				merged = true
				break
		if !merged:
			plots.append(echo)
	return plots

# Angle the track's prediction may be off after `age` seconds: 3σ of the
# filter's velocity error over that time, seen at the target's range, up to
# `limit`. Gates must stay small: every extra resolution cell is another
# chance of a false alarm, and salvo rockets fly close behind each other.
func _track_angle_uncertainty_rad(track: Dictionary, age: float, slant_range: float, limit: float) -> float:
	var velocity_sigma = sqrt(maxf(float(track.get("kalman_velocity_variance", 0.0)), 0.0))
	return minf(3.0 * velocity_sigma * age / maxf(slant_range, 1.0), limit)

# Matches СОЦ plots to tracks, nearest pairs first. A track seen once has no
# velocity yet, so its gate is everything the fastest target could reach
# since that plot; older tracks use the filter's prediction. Precise tracks
# take part too so their own СОЦ echoes do not start duplicate tracks.
# Returns plot index -> track id.
func _associate_soc_plots(plots: Array, scan_time_s: float) -> Dictionary:
	var candidates = []
	for track_id in tracks:
		var predicted = get_predicted_track_state(track_id, scan_time_s)
		if predicted.is_empty():
			continue
		var track: Dictionary = tracks[track_id]
		var age = float(predicted["measurement_age_s"])
		var center = _to_radar_polar(predicted["position"], predicted["velocity"])
		center["vr"] = float(track.get("radial_velocity", center["vr"]))
		var precise = is_track_precise(track_id)
		var initiation = int(track.get("hits", 0)) < 2 and !precise
		var azimuth_gate = SOC_GATE_AZIMUTH_RAD
		var elevation_gate = SOC_GATE_ELEVATION_RAD
		if !precise:
			# A young СОЦ track has a poor velocity estimate (plots off by hundreds
			# of metres), so its range is carried by the measured radial velocity,
			# and the angle gates grow with the filter's velocity uncertainty.
			center["range"] = _to_radar_polar(track["measured_position"], Vector3.ZERO)["range"] + center["vr"] * age
			var angle_growth = _track_angle_uncertainty_rad(track, age, center["range"], SOC_GATE_MAX_ANGLE_GROWTH_RAD)
			azimuth_gate += angle_growth
			elevation_gate += angle_growth
		for plot in plots:
			var d_vr = (plot["vr"] - center["vr"]) / SOC_GATE_RADIAL_VELOCITY_MPS
			var distance: float
			if initiation:
				# Both plots carry the СОЦ errors (about 1° in elevation, hundreds
				# of metres at long range), so the gate covers 3σ of their difference.
				var plot_error_m = 3.0 * sqrt(2.0 * _search_measurement_variance(plot["position"]))
				var reach = maxf(SOC_INITIATION_GATE_M, plot_error_m) + SOC_INITIATION_MAX_SPEED_MPS * age
				var d_position = plot["position"].distance_to(track["measured_position"]) / reach
				if d_position > 1.0 or absf(d_vr) > 1.0:
					continue
				distance = d_position * d_position + d_vr * d_vr
			else:
				var d_az = angle_difference(center["az"], plot["az"]) / azimuth_gate
				var d_el = (plot["el"] - center["el"]) / elevation_gate
				var d_range = (plot["range"] - center["range"]) / (SOC_GATE_RANGE_M + SOC_GATE_RANGE_GROWTH_MPS * age)
				if absf(d_az) > 1.0 or absf(d_el) > 1.0 or absf(d_range) > 1.0 or absf(d_vr) > 1.0:
					continue
				distance = d_az * d_az + d_el * d_el + d_range * d_range + d_vr * d_vr
			candidates.append({"distance": distance, "track_id": track_id, "plot_index": plot["index"]})

	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])
	var assignment = {}
	var used_tracks = {}
	for candidate in candidates:
		if assignment.has(candidate["plot_index"]) or used_tracks.has(candidate["track_id"]):
			continue
		assignment[candidate["plot_index"]] = candidate["track_id"]
		used_tracks[candidate["track_id"]] = true
	return assignment

func _remove_expired_tracks() -> void:
	var ids_to_remove = []
	for id in tracks:
		if _simulation_time_s - tracks[id]["timestamp"] > _track_decay_time_s():
			ids_to_remove.append(id)
	for id in ids_to_remove:
		tracks.erase(id)
		_target_classifications.erase(id)

func _measure_position(state_key: String, real_position: Vector3, update_delta: float) -> Vector3:
	var slant_range = pantsir_position.distance_to(real_position)
	var rms_error = slant_range * missile_flight_config.position_error_fraction
	var component_sigma = rms_error / sqrt(3.0)
	var old_noise: Vector3 = _measurement_noise_states.get(state_key, Vector3.ZERO)
	var correlation = exp(-update_delta / maxf(missile_flight_config.noise_correlation_time_s, 0.01))
	var innovation_sigma = component_sigma * sqrt(maxf(1.0 - correlation * correlation, 0.0))
	var innovation = Vector3(
		_measurement_rng.randfn(0.0, innovation_sigma),
		_measurement_rng.randfn(0.0, innovation_sigma),
		_measurement_rng.randfn(0.0, innovation_sigma)
	)
	var noise = old_noise * correlation + innovation
	noise = noise.limit_length(rms_error * 3.0)
	_measurement_noise_states[state_key] = noise
	return real_position + noise

# Search radar (СОЦ) plot: independent errors in azimuth, elevation and range.
# Its elevation is much coarser than the МРЛС, so a target designated from it
# is generally off the visor centre until the МРЛС takes it.
func _measure_search_position(real_position: Vector3) -> Vector3:
	var relative = real_position - pantsir_position
	var slant_range = maxf(relative.length(), 1.0)
	var azimuth = atan2(relative.x, -relative.z) + _measurement_rng.randfn(0.0, SEARCH_AZIMUTH_SIGMA_RAD)
	var horizontal = Vector2(relative.x, relative.z).length()
	var elevation = atan2(relative.y, horizontal) + _measurement_rng.randfn(0.0, SEARCH_ELEVATION_SIGMA_RAD)
	var measured_range = slant_range + _measurement_rng.randfn(0.0, SEARCH_RANGE_SIGMA_M)
	return pantsir_position + Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		-cos(azimuth) * cos(elevation)
	) * measured_range

func _search_measurement_variance(measured_position: Vector3) -> float:
	# The filter is isotropic, so use the largest of the three error components.
	var slant_range = pantsir_position.distance_to(measured_position)
	var angular_sigma = slant_range * maxf(SEARCH_AZIMUTH_SIGMA_RAD, SEARCH_ELEVATION_SIGMA_RAD)
	var sigma = maxf(angular_sigma, SEARCH_RANGE_SIGMA_M)
	return sigma * sigma

func _measurement_variance_for_position(measured_position: Vector3) -> float:
	var measured_range = pantsir_position.distance_to(measured_position)
	var rms_error = measured_range * missile_flight_config.position_error_fraction
	var component_variance = rms_error * rms_error / 3.0
	return maxf(component_variance * missile_flight_config.kalman_measurement_variance_scale, 0.000001)

func reset_measurement_noise(seed: int = MEASUREMENT_SEED) -> void:
	_measurement_rng.seed = seed
	_measurement_noise_states.clear()

func process_missile_guidance(delta):
	for i in range(4):
		var channel = guidance_channels[i]
		if channel == null: continue
		
		var missile = channel["missile"]
		var tid: int = channel["target_id"]
		if !is_instance_valid(missile) or !missile.is_active:
			_last_missile_end_s[tid] = _simulation_time_s
			guidance_channels[i] = null
			continue

		# П-РЛ: no commands until the МРЛС has found the missile; meanwhile the
		# onboard autopilot holds the launch path straight, cancelling gravity,
		# instead of letting it sag. The МРЛС tries to take the missile every
		# MISSILE_CAPTURE_RETRY_S; past the deadline the capture has failed (срыв)
		# and the missile flies on uncontrolled. The capture measurement restarts
		# the missile filter, so the boost phase it missed does not leave the
		# filter lagging.
		if !channel.get("missile_captured", true):
			missile.update_guidance_acceleration(Vector3.ZERO, channel["guidance_mode"])
			if _simulation_time_s < float(channel["capture_time_s"]):
				continue
			if !_try_capture_missile(channel, missile):
				if _simulation_time_s - float(channel["launch_time_s"]) >= MISSILE_CAPTURE_DEADLINE_S:
					missile.clear_guidance_command()
					_last_missile_end_s[tid] = _simulation_time_s
					guidance_channels[i] = null
				else:
					channel["capture_time_s"] = _simulation_time_s + MISSILE_CAPTURE_RETRY_S
				continue

		var track_available = tracks.has(tid) and _simulation_time_s - tracks[tid]["timestamp"] <= TARGET_TRACK_STALE_TIME_S
		if !track_available:
			_process_lost_guidance_channel(i, channel, missile, delta)
			continue

		channel["loss_elapsed_s"] = 0.0
		var target_state = get_predicted_track_state(tid)
		if target_state.is_empty():
			_process_lost_guidance_channel(i, channel, missile, delta)
			continue
		var target_position: Vector3 = target_state["position"]
		var target_velocity: Vector3 = target_state["velocity"]
		if !missile.has_fuze_target():
			var target_node = get_track_target_node(tid)
			if target_node:
				missile.set_fuze_target(target_node)
		_update_missile_measurement(channel, missile)
		var missile_position: Vector3 = channel["missile_position"]
		var missile_velocity: Vector3 = channel["missile_velocity"]
		var missile_filter: KalmanTrack3D = channel.get("missile_filter")
		if missile_filter != null:
			var missile_prediction_time = maxf(_simulation_time_s - channel["missile_measurement_timestamp"], 0.0)
			missile_position = missile_filter.predicted_position(missile_prediction_time)
			missile_velocity = missile_filter.velocity
		if _should_command_detonate(missile, missile_position, missile_velocity, target_position, target_velocity, delta):
			missile.command_detonate()
			continue
		var origin = pantsir_position + launcher_offset

		var raw_los_rate = MissileGuidance.line_of_sight_rate(origin, target_position, target_velocity)
		var mode_blend = 1.0 - exp(-delta / maxf(missile_flight_config.mode_filter_time_constant_s, 0.01))
		channel["filtered_los_rate"] = lerpf(channel["filtered_los_rate"], raw_los_rate, mode_blend)
		_update_channel_guidance_mode(channel)

		var command = Vector3.ZERO
		if channel["guidance_mode"] == GUIDANCE_PS:
			command = MissileGuidance.half_straightening_acceleration(
				missile_position,
				missile_velocity,
				target_position,
				target_velocity,
				missile_flight_config.half_straightening_time_constant_s
			)
		else:
			var range_to_target = missile_position.distance_to(target_position)
			var loft = MissileGuidance.smooth_loft_height(
				range_to_target,
				missile_flight_config.maximum_loft_height_m,
				missile_flight_config.loft_fade_range_m
			)
			command = MissileGuidance.three_point_acceleration(
				origin,
				missile_position,
				missile_velocity,
				target_position,
				target_velocity,
				loft,
				missile_flight_config.three_point_position_gain_s2,
				missile_flight_config.three_point_velocity_gain_s
			)
		channel["last_command"] = command
		missile.update_guidance_acceleration(command, channel["guidance_mode"])
		guidance_channels[i] = channel

# Command detonation (95Я6М): judged only from the complex's own missile and
# target tracks. Fires once the estimated miss distance is inside the
# detonation range, or when the closest approach falls within this tick and
# would be inside it.
func _should_command_detonate(missile: PantsirMissile, missile_position: Vector3, missile_velocity: Vector3, target_position: Vector3, target_velocity: Vector3, delta: float) -> bool:
	var config: MissileFlightConfig = missile.flight_config
	if !config.uses_command_detonation():
		return false
	var offset = target_position - missile_position
	if offset.length() <= config.command_detonation_range_m:
		return true
	var closing_velocity = target_velocity - missile_velocity
	var closing_speed_sq = closing_velocity.length_squared()
	if closing_speed_sq <= 0.000001:
		return false
	var time_to_closest = -offset.dot(closing_velocity) / closing_speed_sq
	if time_to_closest < 0.0 or time_to_closest > delta:
		return false
	return (offset + closing_velocity * time_to_closest).length() <= config.command_detonation_range_m

# One capture attempt. The missile must be inside the МРЛС sector.
func _try_capture_missile(channel: Dictionary, missile: PantsirMissile) -> bool:
	var polar = _to_radar_polar(missile.global_position, Vector3.ZERO)
	if !sector_radar_on or absf(angle_difference(turret_current_angle, polar["az"])) >= SECTOR_WIDTH_RAD:
		return false
	if _detection_rng.randf() >= MISSILE_CAPTURE_PROBABILITY:
		return false
	_capture_missile(channel, missile)
	return true

# The missile channel measures the missile with the МРЛС's own errors.
func _measure_missile_position(real_position: Vector3) -> Vector3:
	var polar = _to_radar_polar(real_position, Vector3.ZERO)
	return _from_radar_polar(
		polar["az"] + _measurement_rng.randfn(0.0, mrls_angle_sigma_rad),
		polar["el"] + _measurement_rng.randfn(0.0, mrls_angle_sigma_rad),
		polar["range"] + _measurement_rng.randfn(0.0, mrls_range_sigma_m)
	)

func _capture_missile(channel: Dictionary, missile: PantsirMissile) -> void:
	var measured_position = _measure_missile_position(missile.global_position)
	var missile_filter = KalmanTrack3D.new()
	missile_filter.initialize(
		measured_position,
		missile.velocity,
		_mrls_measurement_variance(pantsir_position.distance_to(measured_position)),
		missile_flight_config.kalman_initial_missile_velocity_sigma_mps ** 2
	)
	channel["missile_filter"] = missile_filter
	channel["missile_position"] = measured_position
	channel["missile_measured_position"] = measured_position
	channel["missile_velocity"] = missile.velocity
	channel["missile_position_variance"] = missile_filter.position_variance
	channel["missile_velocity_variance"] = missile_filter.velocity_variance
	channel["missile_measurement_timestamp"] = _simulation_time_s
	channel["missile_captured"] = true

func _update_missile_measurement(channel: Dictionary, missile: PantsirMissile) -> void:
	var elapsed = _simulation_time_s - channel["missile_measurement_timestamp"]
	if elapsed + 0.000001 < missile_flight_config.radar_measurement_interval_s:
		return
	var measured_position = _measure_missile_position(missile.global_position)
	var measurement_variance = _mrls_measurement_variance(pantsir_position.distance_to(measured_position))
	var kalman_filter: KalmanTrack3D = channel.get("missile_filter")
	if kalman_filter == null:
		kalman_filter = KalmanTrack3D.new()
		kalman_filter.initialize(
			channel["missile_position"],
			channel["missile_velocity"],
			measurement_variance,
			missile_flight_config.kalman_initial_missile_velocity_sigma_mps ** 2
		)
	kalman_filter.update(
		measured_position,
		elapsed,
		measurement_variance,
		missile_flight_config.kalman_missile_acceleration_sigma_mps2
	)
	channel["missile_filter"] = kalman_filter
	channel["missile_position"] = kalman_filter.position
	channel["missile_velocity"] = kalman_filter.velocity
	channel["missile_measured_position"] = measured_position
	channel["missile_position_variance"] = kalman_filter.position_variance
	channel["missile_velocity_variance"] = kalman_filter.velocity_variance
	channel["missile_measurement_timestamp"] = _simulation_time_s

func _update_channel_guidance_mode(channel: Dictionary) -> void:
	var rate: float = channel["filtered_los_rate"]
	channel["guidance_mode"] = MissileGuidance.select_mode_with_hysteresis(
		channel["guidance_mode"],
		rate,
		missile_flight_config.mode_switch_to_ps_rad_s,
		missile_flight_config.mode_switch_to_tt_rad_s
	)

func _process_lost_guidance_channel(index: int, channel: Dictionary, missile: PantsirMissile, delta: float) -> void:
	channel["loss_elapsed_s"] += delta
	var loss_time: float = channel["loss_elapsed_s"]
	if loss_time <= missile_flight_config.track_loss_grace_period_s:
		var decay_time = maxf(loss_time - LOST_COMMAND_HOLD_TIME_S, 0.0)
		var factor = exp(-decay_time / maxf(missile_flight_config.command_loss_decay_time_s, 0.01))
		missile.update_guidance_acceleration(channel["last_command"] * factor, channel["guidance_mode"])
		guidance_channels[index] = channel
		return
	missile.clear_guidance_command()
	guidance_channels[index] = null

func get_guidance_mode_for_target(target_id: int) -> String:
	for channel in guidance_channels:
		if channel != null and channel["target_id"] == target_id and is_instance_valid(channel["missile"]):
			return channel["guidance_mode"]
	var rate = _target_los_rate(target_id)
	if rate >= missile_flight_config.mode_switch_to_ps_rad_s:
		return GUIDANCE_PS
	return GUIDANCE_TT

func _target_los_rate(target_id: int) -> float:
	if !tracks.has(target_id):
		return 0.0
	var target_state = get_predicted_track_state(target_id)
	if target_state.is_empty():
		return 0.0
	return MissileGuidance.line_of_sight_rate(
		pantsir_position + launcher_offset,
		target_state["position"],
		target_state["velocity"]
	)

func process_gun_fire(delta):
	if gun_fire_timer > 0:
		gun_fire_timer -= delta

func angle_difference(angle1, angle2):
	var diff = angle2 - angle1
	return wrapf(diff, -PI, PI)

func scan_radar_power_switch(): search_radar_on = !search_radar_on
func soc_switch():
	sector_radar_on = !sector_radar_on
	if !sector_radar_on:
		locked_track_id = -1
		_reset_mrls_target_channel()
func lock_on_target(track_id: int):
	# Допоиск state is per target, so a target already tracked precisely in the
	# sector goes straight to АС when it is designated.
	if tracks.has(track_id):
		locked_track_id = track_id
		sector_radar_on = true
		_assign_target_channel(track_id)
func toggle_master_power():
	master_power_on = !master_power_on
	master_power_elapsed = 0.0
	complex_ready = false
	if !master_power_on:
		search_radar_on = false
		sector_radar_on = false
		locked_track_id = -1
		_reset_mrls_target_channel()
		_cancel_pending_missile_launch()
	else:
		reset_measurement_noise()
		_radar_measurement_accumulator_s = 0.0
func reset_simulation() -> void:
	if master_power_on:
		toggle_master_power()
	targets.clear()
	tracks.clear()
	_target_classifications.clear()
	_last_missile_end_s.clear()
	_soc_passes.clear()
	_next_track_number = 1
	_reset_mrls_target_channel()
	_measurement_noise_states.clear()
	guidance_channels = [null, null, null, null]
	target_channels = [-1, -1, -1, -1]
	_simulation_time_s = 0.0
	_radar_measurement_accumulator_s = 0.0
	search_radar_angle = 0.0
	turret_current_angle = 0.0
	turret_target_angle = 0.0
	turret_current_pitch = 0.0
	turret_target_pitch = 0.0
	optic_current_angle = 0.0
	optic_target_angle = 0.0
	optic_current_pitch = 0.0
	optic_target_pitch = 0.0
	manual_zoom_factor = OPTIC_ZOOM_LEVELS[0]
	selected_weapon = "MISSILES"
	MAX_RANGE = 30000
	gun_fire_timer = 0.0
	gun_ammo_by_barrel = [300, 300, 300, 300]
	ammo_guns = 1200
	next_gun_barrel = 0
	missile_cooldown_timer = 0.0
	for i in range(missile_tubes_loaded.size()):
		missile_tubes_loaded[i] = true
	ammo_missiles = missile_tubes_loaded.size()
	_next_launcher_arm_cursor = 0
	_selected_missile_tube_index = -1
	_select_next_missile_tube()
	auto_fire_on = false
	_auto_fire_burst_left_s = 0.0
	_auto_fire_pause_left_s = 0.0
	last_missile_launch_time_s = -INF
	sound_play_required = false
	_detection_rng.seed = DETECTION_SEED
	reload_time_left_s = 0.0
	_pending_loadout = {}
	soc_current_sector = 0
	_soc_sector_rotation_rad = 0.0
	_soc_last_plot_angle = 0.0

func select_weapon_guns(): selected_weapon = "GUNS"
func select_weapon_missiles(): selected_weapon = "MISSILES"

func zoom_inc():
	for zoom_level in OPTIC_ZOOM_LEVELS:
		if zoom_level > manual_zoom_factor + 0.001:
			manual_zoom_factor = zoom_level
			return
	manual_zoom_factor = OPTIC_ZOOM_LEVELS[-1]

func zoom_dec():
	for index in range(OPTIC_ZOOM_LEVELS.size() - 1, -1, -1):
		var zoom_level = OPTIC_ZOOM_LEVELS[index]
		if zoom_level < manual_zoom_factor - 0.001:
			manual_zoom_factor = zoom_level
			return
	manual_zoom_factor = OPTIC_ZOOM_LEVELS[0]

func fire_active_weapon():
	if !master_power_on: return
	
	if selected_weapon == "MISSILES":
		fire_missile_logic()
	elif selected_weapon == "GUNS":
		fire_guns_logic()

func fire_missile_logic():
	if is_reloading(): return
	if missile_cooldown_timer > 0: return
	if ammo_missiles <= 0: return
	if !_pending_missile_launch.is_empty(): return
	if locked_track_id == -1 or !sector_radar_on: return
	if !tracks.has(locked_track_id): return
	# Commands need a stable МРЛС track; no launch while still in допоиск.
	if mrls_mode != MRLS_MODE_TRACK: return

	var target_state = get_predicted_track_state(locked_track_id)
	if target_state.is_empty(): return
	var t_pos: Vector3 = target_state["position"]
	var intercept_range = calculate_missile_intercept_range(t_pos, target_state["velocity"])
	if intercept_range < 0.0 or intercept_range > missile_flight_config.maximum_distance_m: return
	var rel = t_pos - pantsir_position
	var t_az = atan2(rel.x, -rel.z)
	var diff = abs(angle_difference(turret_current_angle, t_az))
	if diff > SECTOR_WIDTH_RAD: return
	
	var free_channel_idx = -1
	for i in range(4):
		if guidance_channels[i] == null:
			free_channel_idx = i
			break
	if free_channel_idx == -1: return

	if _selected_missile_tube_index < 0 or !_tube_holds(_selected_missile_tube_index, selected_missile_type):
		_select_next_missile_tube()
	if _selected_missile_tube_index < 0: return

	var launcher_arm = get_launcher_arm_for_tube(_selected_missile_tube_index + 1)
	_pending_missile_launch = {
		"tube_index": _selected_missile_tube_index,
		"launcher_arm": launcher_arm,
		"channel_index": free_channel_idx,
		"target_id": locked_track_id,
		"missile_type": selected_missile_type,
	}
	_missile_arm_raise_timer = MISSILE_ARM_RAISE_TIME
	# Count preparation as part of the existing two-second launch interval.
	missile_cooldown_timer = MISSILE_COOLDOWN_TIME

func process_pending_missile_launch(delta: float) -> void:
	if _pending_missile_launch.is_empty():
		return
	_missile_arm_raise_timer = maxf(_missile_arm_raise_timer - delta, 0.0)
	if _missile_arm_raise_timer > 0.0:
		return

	var tube_index: int = _pending_missile_launch["tube_index"]
	var launcher_arm: int = _pending_missile_launch["launcher_arm"]
	var channel_index: int = _pending_missile_launch["channel_index"]
	var target_id: int = _pending_missile_launch["target_id"]
	var missile_type: String = _pending_missile_launch["missile_type"]
	_pending_missile_launch = {}

	if tube_index < 0 or tube_index >= missile_tubes_loaded.size() or !_tube_holds(tube_index, missile_type):
		_select_next_missile_tube()
		return
	if channel_index < 0 or channel_index >= guidance_channels.size() or guidance_channels[channel_index] != null:
		_select_next_missile_tube()
		return

	spawn_projectile(missile_scene, true, channel_index, launcher_arm, target_id, missile_type)
	last_missile_launch_time_s = _simulation_time_s
	# A ТКБ-1055 container empties one missile at a time.
	missile_tube_counts[tube_index] -= 1
	if missile_tube_counts[tube_index] <= 0:
		missile_tube_counts[tube_index] = 0
		missile_tube_types[tube_index] = ""
		missile_tubes_loaded[tube_index] = false
	ammo_missiles = get_missile_count(selected_missile_type)
	sound_play_required = true
	_selected_missile_tube_index = -1
	_select_next_missile_tube()

# Missile types the selected complex can carry.
func get_missile_types() -> Array:
	return MISSILE_TYPES_BY_COMPLEX.get(GameSettings.selected_complex, MISSILE_TYPES_BY_COMPLEX["SM"])

func get_missiles_per_tube(missile_type: String) -> int:
	return MISSILES_PER_TUBE.get(missile_type, 1)

# Name for menus: a ТКБ-1055 container is shown as four missiles.
func get_tube_load_label(missile_type: String) -> String:
	var count = get_missiles_per_tube(missile_type)
	return missile_type if count == 1 else "%d× %s" % [count, missile_type]

func get_missile_count(missile_type: String) -> int:
	var count = 0
	for i in range(missile_tube_types.size()):
		if missile_tube_types[i] == missile_type:
			count += missile_tube_counts[i]
	return count

func get_total_missile_count() -> int:
	var count = 0
	for tube_count in missile_tube_counts:
		count += tube_count
	return count

func get_missile_tube_type(tube_number: int) -> String:
	var tube_index = tube_number - 1
	return missile_tube_types[tube_index] if tube_index >= 0 and tube_index < missile_tube_types.size() else ""

func get_missile_tube_count(tube_number: int) -> int:
	var tube_index = tube_number - 1
	return missile_tube_counts[tube_index] if tube_index >= 0 and tube_index < missile_tube_counts.size() else 0

func _tube_holds(tube_index: int, missile_type: String) -> bool:
	return (
		tube_index >= 0 and tube_index < missile_tube_types.size()
		and missile_tube_types[tube_index] == missile_type
		and missile_tube_counts[tube_index] > 0
	)

# Selector (ВЫБОР ЗУР): the type to fire next. Its flight model drives the
# launch zone, launch permission and the launcher lead. Not changed while a
# launch is being prepared.
func select_missile_type(missile_type: String) -> void:
	if is_missile_launch_preparing() or !MISSILE_FLIGHT_CONFIGS.has(missile_type):
		return
	selected_missile_type = missile_type
	missile_flight_config = MISSILE_FLIGHT_CONFIGS[missile_type]
	ammo_missiles = get_missile_count(missile_type)
	_selected_missile_tube_index = -1
	_select_next_missile_tube()

func select_next_missile_type() -> void:
	var types = get_missile_types()
	var index = types.find(selected_missile_type)
	select_missile_type(types[(index + 1) % types.size()])

# Full standard loadout for the selected complex; also selects its first
# missile type and the СОЦ elevation scan.
func load_default_loadout() -> void:
	selected_missile_type = get_missile_types()[0]
	missile_flight_config = MISSILE_FLIGHT_CONFIGS[selected_missile_type]
	_update_soc_sectors()
	var tube_types: Array[String] = []
	for i in range(missile_tubes_loaded.size()):
		tube_types.append(get_missile_types()[0])
	var belt_types: Array[String] = []
	for gun in range(gun_ammo_by_barrel.size() / 2):
		belt_types.append(GUN_BELT_TYPES[0])
	apply_loadout(tube_types, belt_types)

# Loads or unloads tubes and gun belts. Refused while a launch is under way.
func apply_loadout(tube_types: Array, belt_types: Array) -> bool:
	if is_missile_launch_preparing():
		return false
	missile_tube_types.clear()
	missile_tube_counts.clear()
	for i in range(missile_tubes_loaded.size()):
		var tube_type: String = tube_types[i] if i < tube_types.size() else ""
		missile_tube_types.append(tube_type)
		missile_tube_counts.append(0 if tube_type.is_empty() else get_missiles_per_tube(tube_type))
		missile_tubes_loaded[i] = !tube_type.is_empty()
	ammo_missiles = get_missile_count(selected_missile_type)
	_selected_missile_tube_index = -1
	_select_next_missile_tube()
	gun_belt_types.clear()
	ammo_guns = 0
	for gun in range(gun_ammo_by_barrel.size() / 2):
		var belt_type: String = belt_types[gun] if gun < belt_types.size() else ""
		gun_belt_types.append(belt_type)
		var rounds = GUN_ROUNDS_PER_BARREL if !belt_type.is_empty() else 0
		gun_ammo_by_barrel[gun * 2] = rounds
		gun_ammo_by_barrel[gun * 2 + 1] = rounds
		ammo_guns += rounds * 2
	return true

func request_reload(tube_types: Array, belt_types: Array) -> bool:
	if is_reloading() or is_missile_launch_preparing():
		return false
	_pending_loadout = {"tubes": tube_types.duplicate(), "belts": belt_types.duplicate()}
	reload_time_left_s = RELOAD_TIME_S
	return true

func is_reloading() -> bool:
	return reload_time_left_s > 0.0

func _process_reload(delta: float) -> void:
	if !is_reloading():
		return
	reload_time_left_s -= delta
	if reload_time_left_s <= 0.0:
		reload_time_left_s = 0.0
		apply_loadout(_pending_loadout["tubes"], _pending_loadout["belts"])
		_pending_loadout = {}

# Mass of one loaded tube of this type.
func get_tube_load_mass_kg(missile_type: String) -> float:
	if missile_type.is_empty():
		return 0.0
	if TUBE_LOAD_MASS_KG.has(missile_type):
		return TUBE_LOAD_MASS_KG[missile_type]
	return MISSILE_FLIGHT_CONFIGS[missile_type].launch_mass_kg * get_missiles_per_tube(missile_type)

func _cancel_pending_missile_launch() -> void:
	_pending_missile_launch = {}
	_missile_arm_raise_timer = 0.0

# Missiles of the selected type left on one launcher arm.
func _count_loaded_tubes_on_arm(launcher_arm: int) -> int:
	if launcher_arm < 0 or launcher_arm >= LAUNCHER_ARM_TUBES.size():
		return 0
	var loaded_count = 0
	for tube_index in LAUNCHER_ARM_TUBES[launcher_arm]:
		if _tube_holds(tube_index, selected_missile_type):
			loaded_count += missile_tube_counts[tube_index]
	return loaded_count

func _select_next_missile_tube() -> void:
	if !_pending_missile_launch.is_empty():
		return
	var maximum_remaining = 0
	for launcher_arm in range(LAUNCHER_ARM_TUBES.size()):
		maximum_remaining = maxi(maximum_remaining, _count_loaded_tubes_on_arm(launcher_arm))
	if maximum_remaining == 0:
		_selected_missile_tube_index = -1
		return

	for offset in range(LAUNCHER_ARM_TUBES.size()):
		var launcher_arm = (_next_launcher_arm_cursor + offset) % LAUNCHER_ARM_TUBES.size()
		if _count_loaded_tubes_on_arm(launcher_arm) != maximum_remaining:
			continue
		for tube_index in LAUNCHER_ARM_TUBES[launcher_arm]:
			if _tube_holds(tube_index, selected_missile_type):
				_selected_missile_tube_index = tube_index
				_next_launcher_arm_cursor = (launcher_arm + 1) % LAUNCHER_ARM_TUBES.size()
				return

func get_selected_missile_tube_number() -> int:
	return _selected_missile_tube_index + 1 if _selected_missile_tube_index >= 0 else -1

func get_launcher_arm_for_tube(tube_number: int) -> int:
	var tube_index = tube_number - 1
	for launcher_arm in range(LAUNCHER_ARM_TUBES.size()):
		if tube_index in LAUNCHER_ARM_TUBES[launcher_arm]:
			return launcher_arm
	return -1

func get_selected_launcher_arm() -> int:
	return get_launcher_arm_for_tube(get_selected_missile_tube_number())

func is_missile_tube_loaded(tube_number: int) -> bool:
	var tube_index = tube_number - 1
	return tube_index >= 0 and tube_index < missile_tubes_loaded.size() and missile_tubes_loaded[tube_index]

func is_missile_launch_preparing() -> bool:
	return !_pending_missile_launch.is_empty()

func is_launcher_arm_raised(launcher_arm: int) -> bool:
	if _pending_missile_launch.is_empty():
		return false
	var selected_arm: int = _pending_missile_launch["launcher_arm"]
	if launcher_arm == selected_arm:
		return true
	# An outer arm is mechanically raised together with the inner arm on its side.
	return (selected_arm == 0 and launcher_arm == 1) or (selected_arm == 3 and launcher_arm == 2)

func fire_guns_logic():
	if is_reloading(): return
	if gun_fire_timer > 0: return
	if ammo_guns <= 0: return

	var firing_barrel = -1
	for offset in range(gun_ammo_by_barrel.size()):
		var barrel_index = (next_gun_barrel + offset) % gun_ammo_by_barrel.size()
		if gun_ammo_by_barrel[barrel_index] > 0:
			firing_barrel = barrel_index
			break
	if firing_barrel == -1: return

	gun_fire_timer = GUN_RATE_OF_FIRE
	spawn_bullet()
	gun_ammo_by_barrel[firing_barrel] -= 1
	next_gun_barrel = (firing_barrel + 1) % gun_ammo_by_barrel.size()
	ammo_guns = 0
	for barrel_ammo in gun_ammo_by_barrel:
		ammo_guns += barrel_ammo

func spawn_projectile(scene, is_missile, channel_idx = -1, launcher_arm: int = -1, target_id: int = -1, missile_type: String = ""):
	var world = get_tree().current_scene.find_child("SimulationCore")
	if !world: world = get_tree().root

	var inst = scene.instantiate()
	if is_missile:
		inst.flight_config = MISSILE_FLIGHT_CONFIGS.get(missile_type, missile_flight_config)
	inst.rotation.y = -turret_current_angle
	inst.rotation.x = turret_current_pitch
	world.add_child(inst)
	
	var launch_offset = Vector3(0, 3.5, 0)
	if is_missile and launcher_arm >= 0 and launcher_arm < LAUNCHER_ARM_LATERAL_OFFSETS_M.size():
		launch_offset.x = LAUNCHER_ARM_LATERAL_OFFSETS_M[launcher_arm]
	launch_offset = launch_offset.rotated(Vector3.UP, -turret_current_angle)
	inst.global_position = pantsir_position + launch_offset
	
	if is_missile:
		inst.initialize_launch_state(-inst.global_transform.basis.z)
		var launch_target_id = locked_track_id if target_id < 0 else target_id
		var target_node = get_track_target_node(launch_target_id)
		if target_node:
			inst.set_fuze_target(target_node)
		var measured_missile_position = _measure_missile_position(inst.global_position)
		var missile_filter = KalmanTrack3D.new()
		missile_filter.initialize(
			measured_missile_position,
			inst.velocity,
			_mrls_measurement_variance(pantsir_position.distance_to(measured_missile_position)),
			missile_flight_config.kalman_initial_missile_velocity_sigma_mps ** 2
		)
		var initial_los_rate = _target_los_rate(launch_target_id)
		var initial_mode = get_guidance_mode_for_target(launch_target_id)
		guidance_channels[channel_idx] = {
			"missile": inst,
			"target_id": launch_target_id,
			"guidance_mode": initial_mode,
			"filtered_los_rate": initial_los_rate,
			"last_command": Vector3.ZERO,
			"loss_elapsed_s": 0.0,
			"noise_key": "missile_%s" % inst.get_instance_id(),
			"missile_position": measured_missile_position,
			"missile_measured_position": measured_missile_position,
			"missile_velocity": inst.velocity,
			"missile_filter": missile_filter,
			"missile_position_variance": missile_filter.position_variance,
			"missile_velocity_variance": missile_filter.velocity_variance,
			"missile_measurement_timestamp": _simulation_time_s,
			"launch_time_s": _simulation_time_s,
			"capture_time_s": _simulation_time_s + _detection_rng.randf_range(MISSILE_CAPTURE_MIN_S, MISSILE_CAPTURE_MAX_S),
			"missile_captured": false,
		}

func spawn_bullet():
	var world = get_tree().current_scene.find_child("SimulationCore")
	if !world: world = get_tree().root
	
	var bullet = Node3D.new()
	bullet.set_script(bullet_script) 
	world.add_child(bullet)
	
	var offset = Vector3(randf_range(-0.5, 0.5), GUN_MUZZLE_HEIGHT_M, 0)
	offset = offset.rotated(Vector3.UP, -turret_current_angle)
	
	bullet.global_position = pantsir_position + offset
	
	var spread = 0.002
	var base_rot_y = -turret_current_angle + randf_range(-spread, spread)
	var base_rot_x = turret_current_pitch + randf_range(-spread, spread)
	
	bullet.rotation.y = base_rot_y
	bullet.rotation.x = base_rot_x
	
	bullet.init_bullet(GUN_MUZZLE_VELOCITY)

func spawn_random_target():
	var world = get_tree().current_scene.find_child("World3D")
	if !world: world = get_tree().root
	
	var rand_val = randi() % 2
	var inst = null
	if rand_val == 0:
		inst = scene_drone.instantiate()
	else:
		inst = scene_tomahawk.instantiate()
		
	world.add_child(inst)
	
	var angle = randf() * TAU
	var dist = randf_range(15000, 30000)
	var height = randf_range(100, 3000)
	
	var x = sin(angle) * dist
	var z = cos(angle) * dist
	if "terrain_following" in inst:
		# Cruise missiles come in low, hugging the terrain.
		inst.terrain_following = true
		inst.terrain_clearance_m = randf_range(CRUISE_MISSILE_MIN_CLEARANCE_M, CRUISE_MISSILE_MAX_CLEARANCE_M)
		height = get_ground_height(x, z) + inst.terrain_clearance_m

	inst.global_position = Vector3(x, height, z)
	inst.look_at(Vector3(0, height, 0), Vector3.UP)
	
	if "attack_mode" in inst:
		inst.attack_mode = true
	if "flight_speed" in inst:
		if rand_val == 0:
			inst.flight_speed = randf_range(DRONE_MIN_SPEED_MPS, DRONE_MAX_SPEED_MPS)
		else:
			inst.flight_speed = randf_range(TOMAHAWK_MIN_SPEED_MPS, TOMAHAWK_MAX_SPEED_MPS)

func spawn_himars_salvo():
	var world = get_tree().current_scene.find_child("World3D")
	if !world: world = get_tree().root
	
	var angle = randf() * TAU
	var dist = 40000.0
	var launch_pos = Vector3(sin(angle) * dist, 100, cos(angle) * dist)
	
	var target_pos = pantsir_position
	
	var flight_time = 40.0
	
	_launch_salvo_coroutine(world, launch_pos, target_pos, flight_time)

func _launch_salvo_coroutine(world, start_pos, end_pos, f_time):
	for i in range(6):
		# The salvo may outlive the session when the player leaves to the menu.
		if !is_instance_valid(world) or !world.is_inside_tree():
			return
		var rocket = CharacterBody3D.new()
		rocket.set_script(script_ballistic)
		world.add_child(rocket)
		
		var spread = Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))
		rocket.init_ballistics(start_pos, end_pos + spread, f_time)
		
		await get_tree().create_timer(2.0).timeout
