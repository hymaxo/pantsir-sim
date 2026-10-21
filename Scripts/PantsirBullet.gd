extends Node3D

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 9.8
var time_alive: float = 0.0
var max_lifetime: float = 5.0

const HIT_RADIUS_M: float = 5.0
# Chance that one 30 mm hit destroys the target; the rest only damage it.
const HIT_KILL_PROBABILITY: float = 0.2

func init_bullet(muzzle_vel: float):
	velocity = -global_transform.basis.z * muzzle_vel
	create_visuals()

func create_visuals():
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 2.0
	
	sphere.material = mat
	mesh_inst.mesh = sphere
	add_child(mesh_inst)

func _physics_process(delta):
	time_alive += delta
	if time_alive > max_lifetime:
		queue_free()
		return
	
	velocity.y -= gravity * delta
	
	var step = velocity * delta
	global_position += step
	
	check_collision(step)

# A shell covers ~5 m per physics tick, so the hit test uses the whole segment
# flown this tick instead of only its end point.
func check_collision(step_vec: Vector3):
	var segment_start = global_position - step_vec
	var targets = get_tree().get_nodes_in_group("radar_targets")
	for t in targets:
		var closest = Geometry3D.get_closest_point_to_segment(t.global_position, segment_start, global_position)
		if closest.distance_to(t.global_position) < HIT_RADIUS_M:
			if t.has_method("take_damage"):
				t.take_damage(randf() < HIT_KILL_PROBABILITY)

			queue_free()
			return
