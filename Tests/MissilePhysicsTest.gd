extends Node

const MissileScript = preload("res://Scripts/PantsirMissile.gd")
const Guidance = preload("res://Scripts/MissileGuidance.gd")
const Kalman = preload("res://Scripts/KalmanTrack3D.gd")
const Config = preload("res://Resources/PantsirMissileFlightConfig.tres")
const PHYSICS_DELTA: float = 1.0 / 200.0

var failures: Array[String] = []

func _ready() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	print("PANTSIR MISSILE HEADLESS TESTS (200 physics ticks/s)")
	_test_launcher_arm_selection()
	_test_render_fps_invariance()
	_test_war_thunder_parameter_mapping()
	_test_flight_profile()
	_test_six_dof_control_response()
	_test_six_dof_guided_intercept()
	_test_launch_elevation_compensation()
	_test_elevated_launch_boost_lead()
	_test_guidance_math()
	_test_missile_intercept_range()
	_test_mode_hysteresis()
	_test_timestamped_track_prediction()
	_test_track_loss_behavior()
	_test_continuous_fuze()
	_test_measurement_noise()
	_test_kalman_noise_suppression()
	if failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("RESULT: FAIL (%d)" % failures.size())
		get_tree().quit(1)

func _new_test_missile() -> PantsirMissile:
	var missile: PantsirMissile = MissileScript.new()
	missile.create_flight_visuals = false
	get_tree().root.add_child(missile)
	missile.set_physics_process(false)
	missile.global_position = Vector3(0.0, 1000.0, 0.0)
	missile.initialize_launch_state(Vector3.FORWARD)
	return missile

func _test_launcher_arm_selection() -> void:
	var saved_tubes = GlobalPantsirSystem.missile_tubes_loaded.duplicate()
	var saved_types = GlobalPantsirSystem.missile_tube_types.duplicate()
	var saved_counts = GlobalPantsirSystem.missile_tube_counts.duplicate()
	var saved_type = GlobalPantsirSystem.selected_missile_type
	var saved_cursor = GlobalPantsirSystem._next_launcher_arm_cursor
	var saved_selection = GlobalPantsirSystem._selected_missile_tube_index
	var saved_pending = GlobalPantsirSystem._pending_missile_launch.duplicate()

	var missile_type = GlobalPantsirSystem.MISSILE_95YA6
	var full_load: Array[String] = []
	full_load.resize(12)
	full_load.fill(missile_type)
	# Guns stay fully loaded, as they are before this test.
	var full_belts: Array[String] = [GlobalPantsirSystem.GUN_BELT_TYPES[0], GlobalPantsirSystem.GUN_BELT_TYPES[0]]
	GlobalPantsirSystem._pending_missile_launch = {}
	GlobalPantsirSystem.select_missile_type(missile_type)
	GlobalPantsirSystem.apply_loadout(full_load, full_belts)
	GlobalPantsirSystem._next_launcher_arm_cursor = 0
	GlobalPantsirSystem._selected_missile_tube_index = -1
	for expected_tube in range(1, 13):
		GlobalPantsirSystem._select_next_missile_tube()
		_assert(
			GlobalPantsirSystem.get_selected_missile_tube_number() == expected_tube,
			"launcher load balancing selected tube %d instead of %d" % [GlobalPantsirSystem.get_selected_missile_tube_number(), expected_tube]
		)
		GlobalPantsirSystem.missile_tube_counts[expected_tube - 1] = 0
		GlobalPantsirSystem.missile_tube_types[expected_tube - 1] = ""
		GlobalPantsirSystem.missile_tubes_loaded[expected_tube - 1] = false
		GlobalPantsirSystem._selected_missile_tube_index = -1

	# A ТКБ-1055 container holds four missiles; only tubes of the selected
	# type are offered.
	var mixed_load: Array[String] = []
	mixed_load.resize(12)
	mixed_load.fill("")
	mixed_load[0] = GlobalPantsirSystem.MISSILE_95YA6M
	mixed_load[5] = GlobalPantsirSystem.MISSILE_TKB_1055
	GlobalPantsirSystem.apply_loadout(mixed_load, full_belts)
	GlobalPantsirSystem.select_missile_type(GlobalPantsirSystem.MISSILE_TKB_1055)
	_assert(GlobalPantsirSystem.get_missile_count(GlobalPantsirSystem.MISSILE_TKB_1055) == 4, "ТКБ-1055 container does not hold four missiles")
	_assert(GlobalPantsirSystem.get_selected_missile_tube_number() == 6, "ТКБ-1055 selection picked tube %d instead of 6" % GlobalPantsirSystem.get_selected_missile_tube_number())
	GlobalPantsirSystem.select_missile_type(GlobalPantsirSystem.MISSILE_95YA6M)
	_assert(GlobalPantsirSystem.get_selected_missile_tube_number() == 1, "95Я6М selection picked tube %d instead of 1" % GlobalPantsirSystem.get_selected_missile_tube_number())

	GlobalPantsirSystem._pending_missile_launch = {"launcher_arm": 0}
	_assert(GlobalPantsirSystem.is_launcher_arm_raised(0), "left outer arm did not rise")
	_assert(GlobalPantsirSystem.is_launcher_arm_raised(1), "left outer arm rose without its inner arm")
	_assert(!GlobalPantsirSystem.is_launcher_arm_raised(2), "opposite inner arm rose with left outer arm")
	GlobalPantsirSystem._pending_missile_launch = {"launcher_arm": 1}
	_assert(GlobalPantsirSystem.is_launcher_arm_raised(1), "left inner arm did not rise independently")
	_assert(!GlobalPantsirSystem.is_launcher_arm_raised(0), "left inner arm incorrectly raised the outer arm")
	GlobalPantsirSystem._pending_missile_launch = {"launcher_arm": 3}
	_assert(GlobalPantsirSystem.is_launcher_arm_raised(2), "right outer arm rose without its inner arm")
	_assert(GlobalPantsirSystem.LAUNCHER_ARM_LATERAL_OFFSETS_M[0] < 0.0, "left launcher offset is not left of the sight")
	_assert(GlobalPantsirSystem.LAUNCHER_ARM_LATERAL_OFFSETS_M[3] > 0.0, "right launcher offset is not right of the sight")

	GlobalPantsirSystem.missile_tubes_loaded.assign(saved_tubes)
	GlobalPantsirSystem.missile_tube_types.assign(saved_types)
	GlobalPantsirSystem.missile_tube_counts.assign(saved_counts)
	GlobalPantsirSystem._pending_missile_launch = {}
	GlobalPantsirSystem.select_missile_type(saved_type)
	GlobalPantsirSystem._next_launcher_arm_cursor = saved_cursor
	GlobalPantsirSystem._selected_missile_tube_index = saved_selection
	GlobalPantsirSystem._pending_missile_launch = saved_pending

