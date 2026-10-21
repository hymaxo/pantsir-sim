extends RefCounted
class_name KalmanTrack3D

# Three independent, identically tuned constant-velocity Kalman filters.
# Position and velocity are Vector3 states; the four scalar covariance terms
# apply to every axis because the radar error model is isotropic.
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var position_variance: float = 1.0
var position_velocity_covariance: float = 0.0
var velocity_position_covariance: float = 0.0
var velocity_variance: float = 1.0
var last_position_gain: float = 0.0
var last_velocity_gain: float = 0.0
var last_innovation: Vector3 = Vector3.ZERO
var initialized: bool = false

func initialize(
	measured_position: Vector3,
	initial_velocity: Vector3,
	measurement_variance: float,
	initial_velocity_variance: float
) -> void:
	position = measured_position
	velocity = initial_velocity
	position_variance = maxf(measurement_variance, 0.000001)
	position_velocity_covariance = 0.0
	velocity_position_covariance = 0.0
	velocity_variance = maxf(initial_velocity_variance, 0.000001)
	last_position_gain = 0.0
	last_velocity_gain = 0.0
	last_innovation = Vector3.ZERO
	initialized = true

func update(
	measured_position: Vector3,
	delta: float,
	measurement_variance: float,
	acceleration_sigma_mps2: float
) -> void:
	if !initialized:
		initialize(measured_position, Vector3.ZERO, measurement_variance, acceleration_sigma_mps2 * acceleration_sigma_mps2)
		return
	var dt = maxf(delta, 0.000001)
	var acceleration_variance = acceleration_sigma_mps2 * acceleration_sigma_mps2
	var dt2 = dt * dt
	var dt3 = dt2 * dt
	var dt4 = dt2 * dt2

	# Predict x(k|k-1) = F x(k-1|k-1), F = [[1, dt], [0, 1]].
	position += velocity * dt
	var predicted_p00 = (
		position_variance
		+ dt * (position_velocity_covariance + velocity_position_covariance)
		+ dt2 * velocity_variance
		+ 0.25 * dt4 * acceleration_variance
	)
	var predicted_p01 = position_velocity_covariance + dt * velocity_variance + 0.5 * dt3 * acceleration_variance
	var predicted_p10 = velocity_position_covariance + dt * velocity_variance + 0.5 * dt3 * acceleration_variance
	var predicted_p11 = velocity_variance + dt2 * acceleration_variance

	# Correct with a position-only radar measurement H = [1, 0].
	var innovation_variance = maxf(predicted_p00 + measurement_variance, 0.000001)
	last_position_gain = clampf(predicted_p00 / innovation_variance, 0.0, 1.0)
	last_velocity_gain = predicted_p10 / innovation_variance
	last_innovation = measured_position - position
	position += last_innovation * last_position_gain
	velocity += last_innovation * last_velocity_gain

	position_variance = maxf((1.0 - last_position_gain) * predicted_p00, 0.000001)
	position_velocity_covariance = (1.0 - last_position_gain) * predicted_p01
	velocity_position_covariance = predicted_p10 - last_velocity_gain * predicted_p00
	velocity_variance = maxf(predicted_p11 - last_velocity_gain * predicted_p01, 0.000001)
	# Numerical roundoff can make the theoretically symmetric terms differ.
	var symmetric_covariance = 0.5 * (position_velocity_covariance + velocity_position_covariance)
	position_velocity_covariance = symmetric_covariance
	velocity_position_covariance = symmetric_covariance

func predicted_position(delta: float) -> Vector3:
	return position + velocity * maxf(delta, 0.0)
