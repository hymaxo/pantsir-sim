extends CharacterBody3D
class_name PantsirMissile

const STANDARD_GRAVITY_MPS2: float = 9.80665
const SEA_LEVEL_DENSITY_KG_M3: float = 1.225
const GAS_HEAT_RATIO: float = 1.4
const AIR_GAS_CONSTANT: float = 287.05
const SEA_LEVEL_TEMPERATURE_K: float = 288.15
const TEMPERATURE_LAPSE_K_M: float = 0.0065
const MIN_TEMPERATURE_K: float = 216.65
const EPSILON: float = 0.000001
# Area of a target that a single fragment must strike to disable it, for
# targets that do not define their own vulnerable_area_m2.
const DEFAULT_VULNERABLE_AREA_M2: float = 0.5

@export var flight_config: MissileFlightConfig = preload("res://Resources/PantsirMissileFlightConfig.tres")
@export var create_flight_visuals: bool = true

# Translational state and telemetry.
var current_speed: float = 0.0
var current_mass_kg: float = 0.0
var current_mach: float = 0.0
var current_dynamic_pressure_pa: float = 0.0
var current_load_factor_g: float = 0.0
var peak_load_factor_g: float = 0.0
var distance_travelled_m: float = 0.0
var distance_from_launch_m: float = 0.0
var time_alive: float = 0.0
var is_active: bool = true
var motor_burning: bool = true
var booster_attached: bool = true
var booster_jettisoned: bool = false
var current_control_gain: float = 0.0

# Rotational state is expressed in missile body axes: X=pitch, Y=yaw,
# Z=roll. Godot's missile-forward axis is local -Z.
var body_angular_velocity_rad_s: Vector3 = Vector3.ZERO
var body_angular_acceleration_rad_s2: Vector3 = Vector3.ZERO
var angle_of_attack_rad: float = 0.0
var sideslip_angle_rad: float = 0.0
var pitch_fin_deflection_rad: float = 0.0
var yaw_fin_deflection_rad: float = 0.0
var guidance_mode: String = "ТТ"

# Kept as a read-only compatibility value for existing UI/scripts.
var proximity_threshold: float:
	get:
		return flight_config.proximity_fuze_radius_m

var _commanded_normal_acceleration: Vector3 = Vector3.ZERO
var _filtered_normal_acceleration: Vector3 = Vector3.ZERO
var _guidance_command_valid: bool = false
var _launch_position: Vector3 = Vector3.ZERO
var _fuze_target: Node3D = null
var _previous_missile_position: Vector3 = Vector3.ZERO
var _previous_target_position: Vector3 = Vector3.ZERO
var _have_fuze_history: bool = false
var _detonation_started: bool = false

func _ready() -> void:
	add_to_group("pantsir_missiles")
	initialize_launch_state(-global_transform.basis.z)
	if create_flight_visuals:
		setup_visuals()

func initialize_launch_state(launch_direction: Vector3, launcher_velocity: Vector3 = Vector3.ZERO) -> void:
	var direction = launch_direction.normalized()
	if direction.length_squared() <= EPSILON:
		direction = Vector3.FORWARD
	_align_body_to_direction(direction)
	velocity = (
		direction * flight_config.launch_speed_mps
		if flight_config.use_start_speed and flight_config.launch_speed_mps > EPSILON
		else launcher_velocity
	)
	current_speed = velocity.length()
	current_mass_kg = flight_config.launch_mass_kg
	current_mach = 0.0
	current_dynamic_pressure_pa = 0.0
	current_load_factor_g = 0.0
	peak_load_factor_g = 0.0
	distance_travelled_m = 0.0
	distance_from_launch_m = 0.0
	time_alive = 0.0
	is_active = true
	motor_burning = true
	booster_attached = true
	booster_jettisoned = false
	current_control_gain = 0.0
	body_angular_velocity_rad_s = Vector3.ZERO
	body_angular_acceleration_rad_s2 = Vector3.ZERO
	angle_of_attack_rad = 0.0
	sideslip_angle_rad = 0.0
	pitch_fin_deflection_rad = 0.0
	yaw_fin_deflection_rad = 0.0
	_commanded_normal_acceleration = Vector3.ZERO
	_filtered_normal_acceleration = Vector3.ZERO
	_guidance_command_valid = false
	_launch_position = global_position
	_previous_missile_position = global_position
	_detonation_started = false