func _test_missile_intercept_range() -> void:
	var saved_position = GlobalPantsirSystem.pantsir_position
	GlobalPantsirSystem.pantsir_position = Vector3.ZERO
	var stationary_range = GlobalPantsirSystem.calculate_missile_intercept_range(
		Vector3(0.0, 0.0, -19000.0),
		Vector3.ZERO
	)
	var outbound_range = GlobalPantsirSystem.calculate_missile_intercept_range(
		Vector3(0.0, 0.0, -19000.0),
		Vector3(0.0, 0.0, -200.0)
	)
	GlobalPantsirSystem.pantsir_position = saved_position

	_assert(absf(stationary_range - 19000.0) <= 0.01, "stationary intercept range is incorrect")
	_assert(outbound_range > Config.maximum_distance_m, "outbound target intercept should exceed 20 km")

func _run_grouped_scenario(render_fps: int, duration_s: float) -> Vector3:
	var missile = _new_test_missile()
	var render_accumulator = 0.0
	var completed_steps = 0
	var required_steps = int(round(duration_s / PHYSICS_DELTA))
	while completed_steps < required_steps:
		render_accumulator += 1.0 / float(render_fps)
		while render_accumulator + 0.0000001 >= PHYSICS_DELTA and completed_steps < required_steps:
			missile.update_guidance_acceleration(Vector3.ZERO, "ТТ")
			missile.simulate_physics_step(PHYSICS_DELTA, false)
			render_accumulator -= PHYSICS_DELTA
			completed_steps += 1
	var result = missile.global_position
	missile.free()
	return result

func _test_render_fps_invariance() -> void:
	var positions = {
		30: _run_grouped_scenario(30, 10.0),
		60: _run_grouped_scenario(60, 10.0),
		144: _run_grouped_scenario(144, 10.0),
	}
	var max_difference = maxf(
		positions[30].distance_to(positions[60]),
		maxf(positions[30].distance_to(positions[144]), positions[60].distance_to(positions[144]))
	)
	_assert(max_difference <= 1.0, "30/60/144 FPS position difference exceeds 1 m: %.6f" % max_difference)
	print("FPS_INVARIANCE max_position_difference_m=%.6f" % max_difference)

func _test_war_thunder_parameter_mapping() -> void:
	_assert(is_equal_approx(Config.launch_mass_kg, 74.5), "assembled launch mass was not mapped")
	_assert(is_equal_approx(Config.final_mass_kg(), 28.0), "WT massEnd was not mapped to burnout mass")
	_assert(is_equal_approx(Config.booster_mass_kg, 46.5), "booster mass was not mapped")
	_assert(is_equal_approx(Config.assembled_length_m, 3.16), "assembled length was not mapped")
	_assert(is_equal_approx(Config.body_length_m, 1.85), "sustainer length was not mapped")
	_assert(is_equal_approx(Config.booster_caliber_m, 0.17), "booster caliber was not mapped")
	_assert(is_equal_approx(Config.body_caliber_m, 0.09), "sustainer caliber was not mapped")
	_assert(is_equal_approx(Config.motor_burn_time_s, 2.4), "WT timeFire was not mapped")
	_assert(is_equal_approx(Config.thrust_newtons, 26000.0), "WT force was not mapped")
	_assert(is_equal_approx(Config.launch_speed_mps, 10.0), "WT startSpeed was not mapped")
	_assert(is_equal_approx(Config.maximum_speed_mps, 1300.0), "WT endSpeed was not mapped")
	_assert(is_equal_approx(Config.maximum_distance_m, 20000.0), "WT maxDistance was not mapped")
	_assert(is_equal_approx(Config.maximum_flight_time_s, 30.0), "WT timeLife was not mapped")
	_assert(is_equal_approx(Config.drag_coefficient_multiplier, 1.1), "WT CxK was not mapped")
	_assert(is_equal_approx(Config.fins_lateral_acceleration, 32.0), "WT finsLatAccel was not mapped")
	_assert(absf(rad_to_deg(Config.maximum_horizontal_fin_deflection_rad()) - 13.05) < 0.001, "WT finsAoaHor conversion is wrong")
	_assert(absf(rad_to_deg(Config.maximum_vertical_fin_deflection_rad()) - 13.05) < 0.001, "WT finsAoaVer conversion is wrong")
	_assert(is_equal_approx(Config.control_gain_at_time(0.0), 0.0), "timeToGain start is wrong")
	_assert(absf(Config.control_gain_at_time(1.0) - 0.25) < 0.0001, "timeToGain interpolation at 1 s is wrong")
	_assert(is_equal_approx(Config.control_gain_at_time(2.0), 0.5), "timeToGain point 1 is wrong")
	_assert(is_equal_approx(Config.control_gain_at_time(2.5), 0.7), "timeToGain point 2 is wrong")
	_assert(is_equal_approx(Config.control_gain_at_time(3.0), 1.0), "timeToGain point 3 is wrong")
	_assert(is_equal_approx(Config.launch_elevation_margin_deg, 0.0), "obsolete launch elevation margin is still enabled")
	print("WT_MAPPING launch_mass_kg=%.1f sustainer_mass_kg=%.1f booster_mass_kg=%.1f fin_limit_deg=%.2f" % [Config.launch_mass_kg, Config.final_mass_kg(), Config.booster_mass_kg, rad_to_deg(Config.maximum_horizontal_fin_deflection_rad())])

