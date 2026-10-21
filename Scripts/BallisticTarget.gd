extends CharacterBody3D

var radar_id: int = 0
# МРЛС signature recognition result.
# On real recordings the МРЛС reads a ballistic rocket as САМ, sometimes jumping to ВЕРТ.
var signature_class: String = "САМ"
# Radar cross-section, m² (227 mm rocket): nose-on and broadside.
# Detection ranges of both radars follow from it.
var rcs_nose_m2: float = 0.03
var rcs_side_m2: float = 0.5

var speed: float = 700.0 
var gravity: float = 9.8
var damage_radius: float = 20.0

var flight_time: float = 0.0
var max_lifetime: float = 120.0

var smoke_particles: GPUParticles3D
var explosion_particles: GPUParticles3D

var destroyed: bool = false
var active: bool = true

func _ready():
	radar_id = GlobalPantsirSystem.get_new_uid()
	add_to_group("radar_targets")
	
	setup_visuals()
	setup_effects()

func init_ballistics(start_pos: Vector3, target_pos: Vector3, flight_duration: float):
	global_position = start_pos
	
	var gravity_vec = Vector3(0, -gravity, 0)
	var displacement = target_pos - start_pos
	
	var velocity_vector = (displacement - (0.5 * gravity_vec * pow(flight_duration, 2))) / flight_duration
	
	velocity = velocity_vector
	look_at(global_position + velocity, Vector3.UP)

func _physics_process(delta):
	if !active: return
	
	flight_time += delta
	if flight_time > max_lifetime:
		queue_free()
		return
	
	velocity.y -= gravity * delta
	
	if velocity.length() > 1.0:
		look_at(global_position + velocity, Vector3.UP)
	
	var collision = move_and_collide(velocity * delta)
	# Impact is also checked by height, in case a step skips the ground collider.
	if collision or global_position.y <= GlobalPantsirSystem.get_ground_height(global_position.x, global_position.z):
		explode()

func setup_visuals():
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.11 
	cyl.bottom_radius = 0.11
	cyl.height = 3.9
	
	mesh_inst.mesh = cyl
	mesh_inst.rotation.x = PI / 2
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.layers = 1 
	add_child(mesh_inst)
	
	var thermal_mat = StandardMaterial3D.new()
	thermal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	thermal_mat.albedo_color = Color(3.0, 3.0, 3.0)
	thermal_mat.emission_enabled = true
	thermal_mat.emission = Color(1.0, 1.0, 1.0)
	thermal_mat.emission_energy_multiplier = 8.0
	mesh_inst.material_override = thermal_mat

func setup_effects():
	var part_mat = StandardMaterial3D.new()
	part_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	part_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	part_mat.vertex_color_use_as_albedo = true
	part_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	
	smoke_particles = GPUParticles3D.new()
	smoke_particles.amount = 100
	smoke_particles.lifetime = 1.5
	smoke_particles.explosiveness = 0.0
	smoke_particles.layers = 1
	smoke_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var quad = QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	quad.material = part_mat
	smoke_particles.draw_pass_1 = quad
	
	var proc = ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 0, 1) 
	proc.spread = 5.0
	proc.initial_velocity_min = 5.0
	proc.initial_velocity_max = 10.0
	proc.gravity = Vector3.ZERO
	proc.scale_min = 1.0
	proc.scale_max = 3.0
	proc.color = Color(1, 1, 1, 0.5)
	smoke_particles.process_material = proc
	smoke_particles.position = Vector3(0, 0, 2.0) 
	
	add_child(smoke_particles)

func take_damage(is_critical: bool):
	if is_critical:
		active = false
		explode()

func explode():
	active = false
	var boom = GPUParticles3D.new()
	boom.one_shot = true
	boom.emitting = true
	boom.amount = 30
	boom.lifetime = 0.5
	boom.explosiveness = 1.0
	boom.layers = 1
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(5.0, 3.0, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	
	var quad = QuadMesh.new()
	quad.size = Vector2(3, 3)
	quad.material = mat
	boom.draw_pass_1 = quad
	
	var proc = ParticleProcessMaterial.new()
	proc.gravity = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 10.0
	proc.initial_velocity_max = 20.0
	boom.process_material = proc
	
	get_parent().add_child(boom)
	boom.global_position = global_position
	
	queue_free()