func _align_body_to_direction(direction: Vector3) -> void:
	var up = Vector3.UP
	if absf(direction.dot(up)) > 0.995:
		up = Vector3.RIGHT
	look_at(global_position + direction, up)
	var transform = global_transform
	transform.basis = transform.basis.orthonormalized()
	global_transform = transform

func setup_visuals() -> void:
	var meshes: Array[MeshInstance3D] = []
	for child in get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	if meshes.is_empty():
		var mesh_instance = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.1
		cylinder.bottom_radius = 0.1
		cylinder.height = 3.0
		mesh_instance.mesh = cylinder
		mesh_instance.rotation.x = PI / 2.0
		add_child(mesh_instance)
		meshes.append(mesh_instance)
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(5.0, 5.0, 5.0)
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 10.0
	for mesh in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers = 1
		mesh.material_override = material

func _physics_process(delta: float) -> void:
	if !is_active:
		return
	simulate_physics_step(delta, true)

func simulate_physics_step(delta: float, use_character_collision: bool = true) -> void:
	if !is_active or delta <= 0.0:
		return
	var start_position = global_position
	time_alive += delta
	_update_mass_and_motor_state()

	var basis = global_transform.basis.orthonormalized()
	var air_velocity_world = velocity - flight_config.wind_velocity_mps
	var airspeed = air_velocity_world.length()
	var body_air_velocity = basis.inverse() * air_velocity_world
	var forward_air_speed = maxf(-body_air_velocity.z, EPSILON)
	angle_of_attack_rad = atan2(-body_air_velocity.y, forward_air_speed)
	sideslip_angle_rad = atan2(body_air_velocity.x, forward_air_speed)

	var altitude = maxf(global_position.y, 0.0)
	var density = atmospheric_density(altitude)
	var sound_speed = local_speed_of_sound(altitude)
	current_mach = airspeed / maxf(sound_speed, 1.0)
	current_dynamic_pressure_pa = 0.5 * density * airspeed * airspeed

	var coefficient_angle_limit = deg_to_rad(flight_config.maximum_angle_of_attack_deg)
	var aerodynamic_alpha = clampf(angle_of_attack_rad, -coefficient_angle_limit, coefficient_angle_limit)
	var aerodynamic_beta = clampf(sideslip_angle_rad, -coefficient_angle_limit, coefficient_angle_limit)
	_update_fin_actuators(delta, basis, air_velocity_world, aerodynamic_alpha, aerodynamic_beta)

	var normal_area = flight_config.normal_reference_area_m2()
	var fin_effectiveness = flight_config.fin_effectiveness_multiplier()
	var normal_coefficients = Vector2(
		-flight_config.static_normal_coefficient_per_rad * aerodynamic_beta
			- flight_config.fin_normal_coefficient_per_rad * fin_effectiveness * yaw_fin_deflection_rad,
		flight_config.static_normal_coefficient_per_rad * aerodynamic_alpha
			+ flight_config.fin_normal_coefficient_per_rad * fin_effectiveness * pitch_fin_deflection_rad
	)
	var maximum_normal_force = current_mass_kg * flight_config.maximum_load_factor_g * STANDARD_GRAVITY_MPS2
	var normal_force_per_coefficient = current_dynamic_pressure_pa * normal_area
	if normal_force_per_coefficient > EPSILON:
		normal_coefficients = normal_coefficients.limit_length(maximum_normal_force / normal_force_per_coefficient)
	var normal_force_body = Vector3(
		normal_coefficients.x * normal_force_per_coefficient,
		normal_coefficients.y * normal_force_per_coefficient,
		0.0
	)
	var normal_force_world = basis * normal_force_body
	current_load_factor_g = normal_force_body.length() / maxf(current_mass_kg * STANDARD_GRAVITY_MPS2, 1.0)
	peak_load_factor_g = maxf(peak_load_factor_g, current_load_factor_g)

	var drag_cd = drag_coefficient(current_mach)
	drag_cd += flight_config.induced_drag_factor * normal_coefficients.length_squared()
	var drag_force_world = Vector3.ZERO
	if airspeed > EPSILON:
		var axial_area = flight_config.boost_reference_area_m2() if booster_attached else flight_config.body_reference_area_m2
		var drag_force = current_dynamic_pressure_pa * axial_area * drag_cd
		drag_force_world = -air_velocity_world / airspeed * drag_force
	var thrust_force_body = Vector3(0.0, 0.0, -flight_config.thrust_newtons if motor_burning else 0.0)
	var gravity_acceleration = Vector3.DOWN * STANDARD_GRAVITY_MPS2
	var total_force_world = basis * thrust_force_body + normal_force_world + drag_force_world
	var linear_acceleration_world = total_force_world / maxf(current_mass_kg, 1.0) + gravity_acceleration
	velocity += linear_acceleration_world * delta
	if flight_config.maximum_speed_mps > 0.0:
		velocity = velocity.limit_length(flight_config.maximum_speed_mps)
	current_speed = velocity.length()

	var aerodynamic_torque_body = _calculate_aerodynamic_torque_body(
		airspeed,
		aerodynamic_alpha,
		aerodynamic_beta,
		current_dynamic_pressure_pa,
		normal_area
	)
	_integrate_rotation(aerodynamic_torque_body, delta)

	if use_character_collision and is_inside_tree():
		var collision = move_and_collide(velocity * delta)
		if collision:
			detonate()
			return
	else:
		global_position += velocity * delta
	distance_travelled_m += start_position.distance_to(global_position)
	distance_from_launch_m = _launch_position.distance_to(global_position)
	_check_continuous_proximity_fuze(start_position)

	if is_active and (
		time_alive >= flight_config.maximum_flight_time_s
		or distance_from_launch_m >= flight_config.maximum_distance_m
		or global_position.y <= GlobalPantsirSystem.get_ground_height(global_position.x, global_position.z)
	):
		detonate()