func _test_flight_profile() -> void:
	var missile = _new_test_missile()
	var sample_steps = [0, 200, 400, 500, 1000, 2000, 3000, 4000, 5000, 6000]
	var next_sample = 1
	var max_speed = missile.current_speed
	var speed_at_burnout = 0.0
	var range_at_burnout = 0.0
	var speed_one_km_after_burnout = -1.0
	var speed_at_12_km = -1.0
	var speed_at_18_km = -1.0
	var previous_range = missile.distance_from_launch_m
	var previous_speed = missile.current_speed
	print("PROFILE time_s,speed_mps,range_m,load_g")
	print("PROFILE 0.0,%.3f,0.000,0.000" % missile.current_speed)
	for step in range(1, 6001):
		missile.update_guidance_acceleration(Vector3.ZERO, "ТТ")
		missile.simulate_physics_step(PHYSICS_DELTA, false)
		max_speed = maxf(max_speed, missile.current_speed)
		if speed_at_burnout <= 0.0 and missile.booster_jettisoned:
			speed_at_burnout = missile.current_speed
			range_at_burnout = missile.distance_from_launch_m
		var current_range = missile.distance_from_launch_m
		if speed_at_burnout > 0.0 and speed_one_km_after_burnout < 0.0 and current_range >= range_at_burnout + 1000.0:
			speed_one_km_after_burnout = missile.current_speed
		if speed_at_12_km < 0.0 and current_range >= 12000.0:
			var fraction_12 = inverse_lerp(previous_range, current_range, 12000.0)
			speed_at_12_km = lerpf(previous_speed, missile.current_speed, fraction_12)
		if speed_at_18_km < 0.0 and current_range >= 18000.0:
			var fraction_18 = inverse_lerp(previous_range, current_range, 18000.0)
			speed_at_18_km = lerpf(previous_speed, missile.current_speed, fraction_18)
		if next_sample < sample_steps.size() and step == sample_steps[next_sample]:
			print("PROFILE %.1f,%.3f,%.3f,%.3f" % [step * PHYSICS_DELTA, missile.current_speed, missile.distance_travelled_m, missile.current_load_factor_g])
			next_sample += 1
		previous_range = current_range
		previous_speed = missile.current_speed
	var braking_per_km = speed_at_burnout - speed_one_km_after_burnout
	print("DRAG_CALIBRATION burnout_mps=%.3f loss_first_km_mps=%.3f speed_12km_mps=%.3f speed_18km_mps=%.3f" % [speed_at_burnout, braking_per_km, speed_at_12_km, speed_at_18_km])
	_assert(max_speed >= 1250.0 and max_speed <= 1400.0, "maximum speed is not near 1300 m/s: %.3f" % max_speed)
	_assert(missile.current_speed < speed_at_burnout, "speed did not fall naturally after motor burnout")
	_assert(!missile.booster_attached and missile.booster_jettisoned, "booster did not separate at burnout")
	_assert(absf(missile.current_mass_kg - Config.final_mass_kg()) < 0.001, "post-separation mass is not sustainer mass")
	_assert(braking_per_km >= 30.0 and braking_per_km <= 50.0, "first-km ballistic braking is not near 40 m/s: %.3f" % braking_per_km)
	_assert(absf(speed_at_12_km - 900.0) <= 80.0, "speed at 12 km is outside calibration band: %.3f" % speed_at_12_km)
	_assert(absf(speed_at_18_km - 780.0) <= 80.0, "speed at 18 km is outside calibration band: %.3f" % speed_at_18_km)
	_assert(missile.distance_travelled_m >= 20000.0 and missile.distance_travelled_m <= 27000.0, "30 s kinematic range is not of order 20 km: %.3f" % missile.distance_travelled_m)
	_assert(missile.distance_from_launch_m <= Config.maximum_distance_m + Config.maximum_speed_mps * PHYSICS_DELTA + 0.1, "maxDistance overshoot exceeds one physics step")
	_assert(missile.peak_load_factor_g <= Config.maximum_load_factor_g + 0.001, "load limit exceeded: %.3f g" % missile.peak_load_factor_g)
	missile.free()

	var straight = _new_test_missile()
	var turning = _new_test_missile()
	straight.time_alive = Config.motor_burn_time_s + 0.1
	turning.time_alive = Config.motor_burn_time_s + 0.1
	straight.velocity = Vector3(0.0, 0.0, -800.0)
	turning.velocity = straight.velocity
	for step in range(400):
		straight.update_guidance_acceleration(Vector3.ZERO, "ТТ")
		turning.update_guidance_acceleration(Vector3.RIGHT * 1000.0, "ПС")
		straight.simulate_physics_step(PHYSICS_DELTA, false)
		turning.simulate_physics_step(PHYSICS_DELTA, false)
	_assert(turning.peak_load_factor_g <= Config.maximum_load_factor_g + 0.001, "turning load exceeded configured limit")
	_assert(turning.current_speed <= straight.current_speed + 0.5, "normal turn added kinetic energy without thrust")
	print("MANEUVER peak_load_g=%.3f turning_speed_mps=%.3f straight_speed_mps=%.3f" % [turning.peak_load_factor_g, turning.current_speed, straight.current_speed])
	straight.free()
	turning.free()

