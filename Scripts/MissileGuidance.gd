extends RefCounted
class_name MissileGuidance

const EPSILON: float = 0.000001

static func select_mode_with_hysteresis(current_mode: String, los_rate: float, switch_to_ps: float, switch_to_tt: float) -> String:
	if current_mode == "ТТ" and los_rate >= switch_to_ps:
		return "ПС"
	if current_mode == "ПС" and los_rate <= switch_to_tt:
		return "ТТ"
	return current_mode

static func closest_approach_distance(relative_start: Vector3, relative_end: Vector3) -> float:
	var segment = relative_end - relative_start
	var segment_length_squared = segment.length_squared()
	if segment_length_squared <= EPSILON:
		return relative_start.length()
	var fraction = clampf(-relative_start.dot(segment) / segment_length_squared, 0.0, 1.0)
	return (relative_start + segment * fraction).length()

static func line_of_sight_rate(origin: Vector3, target_position: Vector3, target_velocity: Vector3) -> float:
	var relative_position = target_position - origin
	var range_squared = relative_position.length_squared()
	if range_squared <= EPSILON:
		return 0.0
	return relative_position.cross(target_velocity).length() / range_squared

static func smooth_loft_height(range_to_target: float, maximum_height: float, fade_range: float) -> float:
	if maximum_height <= 0.0 or fade_range <= EPSILON:
		return 0.0
	var x = clampf(range_to_target / fade_range, 0.0, 1.0)
	var smooth_x = x * x * (3.0 - 2.0 * x)
	return maximum_height * smooth_x

static func three_point_acceleration(
	origin: Vector3,
	missile_position: Vector3,
	missile_velocity: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	loft_height: float,
	position_gain_s2: float,
	velocity_gain_s: float
) -> Vector3:
	var aiming_point = target_position + Vector3.UP * loft_height
	var sight_line = aiming_point - origin
	var sight_range = sight_line.length()
	if sight_range <= EPSILON:
		return Vector3.ZERO
	var sight_direction = sight_line / sight_range
	var missile_from_origin = missile_position - origin
	var along_line = clampf(missile_from_origin.dot(sight_direction), 0.0, sight_range)
	var line_fraction = along_line / sight_range
	var point_on_line = origin + sight_direction * along_line
	var position_error = point_on_line - missile_position
	var line_point_velocity = target_velocity * line_fraction
	var velocity_error = line_point_velocity - missile_velocity
	velocity_error -= sight_direction * velocity_error.dot(sight_direction)
	var command = position_error * position_gain_s2 + velocity_error * velocity_gain_s
	var forward = missile_velocity.normalized()
	if forward.length_squared() > EPSILON:
		command -= forward * command.dot(forward)
	return command

static func intercept_time(relative_position: Vector3, target_velocity: Vector3, missile_speed: float, maximum_time: float = 60.0) -> float:
	if missile_speed <= EPSILON:
		return -1.0
	var a = target_velocity.length_squared() - missile_speed * missile_speed
	var b = 2.0 * relative_position.dot(target_velocity)
	var c = relative_position.length_squared()
	var result = -1.0
	if absf(a) <= EPSILON:
		if absf(b) > EPSILON:
			var linear_time = -c / b
			if linear_time > EPSILON:
				result = linear_time
	else:
		var discriminant = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root = sqrt(discriminant)
			var t1 = (-b - root) / (2.0 * a)
			var t2 = (-b + root) / (2.0 * a)
			if t1 > EPSILON:
				result = t1
			if t2 > EPSILON and (result < 0.0 or t2 < result):
				result = t2
	if !is_finite(result) or result <= 0.0 or result > maximum_time:
		return -1.0
	return result

static func half_straightening_acceleration(
	missile_position: Vector3,
	missile_velocity: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	autopilot_time_constant_s: float
) -> Vector3:
	var relative_position = target_position - missile_position
	var speed = missile_velocity.length()
	var time_to_intercept = intercept_time(relative_position, target_velocity, speed)
	var aiming_point = target_position
	if time_to_intercept > 0.0:
		aiming_point += target_velocity * time_to_intercept
	var desired_direction = (aiming_point - missile_position).normalized()
	var current_direction = missile_velocity.normalized()
	if desired_direction.length_squared() <= EPSILON or current_direction.length_squared() <= EPSILON:
		return Vector3.ZERO
	# A bad root must never order a 180 degree reversal. Falling back to the
	# current line of sight gives a bounded, forward command.
	if current_direction.dot(desired_direction) < -0.2:
		desired_direction = relative_position.normalized()
		if current_direction.dot(desired_direction) < -0.2:
			return Vector3.ZERO
	var desired_velocity = desired_direction * speed
	var velocity_error = desired_velocity - missile_velocity
	velocity_error -= current_direction * velocity_error.dot(current_direction)
	return velocity_error / maxf(autopilot_time_constant_s, 0.05)