func _update_mass_and_motor_state() -> void:
	motor_burning = time_alive < flight_config.motor_burn_time_s
	booster_attached = motor_burning
	booster_jettisoned = !booster_attached
	var burn_fraction = clampf(time_alive / maxf(flight_config.motor_burn_time_s, 0.01), 0.0, 1.0)
	current_mass_kg = lerpf(flight_config.launch_mass_kg, flight_config.final_mass_kg(), burn_fraction)

func _update_fin_actuators(
	delta: float,
	basis: Basis,
	air_velocity_world: Vector3,
	aerodynamic_alpha: float,
	aerodynamic_beta: float
) -> void:
	current_control_gain = flight_config.control_gain_at_time(time_alive)
	# timeToGain belongs to lineOfSightAutopilot: schedule the external
	# guidance demand, not passive stability or gravity compensation.
	var desired_acceleration = (
		_commanded_normal_acceleration * current_control_gain
		if _guidance_command_valid
		else Vector3.ZERO
	)
	if air_velocity_world.length_squared() > EPSILON:
		var flight_direction = air_velocity_world.normalized()
		desired_acceleration -= flight_direction * desired_acceleration.dot(flight_direction)
		# Guidance commands inertial normal acceleration. While guidance is
		# present, the autopilot must also generate the normal force that cancels
		# gravity; otherwise a zero command would make a level flight path sag.
		if _guidance_command_valid:
			var gravity = Vector3.DOWN * STANDARD_GRAVITY_MPS2
			var normal_gravity = gravity - flight_direction * gravity.dot(flight_direction)
			desired_acceleration -= normal_gravity
	desired_acceleration = desired_acceleration.limit_length(
		flight_config.maximum_load_factor_g * STANDARD_GRAVITY_MPS2
	)
	var command_blend = 1.0 - exp(-delta / maxf(flight_config.autopilot_time_constant_s, 0.01))
	_filtered_normal_acceleration = _filtered_normal_acceleration.lerp(desired_acceleration, command_blend)

	var desired_body_acceleration = basis.inverse() * _filtered_normal_acceleration
	var fin_effectiveness = flight_config.fin_effectiveness_multiplier()
	var effective_fin_moment = maxf(
		flight_config.fin_moment_coefficient_per_rad * fin_effectiveness,
		0.01
	)
	var equilibrium_fin_ratio = (
		flight_config.static_moment_coefficient_per_rad
		/ effective_fin_moment
	)
	var effective_normal_slope = (
		flight_config.static_normal_coefficient_per_rad
		+ flight_config.fin_normal_coefficient_per_rad * fin_effectiveness * equilibrium_fin_ratio
	)
	var angle_limit = deg_to_rad(flight_config.maximum_angle_of_attack_deg)
	var requested_angle_plane = Vector2(
		-desired_body_acceleration.x,
		desired_body_acceleration.y
	)
	var requested_normal_force = requested_angle_plane.length() * current_mass_kg
	var aero_force_per_angle = (
		current_dynamic_pressure_pa
		* flight_config.normal_reference_area_m2()
		* effective_normal_slope
	)
	var thrust_force = flight_config.thrust_newtons if motor_burning else 0.0
	var desired_angle_magnitude = _solve_required_control_angle(
		requested_normal_force,
		aero_force_per_angle,
		thrust_force,
		angle_limit
	)
	var desired_angles = Vector2.ZERO
	if requested_angle_plane.length_squared() > EPSILON:
		desired_angles = requested_angle_plane.normalized() * desired_angle_magnitude
	var desired_beta = desired_angles.x
	var desired_alpha = desired_angles.y

	var target_pitch_fin = (
		equilibrium_fin_ratio * desired_alpha
		+ flight_config.autopilot_angle_gain * (desired_alpha - aerodynamic_alpha)
		- flight_config.autopilot_rate_gain_s * body_angular_velocity_rad_s.x
	)
	var target_yaw_fin = (
		equilibrium_fin_ratio * desired_beta
		+ flight_config.autopilot_angle_gain * (desired_beta - aerodynamic_beta)
		- flight_config.autopilot_rate_gain_s * body_angular_velocity_rad_s.y
	)
	pitch_fin_deflection_rad = _step_fin_actuator(
		pitch_fin_deflection_rad,
		target_pitch_fin,
		flight_config.maximum_vertical_fin_deflection_rad(),
		delta
	)
	yaw_fin_deflection_rad = _step_fin_actuator(
		yaw_fin_deflection_rad,
		target_yaw_fin,
		flight_config.maximum_horizontal_fin_deflection_rad(),
		delta
	)