func _test_six_dof_control_response() -> void:
	var missile = _new_test_missile()
	missile.global_position = Vector3(0.0, 5000.0, 0.0)
	missile.initialize_launch_state(Vector3.FORWARD)
	missile.time_alive = Config.motor_burn_time_s + 0.1
	missile.velocity = Vector3.FORWARD * 700.0
	var initial_forward = missile.body_forward_direction()
	var maximum_yaw_rate = 0.0
	var maximum_misalignment = 0.0
	for step in range(400):
		missile.update_guidance_acceleration(Vector3.RIGHT * 8.0 * 9.80665, "ПС")
		missile.simulate_physics_step(PHYSICS_DELTA, false)
		maximum_yaw_rate = maxf(maximum_yaw_rate, absf(missile.body_angular_velocity_rad_s.y))
		var velocity_direction = missile.velocity.normalized()
		var alignment = clampf(missile.body_forward_direction().dot(velocity_direction), -1.0, 1.0)
		maximum_misalignment = maxf(maximum_misalignment, acos(alignment))
	_assert(absf(missile.yaw_fin_deflection_rad) > 0.0001, "6DOF yaw actuator never moved")
	_assert(maximum_yaw_rate > 0.01, "aerodynamic control moment did not create body yaw rate")
	_assert(maximum_misalignment > deg_to_rad(0.05), "body attitude remained glued to velocity")
	_assert(missile.body_forward_direction().dot(initial_forward) < 0.999, "missile attitude did not rotate")
	_assert(missile.global_position.x > 1.0, "right acceleration command did not bend the trajectory right")
	_assert(missile.peak_load_factor_g <= Config.maximum_load_factor_g + 0.001, "6DOF response exceeded structural load limit")
	print("SIX_DOF yaw_rate_rad_s=%.3f max_body_velocity_angle_deg=%.3f lateral_displacement_m=%.3f" % [maximum_yaw_rate, rad_to_deg(maximum_misalignment), missile.global_position.x])
	missile.free()

func _test_six_dof_guided_intercept() -> void:
	var missile = _new_test_missile()
	var launch_position = Vector3(0.0, 1000.0, 0.0)
	var target_position = Vector3(0.0, 1000.0, -8000.0)
	var target_velocity = Vector3.RIGHT * 120.0
	missile.global_position = launch_position
	missile.initialize_launch_state(Vector3.FORWARD)
	var minimum_miss_distance = missile.global_position.distance_to(target_position)
	for step in range(4000):
		var previous_relative = missile.global_position - target_position
		var command = Guidance.half_straightening_acceleration(
			missile.global_position,
			missile.velocity,
			target_position,
			target_velocity,
			Config.half_straightening_time_constant_s
		)
		missile.update_guidance_acceleration(command, "ПС")
		missile.simulate_physics_step(PHYSICS_DELTA, false)
		target_position += target_velocity * PHYSICS_DELTA
		var current_relative = missile.global_position - target_position
		minimum_miss_distance = minf(
			minimum_miss_distance,
			Guidance.closest_approach_distance(previous_relative, current_relative)
		)
		if current_relative.dot(missile.velocity - target_velocity) > 0.0 or !missile.is_active:
			break
	_assert(minimum_miss_distance <= Config.proximity_fuze_radius_m, "6DOF autopilot missed transverse target by %.3f m" % minimum_miss_distance)
	print("GUIDED_INTERCEPT miss_distance_m=%.3f flight_time_s=%.3f" % [minimum_miss_distance, missile.time_alive])
	if is_instance_valid(missile) and !missile.is_queued_for_deletion():
		missile.free()

func _test_launch_elevation_compensation() -> void:
	var target_line_pitch = 0.0
	var launch_pitch = GlobalPantsirSystem.calculate_missile_launch_pitch(target_line_pitch)
	var launch_direction = Vector3.FORWARD.rotated(Vector3.RIGHT, launch_pitch).normalized()
	var vertical_thrust = Config.thrust_newtons * launch_direction.y
	var launch_weight = Config.launch_mass_kg * 9.80665
	_assert(launch_direction.y > 0.0, "positive launch pitch does not point the missile upward")
	_assert(absf(vertical_thrust - launch_weight) <= launch_weight * 0.0001, "zero-margin launch angle does not balance initial missile weight")

	var missile = _new_test_missile()
	var launcher_position = Vector3(0.0, 3.5, 0.0)
	var target_position = Vector3(0.0, 3.5, -15000.0)
	missile.global_position = launcher_position
	missile.initialize_launch_state(launch_direction)
	var minimum_altitude = missile.global_position.y
	var maximum_altitude = missile.global_position.y
	var altitude_at_burnout = missile.global_position.y
	var maximum_boost_aoa = 0.0
	var maximum_boost_fin = 0.0
	for step in range(2000):
		var range_to_target = missile.global_position.distance_to(target_position)
		var loft = Guidance.smooth_loft_height(range_to_target, Config.maximum_loft_height_m, Config.loft_fade_range_m)
		var command = Guidance.three_point_acceleration(
			launcher_position,
			missile.global_position,
			missile.velocity,
			target_position,
			Vector3.ZERO,
			loft,
			Config.three_point_position_gain_s2,
			Config.three_point_velocity_gain_s
		)
		missile.update_guidance_acceleration(command, "ТТ")
		missile.simulate_physics_step(PHYSICS_DELTA, false)
		minimum_altitude = minf(minimum_altitude, missile.global_position.y)
		maximum_altitude = maxf(maximum_altitude, missile.global_position.y)
		if missile.time_alive <= Config.motor_burn_time_s:
			maximum_boost_aoa = maxf(maximum_boost_aoa, absf(missile.angle_of_attack_rad))
			maximum_boost_fin = maxf(maximum_boost_fin, absf(missile.pitch_fin_deflection_rad))
		if step == 499:
			altitude_at_burnout = missile.global_position.y
		if !missile.is_active:
			break
	_assert(missile.is_active, "missile hit the ground while following a level ТТ line")
	_assert(missile.global_position.y >= 2.0, "missile still has excessive in-flight sag after gravity compensation: %.3f m" % missile.global_position.y)
	_assert(maximum_boost_aoa < deg_to_rad(10.0), "boost AoA still saturates despite thrust-vector authority: %.3f deg" % rad_to_deg(maximum_boost_aoa))
	_assert(maximum_boost_fin < Config.maximum_vertical_fin_deflection_rad() * 0.95, "boost fin still saturates at its mechanical stop")
	print("LAUNCH_ELEVATION target_deg=%.3f launch_deg=%.3f min_altitude_m=%.3f max_altitude_m=%.3f altitude_at_burnout_m=%.3f altitude_at_10s_m=%.3f boost_aoa_deg=%.3f boost_fin_deg=%.3f" % [rad_to_deg(target_line_pitch), rad_to_deg(launch_pitch), minimum_altitude, maximum_altitude, altitude_at_burnout, missile.global_position.y, rad_to_deg(maximum_boost_aoa), rad_to_deg(maximum_boost_fin)])
	if is_instance_valid(missile) and !missile.is_queued_for_deletion():
		missile.free()

