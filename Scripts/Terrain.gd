extends Node3D

# Procedural ground: noise hills, an open field around the vehicle and forest
# beyond it. Provides ground height and the foliage loss on radar paths.
# The vehicle stands at the origin.

@export var terrain_seed: int = 0 # 0 picks a random seed each session.
# 80 × 80 km map centred on the vehicle.
@export var half_size_m: float = 40000.0
@export var height_cell_m: float = 150.0
@export var hill_height_m: float = 70.0
@export var hill_wavelength_m: float = 6000.0
# Open field around the vehicle: flat and free of trees.
@export var field_radius_m: float = 2500.0
@export var field_blend_m: float = 1500.0

@export_group("Forest")
@export var forest_cell_m: float = 50.0
@export var forest_wavelength_m: float = 3500.0
# Share of the area outside the field covered by forest.
@export_range(0.0, 1.0) var forest_coverage: float = 0.45
@export var canopy_height_m: float = 22.0
# Trees are only instanced near the vehicle; the forest mask covers the map.
@export var tree_visible_radius_m: float = 3500.0
@export var tree_spacing_m: float = 22.0

@export_group("Radar")
# Two-way loss of a radar path through foliage. Range falls with the fourth
# root of the power loss, so 40 dB cuts detection range tenfold.
@export var foliage_loss_db_per_m: float = 0.15
# The sparse top of the crowns attenuates less than the dense lower canopy.
@export var canopy_top_share: float = 0.3
@export var canopy_top_loss_weight: float = 0.3
@export var foliage_sample_step_m: float = 15.0

# The optic is a thermal imager with no scene lighting, so terrain is drawn
# unshaded and these values act as apparent temperature: cool ground, slightly
# warmer tree crowns.
const COL_GROUND = Color(0.14, 0.14, 0.14)
const COL_TRUNK = Color(0.26, 0.26, 0.26)
const COL_CROWN = Color(0.34, 0.34, 0.34)

var _height_samples: int = 0
var _heights := PackedFloat32Array()
var _forest_samples: int = 0
var _forest := PackedByteArray()
var _forest_threshold: int = 0
var _max_height_m: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = terrain_seed if terrain_seed != 0 else randi()
	_build_height_grid()
	_build_forest_grid()
	_build_ground()
	_build_trees()
	GlobalPantsirSystem.terrain = self

func _exit_tree() -> void:
	if GlobalPantsirSystem.terrain == self:
		GlobalPantsirSystem.terrain = null

func _make_noise(wavelength_m: float, octaves: int) -> FastNoiseLite:
	var noise = FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = octaves
	noise.frequency = 1.0 / wavelength_m
	return noise

func _field_blend(x: float, z: float) -> float:
	var distance = Vector2(x, z).length()
	return smoothstep(field_radius_m, field_radius_m + field_blend_m, distance)

func _build_height_grid() -> void:
	_height_samples = int(round(half_size_m * 2.0 / height_cell_m)) + 1
	var noise = _make_noise(hill_wavelength_m, 4)
	_heights.resize(_height_samples * _height_samples)
	_max_height_m = 0.0
	for iz in range(_height_samples):
		for ix in range(_height_samples):
			var x = -half_size_m + ix * height_cell_m
			var z = -half_size_m + iz * height_cell_m
			var height = noise.get_noise_2d(x, z) * hill_height_m * _field_blend(x, z)
			_heights[iz * _height_samples + ix] = height
			_max_height_m = maxf(_max_height_m, height)

func _build_forest_grid() -> void:
	_forest_samples = int(round(half_size_m * 2.0 / forest_cell_m)) + 1
	var noise = _make_noise(forest_wavelength_m, 3)
	# get_image samples one noise unit per pixel, so scale to the cell size.
	noise.frequency = forest_cell_m / forest_wavelength_m
	var image = noise.get_image(_forest_samples, _forest_samples, false, false, true)
	image.convert(Image.FORMAT_L8)
	_forest = image.get_data()
	# Normalised noise is roughly uniform, so this threshold leaves the
	# requested share of the map under forest.
	_forest_threshold = int(round((1.0 - forest_coverage) * 255.0))

func get_height(x: float, z: float) -> float:
	var fx = clampf((x + half_size_m) / height_cell_m, 0.0, _height_samples - 1.001)
	var fz = clampf((z + half_size_m) / height_cell_m, 0.0, _height_samples - 1.001)
	var ix = int(fx)
	var iz = int(fz)
	var tx = fx - ix
	var tz = fz - iz
	var row = iz * _height_samples
	var top = lerpf(_heights[row + ix], _heights[row + ix + 1], tx)
	var bottom = lerpf(_heights[row + _height_samples + ix], _heights[row + _height_samples + ix + 1], tx)
	return lerpf(top, bottom, tz)

func is_forest(x: float, z: float) -> bool:
	var ix = int(round((x + half_size_m) / forest_cell_m))
	var iz = int(round((z + half_size_m) / forest_cell_m))
	if ix < 0 or iz < 0 or ix >= _forest_samples or iz >= _forest_samples:
		return false
	if x * x + z * z < field_radius_m * field_radius_m:
		return false
	return _forest[iz * _forest_samples + ix] > _forest_threshold