func _solve_required_control_angle(
	required_normal_force: float,
	aero_force_per_angle: float,
	thrust_force: float,
	angle_limit: float
) -> float:
	if required_normal_force <= EPSILON:
		return 0.0
	# Solve q*S*CNa*angle + thrust*sin(angle) = required force. This is
	# the actual boost-phase normal component of thrust, not an added lift
	# coefficient. Four Newton iterations are ample inside the 20-degree limit.
	var angle = clampf(
		required_normal_force / maxf(aero_force_per_angle + thrust_force, EPSILON),
		0.0,
		angle_limit
	)
	for iteration in range(4):
		var residual = aero_force_per_angle * angle + thrust_force * sin(angle) - required_normal_force
		var derivative = aero_force_per_angle + thrust_force * cos(angle)
		if derivative <= EPSILON:
			break
		angle = clampf(angle - residual / derivative, 0.0, angle_limit)
	return angle

func _step_fin_actuator(current: float, target: float, limit: float, delta: float) -> float:
	target = clampf(target, -limit, limit)
	var requested_rate = (target - current) / maxf(flight_config.fin_actuator_time_constant_s, 0.001)
	var maximum_rate = deg_to_rad(flight_config.maximum_fin_rate_deg_s)
	var actual_rate = clampf(requested_rate, -maximum_rate, maximum_rate)
	return clampf(current + actual_rate * delta, -limit, limit)

func _calculate_aerodynamic_torque_body(
	airspeed: float,
	aerodynamic_alpha: float,
	aerodynamic_beta: float,
	dynamic_pressure: float,
	reference_area: float
) -> Vector3:
	if airspeed <= EPSILON or dynamic_pressure <= EPSILON:
		return Vector3.ZERO
	var length = flight_config.body_length_m
	var fin_effectiveness = flight_config.fin_effectiveness_multiplier()
	var nondimensional_rate_scale = length / (2.0 * airspeed)
	var pitch_moment_coefficient = (
		-flight_config.static_moment_coefficient_per_rad * aerodynamic_alpha
		+ flight_config.fin_moment_coefficient_per_rad * fin_effectiveness * pitch_fin_deflection_rad
		- flight_config.pitch_yaw_damping_coefficient
			* body_angular_velocity_rad_s.x * nondimensional_rate_scale
	)
	var yaw_moment_coefficient = (
		-flight_config.static_moment_coefficient_per_rad * aerodynamic_beta
		+ flight_config.fin_moment_coefficient_per_rad * fin_effectiveness * yaw_fin_deflection_rad
		- flight_config.pitch_yaw_damping_coefficient
			* body_angular_velocity_rad_s.y * nondimensional_rate_scale
	)
	var roll_moment_coefficient = (
		-flight_config.roll_damping_coefficient
		* body_angular_velocity_rad_s.z * nondimensional_rate_scale
	)
	return Vector3(
		pitch_moment_coefficient,
		yaw_moment_coefficient,
		roll_moment_coefficient
	) * (dynamic_pressure * reference_area * length)