func _test_elevated_launch_boost_lead() -> void:
	var target_line_pitch = deg_to_rad(5.0)
	var launch_pitch = GlobalPantsirSystem.calculate_missile_launch_pitch(target_line_pitch)
	var launch_weight = Config.launch_mass_kg * PantsirMissile.STANDARD_GRAVITY_MPS2
	var expected_boost_lead = asin(clampf(
		launch_weight * cos(target_line_pitch) / Config.thrust_newtons,
		0.0,
		1.0
	))
	_assert(
		absf((launch_pitch - target_line_pitch) - expected_boost_lead) <= deg_to_rad(0.001),
		"elevated launch does not add gravity lead relative to LOS"
	)

	var launcher_position = Vector3(0.0, 1000.0, 0.0)
	var target_range = 15000.0
	var target_position = launcher_position + Vector3(
		0.0,
		tan(target_line_pitch) * target_range,
		-target_range
	)
	var launch_direction = Vector3.FORWARD.rotated(Vector3.RIGHT, launch_pitch).normalized()
	var missile = _new_test_missile()
	missile.global_position = launcher_position
	missile.initialize_launch_state(launch_direction)
	var minimum_boost_los_error = 0.0
	var los_error_at_burnout = 0.0
	var los_error_at_three_seconds = 0.0
	var maximum_los_error_through_five_seconds = 0.0
	for step in range(int(ceil(5.0 / PHYSICS_DELTA))):
		var command = Guidance.three_point_acceleration(
			launcher_position,
			missile.global_position,
			missile.velocity,
			target_position,
			Vector3.ZERO,
			0.0,
			Config.three_point_position_gain_s2,
			Config.three_point_velocity_gain_s
		)
		missile.update_guidance_acceleration(command, "TT")
		missile.simulate_physics_step(PHYSICS_DELTA, false)
		var distance_along_los = -(missile.global_position.z - launcher_position.z)
		var los_height = launcher_position.y + tan(target_line_pitch) * distance_along_los
		var los_error = missile.global_position.y - los_height
		maximum_los_error_through_five_seconds = maxf(maximum_los_error_through_five_seconds, los_error)
		if missile.time_alive <= Config.motor_burn_time_s + PHYSICS_DELTA * 0.5:
			los_error_at_burnout = los_error
			minimum_boost_los_error = minf(minimum_boost_los_error, los_error)
		if absf(missile.time_alive - 3.0) <= PHYSICS_DELTA * 0.5:
			los_error_at_three_seconds = los_error
	_assert(
		minimum_boost_los_error >= -0.5,
		"missile sagged below elevated LOS during boost: %.3f m" % minimum_boost_los_error
	)
	_assert(
		maximum_los_error_through_five_seconds <= 6.0,
		"boost lead caused excessive late LOS overshoot: %.3f m" % maximum_los_error_through_five_seconds
	)
	print("BOOST_LOS_LEAD target_deg=%.3f launch_deg=%.3f min_los_error_m=%.3f burnout_los_error_m=%.3f error_at_3s_m=%.3f max_error_through_5s_m=%.3f" % [rad_to_deg(target_line_pitch), rad_to_deg(launch_pitch), minimum_boost_los_error, los_error_at_burnout, los_error_at_three_seconds, maximum_los_error_through_five_seconds])
	missile.free()

func _test_guidance_math() -> void:
	var tt_command = Guidance.three_point_acceleration(
		Vector3.ZERO, Vector3(20, 0, -500), Vector3(0, 0, -500),
		Vector3(0, 0, -1000), Vector3.ZERO, 0.0, 0.85, 1.55
	)
	_assert(tt_command.x < 0.0, "ТТ command does not return missile toward complex-target line")
	var relative = Vector3(0, 0, -1000)
	var target_velocity = Vector3(200, 0, 0)
	var intercept = Guidance.intercept_time(relative, target_velocity, 1000.0)
	var ps_command = Guidance.half_straightening_acceleration(
		Vector3.ZERO, Vector3(0, 0, -1000), Vector3(0, 0, -1000), target_velocity, 0.55
	)
	_assert(intercept > 0.0 and is_finite(intercept), "ПС did not find a finite positive intercept")
	_assert(ps_command.x > 0.0, "ПС did not lead a transverse target")

