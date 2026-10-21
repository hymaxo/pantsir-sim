extends Node3D

@onready var los_ray = $LosRay

var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.05
const ANTENNA_HEIGHT_M: float = 6.0
# Farthest range either radar processes echoes from.
const INSTRUMENTED_RANGE_M: float = 45000.0
# Foliage loss changes slowly; the path through the forest is re-traced at
# this interval per target instead of on every radar tick.
const FOLIAGE_UPDATE_INTERVAL_S: float = 0.25

var _foliage_factors: Dictionary = {}

func _ready():
	GlobalPantsirSystem.targets.clear()
	if !los_ray:
		var ray = RayCast3D.new()
		ray.name = "LosRay"
		add_child(ray)
		los_ray = ray

# Mean radar cross-section for the current aspect: smallest nose- or tail-on,
# largest broadside. 0 means the target has no RCS data (always detected).
func _aspect_rcs(body: Node3D, radar_pos: Vector3) -> float:
	if !("rcs_nose_m2" in body):
		return 0.0
	var heading: Vector3 = body.velocity if body.velocity.length() > 1.0 else -body.global_transform.basis.z
	var to_radar = radar_pos - body.global_position
	if heading.length() < 0.001 or to_radar.length() < 0.001:
		return body.rcs_nose_m2
	var sin_aspect = heading.normalized().cross(to_radar.normalized()).length()
	return lerpf(body.rcs_nose_m2, body.rcs_side_m2, sin_aspect * sin_aspect)

func _physics_process(delta):
	update_timer += delta
	if update_timer < UPDATE_INTERVAL:
		return
	update_timer = 0.0

	var my_pos = global_position
	GlobalPantsirSystem.pantsir_position = my_pos
	var antenna_pos = my_pos + Vector3(0, ANTENNA_HEIGHT_M, 0)
	var now = GlobalPantsirSystem.get_simulation_time_s()

	var found_targets = []
	var seen_ids = {}
	var nodes = get_tree().get_nodes_in_group("radar_targets")

	for body in nodes:
		var t_pos = body.global_position
		var dist = my_pos.distance_to(t_pos)

		# Instrumented range; whether a target is actually detected inside it
		# is decided per antenna pass from its reference range.
		if dist > INSTRUMENTED_RANGE_M:
			continue

		# Hills mask the target: the ray is blocked by the terrain collider.
		los_ray.global_position = antenna_pos
		los_ray.target_position = los_ray.to_local(t_pos)
		los_ray.force_raycast_update()

		if los_ray.is_colliding():
			if los_ray.get_collider() != body:
				continue

		seen_ids[body.radar_id] = true
		var foliage = _foliage_factors.get(body.radar_id, {})
		if foliage.is_empty() or now >= float(foliage["next_update_s"]):
			foliage = {
				"factor": GlobalPantsirSystem.get_radar_range_factor(antenna_pos, t_pos),
				"next_update_s": now + FOLIAGE_UPDATE_INTERVAL_S,
			}
			_foliage_factors[body.radar_id] = foliage
		# Trees absorb the signal and shorten every detection range.
		var range_factor: float = foliage["factor"]

		var t_data = {
			"id": body.radar_id,
			"position": t_pos,
			"velocity": body.velocity,
			# The consumer may run before this scene node on the next radar tick.
			# Preserve capture time so that old coordinates are never stamped as new.
			"measurement_timestamp": now,
			"is_threat": (body.velocity.length() > 50 or body.critical_hit == false),
			"signature_class": body.signature_class if "signature_class" in body else "",
			# A critically hit target keeps flying as falling wreckage until it
			# reaches the ground; the radar sees that it is no longer a threat.
			"killed": body.critical_hit if "critical_hit" in body else false,
			"rcs_m2": _aspect_rcs(body, my_pos),
			"radar_range_factor": range_factor,
		}
		found_targets.append(t_data)

	for id in _foliage_factors.keys():
		if !seen_ids.has(id):
			_foliage_factors.erase(id)

	GlobalPantsirSystem.targets = found_targets