func _integrate_rotation(torque_body: Vector3, delta: float) -> void:
	var radius = (flight_config.booster_caliber_m if booster_attached else flight_config.body_caliber_m) * 0.5
	var length = flight_config.assembled_length_m if booster_attached else flight_config.body_length_m
	var transverse_inertia = current_mass_kg * (length * length / 12.0 + radius * radius * 0.25)
	var roll_inertia = maxf(
		0.5 * current_mass_kg * radius * radius,
		flight_config.minimum_roll_inertia_kg_m2
	)
	var inertia = Vector3(transverse_inertia, transverse_inertia, roll_inertia)
	var angular_momentum = Vector3(
		inertia.x * body_angular_velocity_rad_s.x,
		inertia.y * body_angular_velocity_rad_s.y,
		inertia.z * body_angular_velocity_rad_s.z
	)
	var net_torque = torque_body - body_angular_velocity_rad_s.cross(angular_momentum)
	body_angular_acceleration_rad_s2 = Vector3(
		net_torque.x / maxf(inertia.x, EPSILON),
		net_torque.y / maxf(inertia.y, EPSILON),
		net_torque.z / maxf(inertia.z, EPSILON)
	)
	body_angular_velocity_rad_s += body_angular_acceleration_rad_s2 * delta
	body_angular_velocity_rad_s = body_angular_velocity_rad_s.limit_length(
		deg_to_rad(flight_config.maximum_body_rate_deg_s)
	)
	if !body_angular_velocity_rad_s.is_finite():
		body_angular_velocity_rad_s = Vector3.ZERO
		body_angular_acceleration_rad_s2 = Vector3.ZERO
		return
	var rotation_angle = body_angular_velocity_rad_s.length() * delta
	if rotation_angle <= EPSILON:
		return
	var rotation_axis_body = body_angular_velocity_rad_s.normalized()
	var transform = global_transform
	transform.basis = (transform.basis * Basis(rotation_axis_body, rotation_angle)).orthonormalized()
	global_transform = transform

func update_guidance_acceleration(normal_acceleration_mps2: Vector3, mode: String = "ТТ") -> void:
	if !normal_acceleration_mps2.is_finite():
		return
	_commanded_normal_acceleration = normal_acceleration_mps2
	_guidance_command_valid = true
	guidance_mode = mode

func update_guidance_command(target_direction: Vector3) -> void:
	# Compatibility adapter for older callers. The 6DOF autopilot receives an
	# acceleration demand and realizes it through fin forces and body moments.
	if target_direction.length_squared() <= EPSILON:
		return
	var speed = maxf(velocity.length(), flight_config.launch_speed_mps)
	var desired_velocity = target_direction.normalized() * speed
	var forward = velocity.normalized()
	var velocity_error = desired_velocity - velocity
	if forward.length_squared() > EPSILON:
		velocity_error -= forward * velocity_error.dot(forward)
	update_guidance_acceleration(
		velocity_error / maxf(flight_config.autopilot_time_constant_s, 0.05),
		guidance_mode
	)

func clear_guidance_command() -> void:
	_guidance_command_valid = false
	_commanded_normal_acceleration = Vector3.ZERO

func body_forward_direction() -> Vector3:
	return -global_transform.basis.z.normalized()

func set_fuze_target(target: Node3D) -> void:
	_fuze_target = target
	_have_fuze_history = is_instance_valid(target)
	_previous_missile_position = global_position
	if _have_fuze_history:
		_previous_target_position = target.global_position

func has_fuze_target() -> bool:
	return is_instance_valid(_fuze_target)

func _check_continuous_proximity_fuze(start_position: Vector3) -> void:
	# A command-detonated missile has no fuze; the complex triggers it.
	if flight_config.uses_command_detonation():
		return
	if !is_instance_valid(_fuze_target):
		_fuze_target = null
		_have_fuze_history = false
		return
	var target_position = _fuze_target.global_position
	if _have_fuze_history and distance_travelled_m >= flight_config.fuze_arm_distance_m:
		var relative_start = _previous_missile_position - _previous_target_position
		var relative_end = global_position - target_position
		var closest_distance = MissileGuidance.closest_approach_distance(relative_start, relative_end)
		if closest_distance <= flight_config.proximity_fuze_radius_m:
			detonate()
	_previous_missile_position = global_position if is_active else start_position
	_previous_target_position = target_position
	_have_fuze_history = true