func _test_mode_hysteresis() -> void:
	var mode = "ТТ"
	mode = Guidance.select_mode_with_hysteresis(mode, Config.mode_switch_to_ps_rad_s + 0.0005, Config.mode_switch_to_ps_rad_s, Config.mode_switch_to_tt_rad_s)
	_assert(mode == "ПС", "mode did not switch ТТ -> ПС above upper threshold")
	for rate in [0.0039, 0.0035, 0.0031, 0.0036]:
		mode = Guidance.select_mode_with_hysteresis(mode, rate, Config.mode_switch_to_ps_rad_s, Config.mode_switch_to_tt_rad_s)
	_assert(mode == "ПС", "mode chattered inside hysteresis band")
	mode = Guidance.select_mode_with_hysteresis(mode, Config.mode_switch_to_tt_rad_s - 0.0005, Config.mode_switch_to_ps_rad_s, Config.mode_switch_to_tt_rad_s)
	_assert(mode == "ТТ", "mode did not switch ПС -> ТТ below lower threshold")

	# The built-in HIMARS trajectory starts 40 km away and arrives in 40 s.
	# At radar acquisition around 25 km its LOS rate is only about 4.87 mrad/s;
	# the former 12 mrad/s threshold made ПС mathematically unreachable.
	var flight_duration = 40.0
	var sample_time = 15.0
	var start_position = Vector3(0.0, 100.0, -40000.0)
	var impact_position = Vector3.ZERO
	var gravity = Vector3(0.0, -9.8, 0.0)
	var initial_velocity = (
		impact_position - start_position - 0.5 * gravity * flight_duration * flight_duration
	) / flight_duration
	var himars_position = (
		start_position
		+ initial_velocity * sample_time
		+ 0.5 * gravity * sample_time * sample_time
	)
	var himars_velocity = initial_velocity + gravity * sample_time
	var himars_los_rate = Guidance.line_of_sight_rate(Vector3(0.0, 3.5, 0.0), himars_position, himars_velocity)
	_assert(
		himars_los_rate >= Config.mode_switch_to_ps_rad_s,
		"HIMARS LOS rate cannot reach ПС threshold: %.6f rad/s" % himars_los_rate
	)
	var filtered_rate = 0.0
	mode = "ТТ"
	for step in range(200):
		var blend = 1.0 - exp(-PHYSICS_DELTA / Config.mode_filter_time_constant_s)
		filtered_rate = lerpf(filtered_rate, himars_los_rate, blend)
		mode = Guidance.select_mode_with_hysteresis(mode, filtered_rate, Config.mode_switch_to_ps_rad_s, Config.mode_switch_to_tt_rad_s)
	_assert(mode == "ПС", "filtered HIMARS LOS rate did not switch to ПС within one second")
	print("MODE_SWITCH himars_los_rate_rad_s=%.6f threshold_ps_rad_s=%.6f filtered_after_1s_rad_s=%.6f mode=%s" % [himars_los_rate, Config.mode_switch_to_ps_rad_s, filtered_rate, mode])

