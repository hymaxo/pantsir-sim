extends Resource
class_name MissileFlightConfig

# The propulsion and limit values in this resource are mapped from the
# 170 mm ZUR 95Ya6 War Thunder data supplied for the project. Aerodynamic
# derivatives are explicit calibration values: WT's CxK is a multiplier, not
# a conventional standalone drag coefficient.

@export_group("War Thunder propulsion")
@export var launch_mass_kg: float = 74.5
@export var burnout_mass_kg: float = 28.0
@export var booster_mass_kg: float = 46.5
@export var thrust_newtons: float = 26000.0
@export var motor_burn_time_s: float = 2.4
@export var use_start_speed: bool = true
@export var launch_speed_mps: float = 10.0
@export var maximum_speed_mps: float = 1300.0

@export_group("War Thunder flight limits")
@export var maximum_distance_m: float = 20000.0
@export var minimum_guidance_distance_m: float = 1200.0
@export var guaranteed_range_m: float = 18000.0
@export var maximum_flight_time_s: float = 30.0
@export var maximum_load_factor_g: float = 32.0

@export_group("Geometry and inertia")
# Complete round during boost, then the separated guided sustainer.
@export var assembled_length_m: float = 3.16
@export var booster_caliber_m: float = 0.17
@export var body_caliber_m: float = 0.09
@export var body_length_m: float = 1.85
@export var body_reference_area_m2: float = 0.006361725
@export var wing_area_multiplier: float = 1.3
@export var minimum_roll_inertia_kg_m2: float = 0.12

@export_group("Aerodynamics")
@export var drag_coefficient_multiplier: float = 1.1
@export var boost_drag_coefficient: float = 0.01
@export var sustainer_drag_calibration: float = 1.14
@export var static_normal_coefficient_per_rad: float = 8.0
@export var fin_normal_coefficient_per_rad: float = 3.0
@export var induced_drag_factor: float = 0.045
@export var static_moment_coefficient_per_rad: float = 0.75
@export var fin_moment_coefficient_per_rad: float = 1.25
@export var pitch_yaw_damping_coefficient: float = 20.0
@export var roll_damping_coefficient: float = 5.0
@export var maximum_angle_of_attack_deg: float = 20.0
@export var atmosphere_scale_height_m: float = 8500.0
@export var wind_velocity_mps: Vector3 = Vector3.ZERO

@export_group("Fin actuators and autopilot")
# WT stores these as fractions of 90 degrees: 0.145 * 90 = 13.05 deg.
@export_range(0.0, 1.0, 0.001) var fins_aoa_horizontal: float = 0.145
@export_range(0.0, 1.0, 0.001) var fins_aoa_vertical: float = 0.145
@export var fins_lateral_acceleration: float = 32.0
@export var fin_actuator_time_constant_s: float = 0.035
@export var maximum_fin_rate_deg_s: float = 720.0
@export var maximum_body_rate_deg_s: float = 1080.0
@export var autopilot_angle_gain: float = 0.8
@export var autopilot_rate_gain_s: float = 0.035
@export var autopilot_time_constant_s: float = 0.16
@export var time_to_gain_0: Vector2 = Vector2(0.0, 0.0)
@export var time_to_gain_1: Vector2 = Vector2(2.0, 0.5)
@export var time_to_gain_2: Vector2 = Vector2(2.5, 0.7)
@export var time_to_gain_3: Vector2 = Vector2(3.0, 1.0)
@export var command_loss_decay_time_s: float = 0.45

@export_group("Command guidance")
@export var three_point_position_gain_s2: float = 0.85
@export var three_point_velocity_gain_s: float = 1.55
@export var half_straightening_time_constant_s: float = 0.55
@export_range(0.0, 10.0, 0.1, "suffix:deg") var launch_elevation_margin_deg: float = 0.0
@export var maximum_loft_height_m: float = 5.0
@export var loft_fade_range_m: float = 2000.0
@export var mode_switch_to_ps_rad_s: float = 0.004
@export var mode_switch_to_tt_rad_s: float = 0.003
@export var mode_filter_time_constant_s: float = 0.35

@export_group("Radio tracking")
@export var radar_measurement_interval_s: float = 0.05
@export var position_error_fraction: float = 0.0001
@export var noise_correlation_time_s: float = 0.35
@export var kalman_measurement_variance_scale: float = 1.0
@export var kalman_target_acceleration_sigma_mps2: float = 18.0
@export var kalman_missile_acceleration_sigma_mps2: float = 300.0
@export var kalman_initial_target_velocity_sigma_mps: float = 300.0
@export var kalman_initial_missile_velocity_sigma_mps: float = 80.0
@export var track_loss_grace_period_s: float = 1.5

@export_group("Fuze")
@export var proximity_fuze_radius_m: float = 8.0
@export var warhead_effect_radius_m: float = 15.0
@export var fuze_arm_distance_m: float = 1.0

func final_mass_kg() -> float:
	return burnout_mass_kg

func propellant_mass_kg() -> float:
	return maxf(launch_mass_kg - burnout_mass_kg, 0.0)

func normal_reference_area_m2() -> float:
	return body_reference_area_m2 * wing_area_multiplier

func boost_reference_area_m2() -> float:
	var radius = booster_caliber_m * 0.5
	return PI * radius * radius

func fin_effectiveness_multiplier() -> float:
	# finsLatAccel is a control-effectiveness parameter, not a g-limit. The
	# derivative calibration below is defined at the source value of 32.
	return maxf(fins_lateral_acceleration, 0.0) / 32.0

func control_gain_at_time(time_s: float) -> float:
	var points = [time_to_gain_0, time_to_gain_1, time_to_gain_2, time_to_gain_3]
	if time_s <= points[0].x:
		return clampf(points[0].y, 0.0, 1.0)
	for index in range(1, points.size()):
		var right: Vector2 = points[index]
		if time_s <= right.x:
			var left: Vector2 = points[index - 1]
			var fraction = inverse_lerp(left.x, right.x, time_s) if right.x > left.x else 1.0
			return clampf(lerpf(left.y, right.y, fraction), 0.0, 1.0)
	return clampf(points[points.size() - 1].y, 0.0, 1.0)

func maximum_horizontal_fin_deflection_rad() -> float:
	return fins_aoa_horizontal * PI * 0.5

func maximum_vertical_fin_deflection_rad() -> float:
	return fins_aoa_vertical * PI * 0.5