func atmospheric_density(altitude_m: float) -> float:
	return SEA_LEVEL_DENSITY_KG_M3 * exp(-maxf(altitude_m, 0.0) / flight_config.atmosphere_scale_height_m)

func local_speed_of_sound(altitude_m: float) -> float:
	var temperature = maxf(
		SEA_LEVEL_TEMPERATURE_K - TEMPERATURE_LAPSE_K_M * maxf(altitude_m, 0.0),
		MIN_TEMPERATURE_K
	)
	return sqrt(GAS_HEAT_RATIO * AIR_GAS_CONSTANT * temperature)

func drag_coefficient(mach: float) -> float:
	if booster_attached:
		return flight_config.boost_drag_coefficient * flight_config.drag_coefficient_multiplier
	var base_coefficient: float
	if mach < 0.8:
		base_coefficient = lerpf(0.14, 0.16, mach / 0.8)
	elif mach < 1.05:
		base_coefficient = lerpf(0.16, 0.32, (mach - 0.8) / 0.25)
	elif mach < 1.5:
		base_coefficient = lerpf(0.32, 0.22, (mach - 1.05) / 0.45)
	elif mach < 2.2:
		base_coefficient = lerpf(0.22, 0.16, (mach - 1.5) / 0.7)
	elif mach < 3.5:
		base_coefficient = lerpf(0.16, 0.22, (mach - 2.2) / 1.3)
	else:
		base_coefficient = 0.22
	return (
		base_coefficient
		* flight_config.drag_coefficient_multiplier
		* flight_config.sustainer_drag_calibration
	)

func detonate() -> void:
	if _detonation_started:
		return
	_detonation_started = true
	is_active = false
	set_physics_process(false)
	if is_inside_tree() and create_flight_visuals:
		_create_explosion_visual()
	if is_inside_tree():
		for target in get_tree().get_nodes_in_group("radar_targets"):
			if !is_instance_valid(target) or !target.has_method("take_damage"):
				continue
			if global_position.distance_to(target.global_position) <= flight_config.warhead_effect_radius_m or _fragments_hit(target):
				# Preserve the simulator's existing 90% critical-hit damage model.
				target.take_damage(randf() <= 0.9)
		queue_free()

# Detonation command from the complex (missiles without their own fuze).
func command_detonate() -> void:
	if distance_travelled_m >= flight_config.fuze_arm_distance_m:
		detonate()

# Fragments fly out in cones around the missile's direction of motion
# relative to the target. Hits on the target's vulnerable area follow a
# Poisson law: the cone's fragments per steradian spread over d².
func _fragments_hit(target: Node3D) -> bool:
	if flight_config.warhead_fragment_count <= 0:
		return false
	var offset = target.global_position - global_position
	var distance = offset.length()
	if distance > flight_config.warhead_fragment_radius_m:
		return false
	if distance < 0.5:
		return true
	var target_velocity: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
	var axis = velocity - target_velocity
	if axis.length_squared() <= EPSILON:
		axis = body_forward_direction()
	var angle_deg = rad_to_deg(acos(clampf(axis.normalized().dot(offset / distance), -1.0, 1.0)))
	var area = float(target.vulnerable_area_m2) if "vulnerable_area_m2" in target else DEFAULT_VULNERABLE_AREA_M2
	var expected_hits = flight_config.fragment_density_per_sr(angle_deg) * area / (distance * distance)
	return randf() < 1.0 - exp(-expected_hits)

func _create_explosion_visual() -> void:
	var explosion = GPUParticles3D.new()
	explosion.one_shot = true
	explosion.emitting = true
	explosion.amount = 20
	explosion.lifetime = 0.3
	explosion.explosiveness = 1.0
	explosion.layers = 1
	var particle_material = StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.albedo_color = Color(5.0, 5.0, 5.0)
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = particle_material
	explosion.draw_pass_1 = quad
	var process_material = ParticleProcessMaterial.new()
	process_material.gravity = Vector3.ZERO
	process_material.spread = 180.0
	process_material.initial_velocity_min = 5.0
	process_material.initial_velocity_max = 10.0
	explosion.process_material = process_material
	get_parent().add_child(explosion)
	explosion.global_position = global_position

func explode() -> void:
	detonate()