func _test_timestamped_track_prediction() -> void:
	const TRACK_ID: int = 9901
	var capture_time = 20.0
	var consume_time = 20.05
	var captured_position = Vector3(0.0, 1000.0, -10000.0)
	var captured_velocity = Vector3(250.0, 0.0, 0.0)

	GlobalPantsirSystem.tracks.erase(TRACK_ID)
	GlobalPantsirSystem.targets = [{
		"id": TRACK_ID,
		"position": captured_position,
		"velocity": captured_velocity,
		"measurement_timestamp": capture_time,
		"is_threat": true,
	}]
	GlobalPantsirSystem.pantsir_position = Vector3.ZERO
	GlobalPantsirSystem._simulation_time_s = consume_time
	GlobalPantsirSystem._radar_measurement_accumulator_s = Config.radar_measurement_interval_s
	GlobalPantsirSystem.search_radar_on = false
	GlobalPantsirSystem.sector_radar_on = true
	GlobalPantsirSystem.turret_current_angle = 0.0
	# Precise МРЛС data reaches a track only in АС through its gate, so the
	# target is already held precisely with a track one sample old. Noise is
	# off: this checks latency compensation, not measurement error.
	var previous_time = capture_time - Config.radar_measurement_interval_s
	var seed_filter = KalmanTrack3D.new()
	seed_filter.initialize(captured_position - captured_velocity * Config.radar_measurement_interval_s, captured_velocity, 1.0, 1.0)
	GlobalPantsirSystem.tracks[TRACK_ID] = {
		"position": seed_filter.position,
		"velocity": seed_filter.velocity,
		"kalman_filter": seed_filter,
		"is_threat": true,
		"timestamp": previous_time,
		"id": TRACK_ID,
		"hits": 1,
		"stable": false,
	}
	GlobalPantsirSystem._mrls_target_states[TRACK_ID] = {
		"hits": GlobalPantsirSystem.MRLS_ACQUISITION_HITS_REQUIRED,
		"history": [],
		"next_dwell_s": 0.0,
		"precise": true,
		"last_detection_s": consume_time,
		"track_start_s": consume_time,
	}
	var saved_sigmas = [GlobalPantsirSystem.mrls_angle_sigma_rad, GlobalPantsirSystem.mrls_range_sigma_m, GlobalPantsirSystem.mrls_velocity_sigma_mps]
	GlobalPantsirSystem.mrls_angle_sigma_rad = 0.0
	GlobalPantsirSystem.mrls_range_sigma_m = 0.0
	GlobalPantsirSystem.mrls_velocity_sigma_mps = 0.0
	GlobalPantsirSystem.reset_measurement_noise(13579)
	GlobalPantsirSystem.process_radar_logic(0.0)
	GlobalPantsirSystem.mrls_angle_sigma_rad = saved_sigmas[0]
	GlobalPantsirSystem.mrls_range_sigma_m = saved_sigmas[1]
	GlobalPantsirSystem.mrls_velocity_sigma_mps = saved_sigmas[2]

	_assert(GlobalPantsirSystem.tracks.has(TRACK_ID), "timestamped radar sample did not create a track")
	var track = GlobalPantsirSystem.tracks[TRACK_ID]
	_assert(absf(float(track["timestamp"]) - capture_time) < 0.000001, "capture timestamp was replaced by consume time")
	_assert(track["velocity"].is_equal_approx(captured_velocity), "available target velocity was discarded")
	_assert(absf(float(track["source_latency_s"]) - 0.05) < 0.0001, "source latency telemetry is wrong")

	var predicted_state = GlobalPantsirSystem.get_predicted_track_state(TRACK_ID)
	var expected_position = captured_position + captured_velocity * (consume_time - capture_time)
	var prediction_error = predicted_state["position"].distance_to(expected_position)
	_assert(prediction_error <= 3.0, "50 ms source latency was not compensated: %.3f m" % prediction_error)

	var hits_before_duplicate = int(track["hits"])
	GlobalPantsirSystem._radar_measurement_accumulator_s = Config.radar_measurement_interval_s
	GlobalPantsirSystem.process_radar_logic(0.0)
	_assert(int(GlobalPantsirSystem.tracks[TRACK_ID]["hits"]) == hits_before_duplicate, "same radar packet was incorporated twice")

	GlobalPantsirSystem.locked_track_id = TRACK_ID
	GlobalPantsirSystem.selected_weapon = "MISSILES"
	GlobalPantsirSystem.process_auto_tracking(0.0)
	var expected_azimuth = atan2(expected_position.x, -expected_position.z)
	_assert(absf(GlobalPantsirSystem.angle_difference(GlobalPantsirSystem.optic_target_angle, expected_azimuth)) < 0.001, "optic target does not use predicted track state")
	GlobalPantsirSystem.optic_current_angle = GlobalPantsirSystem.optic_target_angle - 0.01
	GlobalPantsirSystem.process_kinematics(PHYSICS_DELTA)
	_assert(absf(GlobalPantsirSystem.angle_difference(GlobalPantsirSystem.optic_current_angle, GlobalPantsirSystem.optic_target_angle)) < 0.000001, "optic servo still adds exponential phase lag")
	print("TRACK_LATENCY source_ms=50 compensated_error_m=%.3f predicted_lead_m=%.3f" % [prediction_error, predicted_state["position"].x - captured_position.x])

	GlobalPantsirSystem.tracks.erase(TRACK_ID)
	GlobalPantsirSystem._mrls_target_states.erase(TRACK_ID)
	GlobalPantsirSystem.targets = []
	GlobalPantsirSystem.locked_track_id = -1
	GlobalPantsirSystem.sector_radar_on = false
	GlobalPantsirSystem._radar_measurement_accumulator_s = 0.0

func _test_track_loss_behavior() -> void:
	var missile = _new_test_missile()
	var target = Node3D.new()
	get_tree().root.add_child(target)
	target.global_position = Vector3(0, 1000, -5000)
	missile.set_fuze_target(target)
	GlobalPantsirSystem._simulation_time_s = 10.0
	GlobalPantsirSystem.tracks[901] = {
		"position": target.global_position,
		"measured_position": target.global_position,
		"velocity": Vector3(120, 0, 0),
		"timestamp": 10.0,
		"id": 901,
		"hits": 5,
		"stable": true,
		"is_threat": true,
	}
	GlobalPantsirSystem.guidance_channels[0] = {
		"missile": missile,
		"target_id": 901,
		"guidance_mode": "ТТ",
		"filtered_los_rate": 0.0,
		"last_command": Vector3.ZERO,
		"loss_elapsed_s": 0.0,
		"noise_key": "loss_test_missile",
		"missile_position": missile.global_position,
		"missile_measured_position": missile.global_position,
		"missile_velocity": missile.velocity,
		"missile_measurement_timestamp": 10.0,
	}
	GlobalPantsirSystem.process_missile_guidance(PHYSICS_DELTA)
	GlobalPantsirSystem.tracks.erase(901)
	for step in range(100):
		GlobalPantsirSystem.process_missile_guidance(PHYSICS_DELTA)
	_assert(GlobalPantsirSystem.guidance_channels[0] != null and missile.is_active, "temporary track loss destroyed missile or channel before grace period")
	GlobalPantsirSystem.tracks[901] = {
		"position": target.global_position,
		"measured_position": target.global_position,
		"velocity": Vector3(120, 0, 0),
		"timestamp": 10.0,
		"id": 901,
		"hits": 6,
		"stable": true,
		"is_threat": true,
	}
	GlobalPantsirSystem.process_missile_guidance(PHYSICS_DELTA)
	_assert(GlobalPantsirSystem.guidance_channels[0]["loss_elapsed_s"] == 0.0, "guidance did not recover inside grace period")
	GlobalPantsirSystem.tracks.erase(901)
	for step in range(400):
		GlobalPantsirSystem.process_missile_guidance(PHYSICS_DELTA)
	_assert(GlobalPantsirSystem.guidance_channels[0] == null and missile.is_active, "final track loss did not release channel into passive flight")
	GlobalPantsirSystem.guidance_channels = [null, null, null, null]
	missile.free()
	target.free()

