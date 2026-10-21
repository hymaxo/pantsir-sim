extends CharacterBody3D

var radar_id: int = 0
# МРЛС signature recognition result.
var signature_class: String = "САМ"
# Radar cross-section, m² (fighter-size aircraft): nose-on and broadside.
# Detection ranges of both radars follow from it.
var rcs_nose_m2: float = 3.0
var rcs_side_m2: float = 15.0

var speed = 150.0
var radius = 1000.0
var angle = 0.0

var critical_hit: bool = false
var hit: bool = false
var destroyed: bool = false
var can_be_destroyed: bool = true

var fall_gravity: float = 9.8
var vertical_speed: float = 0.0

var smoke_particles: GPUParticles3D
var explosion_particles: GPUParticles3D

func _ready():
	radar_id = GlobalPantsirSystem.get_new_uid()
	
	add_to_group("radar_targets")
	
	if position.length() > 10.0:
		radius = position.length()
		angle = atan2(position.x, position.z)
	else:
		position = Vector3(0, 500, 1000)
		radius = 1000.0
		angle = 0.0

	setup_visuals()
	setup_effects()

func setup_visuals():
	var thermal_mat = StandardMaterial3D.new()
	thermal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	thermal_mat.albedo_color = Color(2.0, 2.0, 2.0)
	thermal_mat.emission_enabled = true
	thermal_mat.emission = Color(1.0, 1.0, 1.0)
	thermal_mat.emission_energy_multiplier = 5.0
	
	var meshes = find_all_mesh_instances(self)
	
	if meshes.is_empty():
		var test_mesh = MeshInstance3D.new()
		test_mesh.mesh = BoxMesh.new()
		test_mesh.mesh.size = Vector3(5, 5, 5)
		test_mesh.name = "DebugThermalMesh"
		add_child(test_mesh)
		meshes.append(test_mesh)
	
	for mi in meshes:
		mi.material_override = thermal_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 
		mi.visible = true 

func setup_effects():
	var part_mat = StandardMaterial3D.new()
	part_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_mat.albedo_color = Color(1.5, 1.5, 1.5) 
	part_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	part_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	
	smoke_particles = GPUParticles3D.new()
	smoke_particles.emitting = false
	smoke_particles.amount = 64
	smoke_particles.lifetime = 3.0
	smoke_particles.one_shot = false
	smoke_particles.explosiveness = 0.0
	smoke_particles.layers = 1
	smoke_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var smoke_quad = QuadMesh.new()
	smoke_quad.size = Vector2(2, 2)
	smoke_quad.material = part_mat
	smoke_particles.draw_pass_1 = smoke_quad
	
	var smoke_proc = ParticleProcessMaterial.new()
	smoke_proc.direction = Vector3(0, 1, 0)
	smoke_proc.gravity = Vector3(0, 2, 0) 
	smoke_proc.initial_velocity_min = 2.0
	smoke_proc.initial_velocity_max = 5.0
	smoke_proc.scale_min = 1.0
	smoke_proc.scale_max = 5.0
	smoke_particles.process_material = smoke_proc
	
	add_child(smoke_particles)
	
	explosion_particles = GPUParticles3D.new()
	explosion_particles.emitting = false
	explosion_particles.amount = 40
	explosion_particles.lifetime = 0.8
	explosion_particles.one_shot = true
	explosion_particles.explosiveness = 1.0
	explosion_particles.layers = 1
	explosion_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var exp_quad = QuadMesh.new()
	exp_quad.size = Vector2(4, 4)
	exp_quad.material = part_mat
	explosion_particles.draw_pass_1 = exp_quad
	
	var exp_proc = ParticleProcessMaterial.new()
	exp_proc.direction = Vector3(0, 1, 0)
	exp_proc.spread = 180.0
	exp_proc.initial_velocity_min = 10.0
	exp_proc.initial_velocity_max = 25.0
	exp_proc.gravity = Vector3.ZERO
	exp_proc.scale_min = 2.0
	exp_proc.scale_max = 8.0
	explosion_particles.process_material = exp_proc
	
	add_child(explosion_particles)

func find_all_mesh_instances(node: Node) -> Array:
	var list = []
	if node is MeshInstance3D:
		list.append(node)
	for child in node.get_children():
		list.append_array(find_all_mesh_instances(child))
	return list

func _physics_process(delta):
	if critical_hit:
		process_falling(delta)
	else:
		process_circling(delta)

func process_circling(delta):
	angle += (speed / radius) * delta
	var x = sin(angle) * radius
	var z = cos(angle) * radius
	var target_pos = Vector3(x, position.y, z)
	
	if position.distance_to(target_pos) > 0.1:
		var direction = (target_pos - position).normalized()
		velocity = direction * speed
		look_at(global_position + velocity, Vector3.UP)
	
	move_and_slide()

func process_falling(delta):
	vertical_speed += fall_gravity * delta
	velocity.y -= vertical_speed * delta
	
	velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 10.0 * delta)
	
	if velocity.length() > 1.0:
		look_at(global_position + velocity, Vector3.UP)
	
	move_and_slide()
	
	if global_position.y <= GlobalPantsirSystem.get_ground_height(global_position.x, global_position.z):
		queue_free()

func take_damage(is_critical: bool):
	hit = true
	if smoke_particles:
		smoke_particles.emitting = true
	
	if is_critical and not critical_hit:
		critical_hit = true
		if explosion_particles:
			explosion_particles.restart()
			explosion_particles.emitting = true