# Metres of the path that run through tree crowns, weighted by crown density.
func foliage_path_length(from: Vector3, to: Vector3) -> float:
	var top_of_crowns = _max_height_m + canopy_height_m
	# Only the part of the path low enough to touch the canopy is sampled.
	var t_start = 0.0
	var t_end = 1.0
	if !is_equal_approx(from.y, to.y):
		var t_at_top = (top_of_crowns - from.y) / (to.y - from.y)
		if to.y > from.y:
			t_end = clampf(t_at_top, 0.0, 1.0)
		else:
			t_start = clampf(t_at_top, 0.0, 1.0)
	elif from.y > top_of_crowns:
		return 0.0
	var path_length = from.distance_to(to) * (t_end - t_start)
	if path_length <= 0.0:
		return 0.0
	var steps = int(ceil(path_length / foliage_sample_step_m))
	var step_length = path_length / steps
	var dense_top = canopy_height_m * (1.0 - canopy_top_share)
	var foliage = 0.0
	for i in range(steps):
		var point = from.lerp(to, lerpf(t_start, t_end, (i + 0.5) / steps))
		if !is_forest(point.x, point.z):
			continue
		var above_ground = point.y - get_height(point.x, point.z)
		if above_ground < 0.0 or above_ground > canopy_height_m:
			continue
		foliage += step_length * (1.0 if above_ground <= dense_top else canopy_top_loss_weight)
	return foliage

# Factor (0..1] applied to radar detection ranges for this path.
func radar_range_factor(from: Vector3, to: Vector3) -> float:
	var loss_db = foliage_path_length(from, to) * foliage_loss_db_per_m
	return pow(10.0, -loss_db / 40.0)

func _build_ground() -> void:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	vertices.resize(_height_samples * _height_samples)
	normals.resize(_height_samples * _height_samples)
	for iz in range(_height_samples):
		for ix in range(_height_samples):
			var index = iz * _height_samples + ix
			vertices[index] = Vector3(-half_size_m + ix * height_cell_m, _heights[index], -half_size_m + iz * height_cell_m)
			var left = _heights[iz * _height_samples + maxi(ix - 1, 0)]
			var right = _heights[iz * _height_samples + mini(ix + 1, _height_samples - 1)]
			var back = _heights[maxi(iz - 1, 0) * _height_samples + ix]
			var front = _heights[mini(iz + 1, _height_samples - 1) * _height_samples + ix]
			normals[index] = Vector3(left - right, 2.0 * height_cell_m, back - front).normalized()
	for iz in range(_height_samples - 1):
		for ix in range(_height_samples - 1):
			var a = iz * _height_samples + ix
			var b = a + 1
			var c = a + _height_samples
			var d = c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material = StandardMaterial3D.new()
	material.albedo_color = COL_GROUND
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	%Ground.mesh = mesh

	# HeightMapShape3D spans one unit per sample, centred on its origin. Only
	# uniform scaling is reliable, so heights are stored in cell units.
	var shape_heights = PackedFloat32Array()
	shape_heights.resize(_heights.size())
	for i in range(_heights.size()):
		shape_heights[i] = _heights[i] / height_cell_m
	var shape = HeightMapShape3D.new()
	shape.map_width = _height_samples
	shape.map_depth = _height_samples
	shape.map_data = shape_heights
	%GroundShape.shape = shape
	%GroundShape.scale = Vector3.ONE * height_cell_m

func _make_tree_mesh() -> ArrayMesh:
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = canopy_height_m * 0.35
	trunk.radial_segments = 5
	trunk.rings = 1
	var crown = CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 3.2
	crown.height = canopy_height_m * 0.8
	crown.radial_segments = 7
	crown.rings = 1
	var mesh = ArrayMesh.new()
	# Each part is lifted so the tree's origin is at its foot.
	for part in [[trunk, trunk.height * 0.5, COL_TRUNK], [crown, canopy_height_m - crown.height * 0.5, COL_CROWN]]:
		var arrays = part[0].get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()):
			vertices[i].y += part[1]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material = StandardMaterial3D.new()
		material.albedo_color = part[2]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

func _build_trees() -> void:
	var transforms: Array[Transform3D] = []
	var cells = int(tree_visible_radius_m / tree_spacing_m)
	for iz in range(-cells, cells + 1):
		for ix in range(-cells, cells + 1):
			var x = ix * tree_spacing_m + _rng.randf_range(-0.45, 0.45) * tree_spacing_m
			var z = iz * tree_spacing_m + _rng.randf_range(-0.45, 0.45) * tree_spacing_m
			if Vector2(x, z).length() > tree_visible_radius_m or !is_forest(x, z):
				continue
			var tree_scale = _rng.randf_range(0.75, 1.15)
			var basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * tree_scale)
			transforms.append(Transform3D(basis, Vector3(x, get_height(x, z), z)))
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _make_tree_mesh()
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	%Trees.multimesh = multimesh