func _test_continuous_fuze() -> void:
	var closest = Guidance.closest_approach_distance(Vector3(-20, 0, 0), Vector3(20, 0, 0))
	_assert(closest <= Config.proximity_fuze_radius_m, "continuous fuze missed a between-ticks crossing")
	var miss_distance = Guidance.closest_approach_distance(Vector3(-20, 12, 0), Vector3(20, 12, 0))
	_assert(miss_distance > Config.proximity_fuze_radius_m, "continuous fuze triggered outside configured radius")
	var ticks = [_fuse_trigger_tick(30), _fuse_trigger_tick(60), _fuse_trigger_tick(144)]
	_assert(ticks[0] > 0 and ticks[0] == ticks[1] and ticks[1] == ticks[2], "continuous fuze timing changed with render FPS")
	print("FUZE trigger_physics_tick_30_60_144=%s" % str(ticks))

func _fuse_trigger_tick(render_fps: int) -> int:
	var missile_position = Vector3(-100, 0, 0)
	var target_position = Vector3.ZERO
	var missile_velocity = Vector3(5000, 0, 0)
	var target_velocity = Vector3(-600, 0, 0)
	var render_accumulator = 0.0
	var physics_tick = 0
	while physics_tick < 20:
		render_accumulator += 1.0 / float(render_fps)
		while render_accumulator + 0.0000001 >= PHYSICS_DELTA:
			var old_relative = missile_position - target_position
			missile_position += missile_velocity * PHYSICS_DELTA
			target_position += target_velocity * PHYSICS_DELTA
			physics_tick += 1
			render_accumulator -= PHYSICS_DELTA
			var new_relative = missile_position - target_position
			if Guidance.closest_approach_distance(old_relative, new_relative) <= Config.proximity_fuze_radius_m:
				return physics_tick
	return -1

func _test_measurement_noise() -> void:
	GlobalPantsirSystem.pantsir_position = Vector3.ZERO
	var real_position = Vector3(0, 0, -10000)
	GlobalPantsirSystem.reset_measurement_noise(12345)
	var first = GlobalPantsirSystem._measure_position("noise_test", real_position, Config.radar_measurement_interval_s)
	GlobalPantsirSystem.reset_measurement_noise(12345)
	var repeated = GlobalPantsirSystem._measure_position("noise_test", real_position, Config.radar_measurement_interval_s)
	_assert(first.is_equal_approx(repeated), "measurement noise is not reproducible for a fixed seed")
	GlobalPantsirSystem.reset_measurement_noise(54321)
	var sum_squared = 0.0
	var samples = 12000
	for index in range(samples + 500):
		var measured = GlobalPantsirSystem._measure_position("noise_rms", real_position, Config.radar_measurement_interval_s)
		if index >= 500:
			sum_squared += measured.distance_squared_to(real_position)
	var measured_rms = sqrt(sum_squared / samples)
	var expected_rms = real_position.length() * Config.position_error_fraction
	_assert(absf(measured_rms - expected_rms) / expected_rms < 0.12, "measurement RMS is outside 12%%: measured %.3f expected %.3f" % [measured_rms, expected_rms])
	print("NOISE rms_3d_m=%.3f expected_m=%.3f seed_reproducible=%s" % [measured_rms, expected_rms, str(first.is_equal_approx(repeated))])

func _test_kalman_noise_suppression() -> void:
	GlobalPantsirSystem.pantsir_position = Vector3.ZERO
	GlobalPantsirSystem.reset_measurement_noise(24680)
	var true_position = Vector3(0, 1000, -10000)
	var first_measurement = GlobalPantsirSystem._measure_position("kalman_noise", true_position, Config.radar_measurement_interval_s)
	var filter: KalmanTrack3D = Kalman.new()
	filter.initialize(
		first_measurement,
		Vector3.ZERO,
		GlobalPantsirSystem._measurement_variance_for_position(first_measurement),
		Config.kalman_initial_target_velocity_sigma_mps ** 2
	)
	var raw_error_squared = 0.0
	var filtered_error_squared = 0.0
	var raw_velocity_error_squared = 0.0
	var velocity_error_squared = 0.0
	var measured_samples = 0
	var previous_raw_measurement = first_measurement
	for index in range(5500):
		var raw_measurement = GlobalPantsirSystem._measure_position("kalman_noise", true_position, Config.radar_measurement_interval_s)
		var raw_velocity = (raw_measurement - previous_raw_measurement) / Config.radar_measurement_interval_s
		previous_raw_measurement = raw_measurement
		filter.update(
			raw_measurement,
			Config.radar_measurement_interval_s,
			GlobalPantsirSystem._measurement_variance_for_position(raw_measurement),
			Config.kalman_target_acceleration_sigma_mps2
		)
		if index >= 500:
			raw_error_squared += raw_measurement.distance_squared_to(true_position)
			filtered_error_squared += filter.position.distance_squared_to(true_position)
			raw_velocity_error_squared += raw_velocity.length_squared()
			velocity_error_squared += filter.velocity.length_squared()
			measured_samples += 1
	var raw_rms = sqrt(raw_error_squared / measured_samples)
	var filtered_rms = sqrt(filtered_error_squared / measured_samples)
	var raw_velocity_rms = sqrt(raw_velocity_error_squared / measured_samples)
	var velocity_rms = sqrt(velocity_error_squared / measured_samples)
	_assert(filtered_rms <= raw_rms * 1.02, "Kalman filter amplified position noise by more than 2%%: raw %.3f filtered %.3f" % [raw_rms, filtered_rms])
	_assert(velocity_rms < raw_velocity_rms * 0.35, "Kalman filter did not sufficiently suppress differentiated velocity noise: raw %.3f filtered %.3f" % [raw_velocity_rms, velocity_rms])
	print("KALMAN raw_position_rms_m=%.3f filtered_position_rms_m=%.3f raw_velocity_rms_mps=%.3f filtered_velocity_rms_mps=%.3f" % [raw_rms, filtered_rms, raw_velocity_rms, velocity_rms])

func _assert(condition: bool, message: String) -> void:
	if !condition:
		failures.append(message)
