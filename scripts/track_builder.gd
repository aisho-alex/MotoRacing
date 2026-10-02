class_name TrackBuilder
extends Node3D
## Builds the whole race track procedurally: road mesh, edge lines, walls,
## start/finish area and scenery. Geometry is generated in code; PBR textures
## from the biome folder (TrackDef) are applied when present.

const SUBDIV := 26
const ROAD_Y := 0.02
const LINE_Y := 0.05
const CURB_Y := 0.07
const SIDEWALK_Y := 0.035
## Boost pads ("ускорялки") replace the old jump ramps: flat glowing strips that
## kick the bike's speed up for a short time instead of launching it into the air.
const PAD_LENGTH := 9.0
const PAD_WIDTH_MARGIN := 1.0
const PAD_WIDTH_RATIO := 0.20
const PAD_COUNT := 5
const PAD_COLLISION_HEIGHT := 1.6
## Nitro pickups ("бутылочки"): rotating bottles that instantly refill part of
## the bike's nitro tank when driven over (player and AI both collect them).
const NITRO_BOTTLE_COUNT := 8
## Repair packs ("аптечки"): fewer than nitro bottles, so healing is a real
## decision rather than a constant stream.
const HEALTH_PACK_COUNT := 5
## Money bags (player-only credits), shield cells, oil slicks and road cones.
const CASH_PICKUP_COUNT := 3
const SHIELD_PICKUP_COUNT := 2
const OIL_SLICK_COUNT := 4
const CONE_COUNT := 5
## Keep bottles this many samples away from a boost pad so both reads stay clean.
const NITRO_PICKUP_AVOID_PAD := 26
## Curb kit (Kenney "City Kit (Roads)", CC0): one 1 m one-sided curb segment
## sliced by tools/assetgen/normalize_curb.py. Placed along both road edges.
const CURB_KIT_DIR := "res://assets/environments/city/curbs"
const CURB_KIT: Array[String] = ["curb_straight_a"]
## Arc length between placed curb segments (m); slightly under the 1 m mesh so
## consecutive segments overlap and the strip stays continuous on curves.
const CURB_STEP := 0.8
const CITY_BUILDING_MIN_LATERAL := 48.0
const CITY_BUILDING_FOOTPRINT_RADIUS := 19.0
## Clearance between the road edge and any decor footprint candidate (m).
const ROAD_DECOR_MARGIN := 3.5
const CITY_BUILDING_MIN_CENTER_DISTANCE := 42.0
const CITY_SKYLINE_FOOTPRINT_RADIUS := 16.0
const CITY_SKYLINE_MIN_GAP := 26.0
## Real-mesh building kit for the city biome (see docs/assets.md, section 4).
const BUILDING_KIT_DIR := "res://assets/environments/city/buildings"
const BUILDING_KIT: Array[String] = [
	"bank", "bar", "pharmacy", "restaurant", "store",
	"aptcomplex", "brooklyn", "chicago", "citybld", "oldapt",
	"rohbld", "urbanhouse", "largebld",
]
## Variants reserved for the far skyline band (tallest silhouettes).
const BUILDING_KIT_SKYLINE: Array[String] = [
	"citybld", "largebld",
]
## Max world-space half-diagonal a skyline tower may occupy (m).
const CITY_SKYLINE_MAX_HALF_DIAG := 40.0
## Dense street-front row (urban canyon): kit buildings packed along both road
## edges right behind the sidewalk, replacing the low facade band so the track
## reads as a real street instead of a fence. Setback is measured from the
## outer sidewalk edge (m).
const FRONT_ROW_SETBACK_MIN := 1.2
const FRONT_ROW_SETBACK_MAX := 3.2
const FRONT_ROW_GAP_MIN := 1.0
const FRONT_ROW_GAP_MAX := 4.0
const FRONT_ROW_ALLEY_CHANCE := 0.06
const FRONT_ROW_ALLEY_MIN := 6.0
const FRONT_ROW_ALLEY_MAX := 10.0
const FRONT_ROW_SCALE_MIN := 0.9
const FRONT_ROW_SCALE_MAX := 1.25
## Every Nth front-row building is swapped for a tall tower (rescaled so its
## along-track length matches, keeping the wall's rhythm). Deterministic, so it
## does not disturb the placement RNG.
const FRONT_ROW_TOWER_PERIOD := 7
## Distance (m) after which front-row meshes fade out; the skyline covers the
## horizon, so the belt does not need to be drawn across the whole map.
const FRONT_ROW_VIS_RANGE := 320.0
## Street-scale kit variants for the front row.
const FRONT_ROW_KIT: Array[String] = [
	"bank", "bar", "pharmacy", "restaurant", "store",
	"aptcomplex", "brooklyn", "chicago", "oldapt", "rohbld", "urbanhouse",
]
## Taller silhouettes mixed into the front row for variation.
const FRONT_ROW_TOWERS: Array[String] = ["citybld", "largebld"]

var def: TrackDef

var centerline := PackedVector3Array()
var tangents := PackedVector3Array()
var _arc := PackedFloat32Array()
## World transforms of skyline boxes, kept for tooling (MultiMesh instances
## cannot be read back in headless mode).
var skyline_transforms: Array[Transform3D] = []
var _contact_shadow_mesh: QuadMesh
var _contact_shadow_material: StandardMaterial3D
## Local-space AABBs of building kit variants, cached per build.
var _kit_aabb_cache: Dictionary = {}
## Kit materials whose emission was already tuned for the current race mode.
var _kit_tuned_materials: Dictionary = {}
var _kit_toon_materials: Dictionary = {}  # source material -> shared toon material
var _light_pool_mesh: QuadMesh
var _light_pool_material: StandardMaterial3D
var _puddle_mesh: QuadMesh
var _puddle_material: StandardMaterial3D
## Boost-pad spots are deterministic per track, so compute them once.
var _pad_spots_ready := false
var _pad_spots_cache: Array[int] = []


func build() -> void:
	if def == null:
		def = TrackDef.load_default()
	_sample_centerline()
	add_child(_make_ground())
	var road_roughness := 0.22 if def.wet_road else 0.95
	var road_color := Color(0.42, 0.47, 0.56) if def.wet_road else Color(0.16, 0.16, 0.18)
	add_child(_make_ribbon(def.road_half_width, -def.road_half_width, ROAD_Y, road_color, road_roughness, true))
	var line_roughness := 0.32 if def.night_racing else 0.8
	var line_emission := 0.28 if def.night_racing else 0.0
	add_child(_make_ribbon(def.road_half_width - 0.30, def.road_half_width - 0.65, LINE_Y, Color(0.82, 0.86, 0.94), line_roughness, false, line_emission))
	add_child(_make_ribbon(-(def.road_half_width - 0.65), -(def.road_half_width - 0.30), LINE_Y, Color(0.82, 0.86, 0.94), line_roughness, false, line_emission))
	if def.night_racing:
		add_child(_make_lane_markings())
	if def.urban_canyon:
		add_child(_make_sidewalks())
	if def.wet_road:
		var rng := RandomNumberGenerator.new()
		rng.seed = def.decor_seed ^ 0x51A7
		add_child(_make_puddles(rng))
	add_child(_make_curbs())
	add_child(_make_barrier(1.0))
	add_child(_make_barrier(-1.0))
	add_child(_make_start_area())
	add_child(_make_decor())
	if def.streetlight_spacing > 0:
		add_child(_make_street_lights())
	add_child(_make_boost_pads())
	add_child(_make_nitro_pickups())
	add_child(_make_health_pickups())
	add_child(_make_cash_pickups())
	add_child(_make_shield_pickups())
	add_child(_make_oil_slicks())
	add_child(_make_cones())
	if def.wet_road:
		add_child(_make_reflection_probes())


func sample_count() -> int:
	return centerline.size()


## Approximate world-space distance between adjacent centerline samples.
func sample_spacing(i: int) -> float:
	var n := centerline.size()
	if n < 2:
		return 1.9
	return centerline[i].distance_to(centerline[(i + 1) % n])


func tangent_yaw(i: int) -> float:
	var t := tangents[i]
	return atan2(-t.x, -t.z)


## Index of the centerline sample nearest to `p`. `window` > 0 searches only
## around `from_index`; window <= 0 scans the whole track. Single source for the
## nearest-point search shared by AI, police, traffic and lap tracking.
func nearest_sample(p: Vector3, from_index: int = -1, window: int = 0) -> int:
	var n := centerline.size()
	if n == 0:
		return 0
	if window > 0 and from_index >= 0:
		var best := INF
		var best_i := from_index
		for k in range(-window, window + 1):
			var i := (from_index + k + n) % n
			var d := centerline[i].distance_squared_to(p)
			if d < best:
				best = d
				best_i = i
		return best_i
	var best_full := INF
	var best_full_i := 0
	for i in n:
		var d := centerline[i].distance_squared_to(p)
		if d < best_full:
			best_full = d
			best_full_i = i
	return best_full_i


func side_vector(i: int) -> Vector3:
	var t := tangents[i]
	return Vector3(t.z, 0.0, -t.x)


func min_distance_to_track(p: Vector3) -> float:
	var best := INF
	for c in centerline:
		var d := c.distance_squared_to(p)
		if d < best:
			best = d
	return sqrt(best)


func _sample_centerline() -> void:
	var k := def.control_points.size()
	for i in k:
		var p0: Vector3 = def.control_points[(i - 1 + k) % k]
		var p1: Vector3 = def.control_points[i]
		var p2: Vector3 = def.control_points[(i + 1) % k]
		var p3: Vector3 = def.control_points[(i + 2) % k]
		for j in SUBDIV:
			var t := float(j) / float(SUBDIV)
			centerline.append(_catmull(p0, p1, p2, p3, t))
	var n := centerline.size()
	tangents.resize(n)
	_arc.resize(n)
	var travel := 0.0
	for i in n:
		tangents[i] = (centerline[(i + 1) % n] - centerline[(i - 1 + n) % n]).normalized()
		_arc[i] = travel
		travel += centerline[i].distance_to(centerline[(i + 1) % n])


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


## A ribbon along the centerline. UVs are in tile units on both axes so the
## road texture tiles seamlessly along the lap.
func _make_ribbon(o_hi: float, o_lo: float, y: float, color: Color, rough: float,
		use_road_maps := false, emission_energy := 0.0) -> MeshInstance3D:
	var n := centerline.size()
	var tile := maxf(def.road_tile_length, 0.5)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		var c := centerline[i]
		var s := side_vector(i)
		verts.append(c + s * o_hi + Vector3.UP * y)
		verts.append(c + s * o_lo + Vector3.UP * y)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(o_hi / tile, _arc[i] / tile))
		uvs.append(Vector2(o_lo / tile, _arc[i] / tile))
	for i in n:
		var i2 := (i + 1) % n
		var a := i * 2
		var b := a + 1
		var c2 := i2 * 2
		var d := c2 + 1
		# Clockwise when viewed from above (Godot front faces) so the ribbon
		# is not back-face culled from the camera.
		idx.append_array(PackedInt32Array([a, c2, b, b, c2, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	if use_road_maps:
		_apply_road_maps(mat)
	if mat.albedo_texture == null or def.wet_road:
		mat.albedo_color = color
	mat.roughness = rough
	if def.wet_road and use_road_maps:
		mat.normal_scale = 0.55
		mat.metallic = 0.08
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.82
		mat.clearcoat_roughness = 0.06
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(0.72, 0.82, 1.0)
		mat.emission_energy_multiplier = emission_energy
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


## glTF-style ORM: R = ambient occlusion, G = roughness, B = metallic.
func _apply_road_maps(mat: StandardMaterial3D) -> void:
	var albedo := _load_tex(def.road_albedo_path())
	if albedo != null:
		mat.albedo_texture = albedo
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var normal := _load_tex(def.road_normal_path())
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	var orm := _load_tex(def.road_orm_path())
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE


func _make_lane_markings() -> Node3D:
	var root := Node3D.new()
	root.name = "LaneMarkings"
	root.add_child(_make_dashed_line(-def.road_half_width * 0.5, Color(0.76, 0.82, 0.92)))
	root.add_child(_make_dashed_line(0.0, Color(1.0, 0.68, 0.12)))
	root.add_child(_make_dashed_line(def.road_half_width * 0.5, Color(0.76, 0.82, 0.92)))
	return root


func _make_dashed_line(lateral: float, color: Color) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in range(0, centerline.size(), 8):
		var fwd := tangents[i]
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := Vector3(fwd.z, 0.0, -fwd.x)
		var p := centerline[i] + side_vector(i) * lateral + Vector3.UP * (LINE_Y + 0.004)
		var a := p - right * 0.09 + fwd * 1.45
		var b := p + right * 0.09 + fwd * 1.45
		var c := p - right * 0.09 - fwd * 1.45
		var d := p + right * 0.09 - fwd * 1.45
		var base := verts.size()
		verts.append_array(PackedVector3Array([a, b, c, d]))
		norms.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.26
	mat.metallic = 0.05
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.45
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_sidewalks() -> Node3D:
	var root := Node3D.new()
	root.name = "Sidewalks"
	var inner := def.road_half_width + 0.45
	var outer := def.road_half_width + 7.0
	root.add_child(_make_ribbon(outer, inner, SIDEWALK_Y, Color(0.115, 0.13, 0.16), 0.78))
	root.add_child(_make_ribbon(-inner, -outer, SIDEWALK_Y, Color(0.115, 0.13, 0.16), 0.78))
	root.add_child(_make_ribbon(def.road_half_width + 0.75, def.road_half_width + 0.45, CURB_Y, Color(0.22, 0.24, 0.28), 0.62))
	root.add_child(_make_ribbon(-(def.road_half_width + 0.45), -(def.road_half_width + 0.75), CURB_Y, Color(0.22, 0.24, 0.28), 0.62))
	return root


func _make_puddles(rng: RandomNumberGenerator) -> Node3D:
	if _puddle_mesh == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
		grad.colors = PackedColorArray([
			Color(0.025, 0.035, 0.06, 0.72),
			Color(0.035, 0.05, 0.08, 0.42),
			Color(0.02, 0.03, 0.05, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_puddle_material = StandardMaterial3D.new()
		_puddle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puddle_material.albedo_texture = tex
		_puddle_material.roughness = 0.05
		_puddle_material.metallic = 0.22
		_puddle_material.clearcoat_enabled = true
		_puddle_material.clearcoat = 0.95
		_puddle_material.clearcoat_roughness = 0.025
		_puddle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_puddle_mesh = QuadMesh.new()
		_puddle_mesh.size = Vector2.ONE
		_puddle_mesh.material = _puddle_material
	var root := Node3D.new()
	root.name = "Puddles"
	for _i in 42:
		var idx := rng.randi_range(0, centerline.size() - 1)
		var lateral := rng.randf_range(-def.road_half_width + 1.1, def.road_half_width - 1.1)
		var p := centerline[idx] + side_vector(idx) * lateral + Vector3.UP * (ROAD_Y + 0.014)
		var mi := MeshInstance3D.new()
		mi.mesh = _puddle_mesh
		mi.material_override = _puddle_material
		mi.transform = Transform3D(Basis(Vector3.UP, tangent_yaw(idx)) * Basis(Vector3.RIGHT, -PI * 0.5), p)
		mi.scale = Vector3(rng.randf_range(0.8, 2.8), rng.randf_range(2.2, 7.5), 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Invisible physics barrier along the road edge. The old red/white fence was
## purely visual, so it is removed and replaced by the curb + street facade;
## the collision strip stays so bikes still cannot leave the track.
func _make_barrier(sign_dir: float) -> StaticBody3D:
	var n := centerline.size()
	var offset := sign_dir * (def.road_half_width + 0.4)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n:
		var s := side_vector(i)
		var base := centerline[i] + s * offset
		var normal: Vector3 = -s * signf(sign_dir)
		verts.append(base + Vector3.UP * ROAD_Y)
		verts.append(base + Vector3.UP * (ROAD_Y + def.wall_height))
		norms.append(normal)
		norms.append(normal)
	for i in n:
		var i2 := (i + 1) % n
		var b := i * 2
		var t := b + 1
		var b2 := i2 * 2
		var t2 := b2 + 1
		idx.append_array(PackedInt32Array([b, t, b2, t, t2, b2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := StaticBody3D.new()
	body.name = "Barrier"
	var col_shape := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col_shape.shape = shape
	body.add_child(col_shape)
	return body


## Curb strip along both asphalt edges: the real kit mesh (Kenney CC0) placed
## as one MultiMesh per side for a single draw call, or a painted ribbon fallback.
func _make_curbs() -> Node3D:
	var root := Node3D.new()
	root.name = "Curbs"
	if _curb_available():
		var mesh := _load_curb_mesh(CURB_KIT[0])
		if mesh != null:
			root.add_child(_make_curb_multimesh(mesh, 1.0))
			root.add_child(_make_curb_multimesh(mesh, -1.0))
			return root
	var inner := def.road_half_width
	var outer := def.road_half_width + 0.18
	root.add_child(_make_ribbon(outer, inner, CURB_Y, Color(0.55, 0.57, 0.6), 0.75))
	root.add_child(_make_ribbon(-inner, -outer, CURB_Y, Color(0.55, 0.57, 0.6), 0.75))
	return root


func _curb_available() -> bool:
	for id in CURB_KIT:
		if not ResourceLoader.exists("%s/%s.glb" % [CURB_KIT_DIR, id]):
			return false
	return true


func _load_curb_mesh(id: String) -> Mesh:
	var packed := load("%s/%s.glb" % [CURB_KIT_DIR, id]) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	var mesh: Mesh = null
	for mi in instance.find_children("*", "MeshInstance3D", true, false):
		mesh = (mi as MeshInstance3D).mesh
		break
	instance.free()
	return mesh


func _make_curb_multimesh(mesh: Mesh, sign_dir: float) -> MultiMeshInstance3D:
	var n := centerline.size()
	# local +Z follows the road, local +X points away from the asphalt; the
	# unrotated basis already faces the negative side, so flip the positive one
	var yaw_flip := 0.0 if sign_dir < 0.0 else PI
	# place one 1 m kit segment every CURB_STEP m of arc so the strip is
	# continuous; per-instance scale is unreliable on MultiMesh, so walk the
	# arc instead of stretching a single segment
	var transforms: Array[Transform3D] = []
	for i in n:
		var a := centerline[i]
		var b := centerline[(i + 1) % n]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var steps := maxi(1, int(ceil(seg / CURB_STEP)))
		var yaw := tangent_yaw(i) + yaw_flip
		var s := side_vector(i) * (sign_dir * def.road_half_width)
		for k in steps:
			var f := float(k) / float(steps)
			var p := a.lerp(b, f) + s
			p.y = 0.0
			transforms.append(Transform3D(Basis(Vector3.UP, yaw), p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	mm.custom_aabb = AABB(Vector3(-400.0, -2.0, -400.0), Vector3(800.0, 40.0, 800.0))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _make_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	var mat := StandardMaterial3D.new()
	var albedo: Texture2D = null if def.urban_canyon else _load_tex(def.terrain_albedo_path())
	if albedo != null:
		mat.albedo_texture = albedo
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		# World-space triplanar keeps the terrain tile stable and seamless.
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		var ts := 1.0 / maxf(def.terrain_tile_size, 0.5)
		mat.uv1_scale = Vector3(ts, ts, ts)
		var normal := _load_tex(def.terrain_normal_path())
		if normal != null:
			mat.normal_enabled = true
			mat.normal_texture = normal
		var orm := _load_tex(def.terrain_orm_path())
		if orm != null:
			mat.ao_enabled = true
			mat.ao_texture = orm
			mat.roughness_texture = orm
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			mat.metallic_texture = orm
			mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	else:
		mat.albedo_color = Color(0.045, 0.055, 0.075) if def.urban_canyon else Color(0.24, 0.44, 0.23)
	mat.roughness = 0.9 if def.urban_canyon else 1.0
	mat.metallic = 0.04 if def.urban_canyon else 0.0
	plane.material = mat
	mi.mesh = plane
	mi.position.y = -0.02
	body.add_child(mi)
	# A finite box instead of WorldBoundaryShape3D: the infinite plane can
	# micro-penetrate a resting body and pin it (observed: AI frozen at stop).
	var col := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(4000, 1, 4000)
	col.shape = ground_box
	col.position.y = -0.5
	body.add_child(col)
	return body


func _make_street_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLights"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.15
	pole_mesh.height = 6.8
	pole_mesh.radial_segments = 8
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.035, 0.045, 0.065)
	pole_mat.roughness = 0.38
	pole_mat.metallic = 0.75
	pole_mesh.material = pole_mat
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.12, 0.12, 2.2)
	arm_mesh.material = pole_mat
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.48, 0.14, 0.72)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.78, 0.42)
	head_mat.roughness = 0.22
	if def.night_racing:
		head_mat.emission_enabled = true
		head_mat.emission = Color(1.0, 0.62, 0.22)
		head_mat.emission_energy_multiplier = 5.0
	head_mesh.material = head_mat
	var step := maxi(def.streetlight_spacing, 1)
	for i in range(12, centerline.size() - 4, step):
		var side := 1.0 if ((i / step) % 2 == 0) else -1.0
		var side_dir := side_vector(i)
		var p := centerline[i] + side_dir * side * (def.road_half_width + 3.0)
		var toward := -side_dir * side
		var pole := MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.position = p + Vector3.UP * 3.4
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pole)
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.position = Vector3(p.x + toward.x * 1.05, 6.78, p.z + toward.z * 1.05)
		arm.look_at_from_position(arm.position,
				Vector3(p.x + toward.x * 2.1, 6.78, p.z + toward.z * 2.1), Vector3.UP)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(arm)
		var head_pos := Vector3(p.x + toward.x * 2.1, 6.72, p.z + toward.z * 2.1)
		var head := MeshInstance3D.new()
		head.mesh = head_mesh
		head.position = head_pos
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(head)
		# light + glowing road pool only make sense after dark
		if def.night_racing:
			var light := OmniLight3D.new()
			light.position = head_pos - Vector3.UP * 0.18
			light.light_color = Color(1.0, 0.67, 0.32)
			light.light_energy = 3.5
			light.omni_range = 17.0
			light.omni_attenuation = 1.45
			light.shadow_enabled = false
			light.light_volumetric_fog_energy = 0.8
			light.distance_fade_enabled = true
			light.distance_fade_begin = 75.0
			light.distance_fade_length = 70.0
			root.add_child(light)
			var pool := _make_light_pool()
			pool.position = Vector3(head_pos.x, LINE_Y + 0.018, head_pos.z)
			root.add_child(pool)
	return root


func _make_light_pool() -> MeshInstance3D:
	if _light_pool_mesh == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 0.72, 0.32, 0.34),
			Color(1.0, 0.58, 0.20, 0.13),
			Color(1.0, 0.42, 0.12, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_light_pool_material = StandardMaterial3D.new()
		_light_pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_light_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_light_pool_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_light_pool_material.albedo_texture = tex
		_light_pool_material.albedo_color = Color(2.2, 1.35, 0.62, 0.72)
		_light_pool_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_light_pool_mesh = QuadMesh.new()
		_light_pool_mesh.size = Vector2.ONE
		_light_pool_mesh.material = _light_pool_material
	var mi := MeshInstance3D.new()
	mi.mesh = _light_pool_mesh
	mi.material_override = _light_pool_material
	mi.scale = Vector3(8.0, 8.0, 1.0)
	mi.rotation_degrees.x = -90.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_reflection_probes() -> Node3D:
	var root := Node3D.new()
	root.name = "ReflectionProbes"
	var idx := int(float(centerline.size()) * 0.5) % centerline.size()
	var probe := ReflectionProbe.new()
	probe.position = centerline[idx] + Vector3.UP * 10.0
	probe.size = Vector3(170.0, 58.0, 170.0)
	probe.max_distance = 260.0
	probe.intensity = 1.15
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	root.add_child(probe)
	return root


func _make_start_area() -> Node3D:
	var root := Node3D.new()
	root.position = centerline[0]
	root.rotation.y = atan2(tangents[0].x, tangents[0].z)

	var line := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(def.road_half_width * 2.0 - 0.4, 2.2)
	plane.material = _checker_material()
	line.mesh = plane
	line.position.y = LINE_Y + 0.01
	root.add_child(line)

	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(0.8, 5.0, 0.8)
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.9, 0.9, 0.92)
	if def.night_racing:
		pillar_mat.emission_enabled = true
		pillar_mat.emission = Color(0.32, 0.72, 1.0)
		pillar_mat.emission_energy_multiplier = 2.2
	pillar_mesh.material = pillar_mat
	for s in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.mesh = pillar_mesh
		p.position = Vector3(s * (def.road_half_width + 1.4), 2.5, 0)
		root.add_child(p)

	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(def.road_half_width * 2.0 + 3.6, 0.8, 0.8)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.85, 0.15, 0.12)
	if def.night_racing:
		beam_mat.emission_enabled = true
		beam_mat.emission = Color(1.0, 0.08, 0.025)
		beam_mat.emission_energy_multiplier = 3.0
	beam_mesh.material = beam_mat
	beam.mesh = beam_mesh
	beam.position = Vector3(0, 5.2, 0)
	root.add_child(beam)

	# Banner facing approaching bikes (they travel along +local Z, so they see
	# the -Z-facing side placed before the line). Single-sided so no mirrored
	# text is visible from behind.
	var banner := Label3D.new()
	banner.text = "START / FINISH"
	banner.font_size = 220
	banner.modulate = Color(1.8, 2.2, 3.2) if def.night_racing else Color.WHITE
	banner.outline_size = 40
	banner.double_sided = false
	banner.position = Vector3(0, 5.2, -0.45)
	banner.rotation.y = PI
	root.add_child(banner)
	banner = Label3D.new()
	banner.text = "START / FINISH"
	banner.font_size = 220
	banner.modulate = Color(1.8, 2.2, 3.2) if def.night_racing else Color.WHITE
	banner.outline_size = 40
	banner.double_sided = false
	banner.position = Vector3(0, 5.2, 0.45)
	root.add_child(banner)
	return root


func _checker_material() -> StandardMaterial3D:
	var img := Image.create(8, 2, false, Image.FORMAT_RGB8)
	for y in 2:
		for x in 8:
			var c := Color.BLACK if (x + y) % 2 == 0 else Color.WHITE
			img.set_pixel(x, y, c)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 0.85
	return mat


func _make_boost_pads() -> Node3D:
	var root := Node3D.new()
	root.name = "BoostPads"
	var rng := RandomNumberGenerator.new()
	rng.seed = def.decor_seed ^ 0x7C3F
	var spots := _pad_spots()
	for k in spots.size():
		var w := _pad_width()
		# random lateral placement: a narrow strip, so the line choice is
		# "hit the pad or take the clean asphalt"
		var max_offset := maxf(def.road_half_width - w / 2.0 - 0.4, 0.0)
		var offset := rng.randf_range(-1.0, 1.0) * max_offset
		root.add_child(_make_pad(spots[k], offset))
	return root


func _pad_width() -> float:
	return (def.road_half_width * 2.0 - PAD_WIDTH_MARGIN) * PAD_WIDTH_RATIO


## Picks sample indices on straight sections of the track, away from the start
## line and spaced apart, so pads sit on a fast, predictable stretch.
func _pick_pad_spots(count: int) -> Array[int]:
	var n := sample_count()
	var spots: Array[int] = []
	var last := -1000
	for i in n:
		# keep pads well away from the start straight/grid so the grid is not
		# decided by a free boost right off the line
		if i < 60 or i > n - 12:
			continue
		var t0 := tangents[(i - 8 + n) % n]
		var t1 := tangents[(i + 8) % n]
		if t0.dot(t1) <= 0.995:  # ~5.7 degrees over +-8 samples: not straight
			continue
		if i - last < 70:
			continue
		spots.append(i)
		last = i
		if spots.size() >= count:
			break
	return spots


## A flat glowing strip on the asphalt, spanning part of the road width
## (PAD_WIDTH_RATIO) at a random lateral offset. An Area3D kicks the bike's
## speed up when it passes over; there is nothing to jump off any more.
func _make_pad(idx: int, offset := 0.0) -> Area3D:
	var area := Area3D.new()
	area.name = "BoostPad"
	# no own layer; watch the player (1) and the opponents (2)
	area.collision_layer = 0
	area.collision_mask = 3
	area.add_child(_make_pad_visual())
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_pad_width(), PAD_COLLISION_HEIGHT, PAD_LENGTH)
	col.shape = box
	col.position.y = PAD_COLLISION_HEIGHT * 0.5 - 0.1
	area.add_child(col)
	area.body_entered.connect(_on_pad_body_entered)
	area.position = centerline[idx] + side_vector(idx) * offset + Vector3.UP * ROAD_Y
	area.rotation.y = tangent_yaw(idx)
	return area


func _on_pad_body_entered(body: Node3D) -> void:
	if "is_traffic" in body and body.is_traffic:
		return
	if body.has_method("apply_pad_boost"):
		body.call("apply_pad_boost")


## Nitro bottles and repair packs share the same even arc-length spread and the
## same lateral placement; only the class, count, seed and collision filters
## differ. `script` is the pickup class (NitroPickup / HealthPickup).
func _make_pickups(root_name: String, script, node_name: String,
		spots: Array[int], seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var max_offset := maxf(def.road_half_width - 1.3, 0.0)
	for idx in spots:
		var pickup: Node3D = script.new()
		pickup.name = node_name
		var offset := rng.randf_range(-1.0, 1.0) * max_offset
		pickup.position = centerline[idx] + side_vector(idx) * offset + Vector3.UP * ROAD_Y
		pickup.rotation.y = rng.randf() * TAU
		root.add_child(pickup)
	return root


## Nitro bottles spread evenly along the lap with a random lateral offset inside
## the road, so the line choice is "swing for the refill or stay clean".
func _make_nitro_pickups() -> Node3D:
	return _make_pickups("NitroPickups", NitroPickup, "NitroBottle",
			_pick_bottle_spots(NITRO_BOTTLE_COUNT), def.decor_seed ^ 0x2B9D)


## Even arc-length spread of sample indices for repair packs, avoiding the
## boost pads and the nitro bottles so each pickup stays a distinct read.
func _make_health_pickups() -> Node3D:
	return _make_pickups("HealthPickups", HealthPickup, "HealthPack",
			_pick_health_spots(HEALTH_PACK_COUNT), def.decor_seed ^ 0x5C11)


func _make_cash_pickups() -> Node3D:
	return _make_pickups("CashPickups", CashPickup, "CashBag",
			_pick_cash_spots(CASH_PICKUP_COUNT), def.decor_seed ^ 0x11A3)


func _make_shield_pickups() -> Node3D:
	return _make_pickups("ShieldPickups", ShieldPickup, "ShieldCell",
			_pick_shield_spots(SHIELD_PICKUP_COUNT), def.decor_seed ^ 0x63B1)


## Oil slicks are a persistent on-road hazard (no collect/respawn); their dark
## discs sit inside the road width at seeded arc-length spots.
func _make_oil_slicks() -> Node3D:
	var root := Node3D.new()
	root.name = "OilSlicks"
	var rng := RandomNumberGenerator.new()
	rng.seed = def.decor_seed ^ 0x4D21
	var max_offset := maxf(def.road_half_width - 2.4, 0.0)
	for idx in _pick_oil_spots(OIL_SLICK_COUNT):
		var oil := OilSlick.new()
		oil.position = centerline[idx] + side_vector(idx) * rng.randf_range(-1.0, 1.0) * max_offset + Vector3.UP * ROAD_Y
		root.add_child(oil)
	return root


func _make_cones() -> Node3D:
	return _make_pickups("TrafficCones", TrafficCone, "Cone",
			_pick_cone_spots(CONE_COUNT), def.decor_seed ^ 0x1F0D)


## Even arc-length spread of sample indices for nitro bottles, kept off the start
## straight and away from the boost pads. A small per-slot jitter (seeded) keeps
## laps from feeling identical without clustering bottles together; if a slot is
## blocked the nearest free neighbour is used instead.
func _pick_bottle_spots(count: int) -> Array[int]:
	return _pick_spread_spots(count, def.decor_seed ^ 0x6F21, [], _pad_spots())


func _pick_health_spots(count: int) -> Array[int]:
	# taken starts with the nitro bottles so a pack never shares their slot
	var taken := _pick_bottle_spots(NITRO_BOTTLE_COUNT).duplicate()
	return _pick_spread_spots(count, def.decor_seed ^ 0x3C0D, taken, _pad_spots())


func _pick_cash_spots(count: int) -> Array[int]:
	var taken := _pick_bottle_spots(NITRO_BOTTLE_COUNT).duplicate()
	taken.append_array(_pick_health_spots(HEALTH_PACK_COUNT))
	return _pick_spread_spots(count, def.decor_seed ^ 0x2C47, taken, _pad_spots())


func _pick_shield_spots(count: int) -> Array[int]:
	var taken := _pick_bottle_spots(NITRO_BOTTLE_COUNT).duplicate()
	taken.append_array(_pick_health_spots(HEALTH_PACK_COUNT))
	taken.append_array(_pick_cash_spots(CASH_PICKUP_COUNT))
	return _pick_spread_spots(count, def.decor_seed ^ 0x7E19, taken, _pad_spots())


func _pick_oil_spots(count: int) -> Array[int]:
	var taken := _pick_bottle_spots(NITRO_BOTTLE_COUNT).duplicate()
	taken.append_array(_pick_health_spots(HEALTH_PACK_COUNT))
	taken.append_array(_pick_cash_spots(CASH_PICKUP_COUNT))
	taken.append_array(_pick_shield_spots(SHIELD_PICKUP_COUNT))
	return _pick_spread_spots(count, def.decor_seed ^ 0x4D21, taken, _pad_spots())


func _pick_cone_spots(count: int) -> Array[int]:
	var taken := _pick_bottle_spots(NITRO_BOTTLE_COUNT).duplicate()
	taken.append_array(_pick_health_spots(HEALTH_PACK_COUNT))
	taken.append_array(_pick_cash_spots(CASH_PICKUP_COUNT))
	taken.append_array(_pick_shield_spots(SHIELD_PICKUP_COUNT))
	taken.append_array(_pick_oil_spots(OIL_SLICK_COUNT))
	return _pick_spread_spots(count, def.decor_seed ^ 0x1F0D, taken, _pad_spots())


func _pick_spread_spots(count: int, seed: int, taken: Array[int],
		pads: Array[int]) -> Array[int]:
	var n := sample_count()
	if n < 2:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var total := _arc[n - 1] + centerline[n - 1].distance_to(centerline[0])
	var spots: Array[int] = []
	for k in count:
		var target := total * (float(k) + 0.5) / float(count)
		var i := 0
		while i < n - 1 and _arc[i] < target:
			i += 1
		i = clampi(i + rng.randi_range(-3, 3), 60, n - 12)
		var spot := _free_bottle_spot(i, pads, taken)
		if spot >= 0:
			spots.append(spot)
			taken.append(spot)
	return spots


func _pad_spots() -> Array[int]:
	if not _pad_spots_ready:
		_pad_spots_ready = true
		_pad_spots_cache = _pick_pad_spots(PAD_COUNT)
	return _pad_spots_cache


## Nearest sample to `start` that is a valid bottle spot: off the start straight,
## on the road, clear of every boost pad and not already used.
func _free_bottle_spot(start: int, pads: Array[int], taken: Array[int]) -> int:
	var n := sample_count()
	for step in 40:
		for dir in ([1, -1] if step > 0 else [1]):
			var i := clampi(start + dir * step * 4, 60, n - 12)
			if taken.has(i):
				continue
			var blocked := false
			for p in pads:
				var d := ((p - i) % n + n) % n
				if mini(d, n - d) < NITRO_PICKUP_AVOID_PAD:
					blocked = true
					break
			if not blocked:
				return i
	return -1


## Restores every collected pickup (called on race restart).
func reset_pickups() -> void:
	for group_name in ["NitroPickups", "HealthPickups", "CashPickups", "ShieldPickups", "TrafficCones"]:
		var root := get_node_or_null(group_name)
		if root == null:
			continue
		for pickup in root.get_children():
			if pickup.has_method("reset"):
				pickup.call("reset")


## Dark pad plate plus three glowing chevrons pointing along travel (local -Z).
func _make_pad_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "PadVisual"
	root.add_child(_make_pad_plate())
	root.add_child(_make_pad_chevrons())
	return root


func _make_pad_flat_mesh(verts: PackedVector3Array, idx: PackedInt32Array,
		material: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_pad_plate() -> MeshInstance3D:
	var hw := _pad_width() / 2.0
	var y := 0.008
	var verts := PackedVector3Array([
		Vector3(-hw, y, -PAD_LENGTH * 0.5),
		Vector3(hw, y, -PAD_LENGTH * 0.5),
		Vector3(-hw, y, PAD_LENGTH * 0.5),
		Vector3(hw, y, PAD_LENGTH * 0.5),
	])
	var idx := PackedInt32Array([0, 2, 1, 1, 2, 3])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.065, 0.09) if def.night_racing \
			else Color(0.13, 0.14, 0.17)
	mat.roughness = 0.55
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _make_pad_flat_mesh(verts, idx, mat)


func _make_pad_chevrons() -> MeshInstance3D:
	var w := _pad_width()
	var chevron_hw := w * 0.5 * 0.72
	var chevron_depth := minf(w * 1.1, PAD_LENGTH * 0.32)
	var thickness := maxf(chevron_depth * 0.30, 0.28)
	var y := 0.016
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	# three stacked "V" chevrons; the apex points toward -Z (travel direction)
	for k in 3:
		var zc := (float(k) - 1.0) * PAD_LENGTH * 0.29
		var base := verts.size()
		var o_l := Vector3(-chevron_hw, y, zc + chevron_depth * 0.5)
		var o_a := Vector3(0.0, y, zc - chevron_depth * 0.5)
		var o_r := Vector3(chevron_hw, y, zc + chevron_depth * 0.5)
		var i_l := Vector3(-chevron_hw, y, zc + chevron_depth * 0.5 - thickness)
		var i_a := Vector3(0.0, y, zc - chevron_depth * 0.5 + thickness)
		var i_r := Vector3(chevron_hw, y, zc + chevron_depth * 0.5 - thickness)
		verts.append_array(PackedVector3Array([o_l, o_a, i_l, o_a, i_a, i_l]))
		verts.append_array(PackedVector3Array([o_a, o_r, i_a, o_r, i_r, i_a]))
		idx.append_array(PackedInt32Array([
			base, base + 1, base + 2, base + 1, base + 4, base + 2,
			base + 1, base + 3, base + 4, base + 3, base + 5, base + 4,
		]))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.24, 0.80, 1.0) if def.night_racing \
			else Color(0.12, 0.58, 0.88)
	mat.emission_enabled = true
	mat.emission = Color(0.20, 0.78, 1.0)
	mat.emission_energy_multiplier = 3.6 if def.night_racing else 1.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _make_pad_flat_mesh(verts, idx, mat)


func _make_decor() -> Node3D:
	var root := Node3D.new()
	root.name = "Decor"
	var rng := RandomNumberGenerator.new()
	rng.seed = def.decor_seed
	var biome := def.biome
	var occupied: Array[Vector3] = []

	# billboard sprites from the biome props folder take priority
	var prop_texs: Array[Texture2D] = []
	var prop_dir := def.env_dir() + "/props"
	var da := DirAccess.open(prop_dir)
	if da != null:
		for f in da.get_files():
			if f.get_extension() == "png":
				var t := load(prop_dir + "/" + f) as Texture2D
				if t != null:
					prop_texs.append(t)

	if def.urban_canyon:
		root.add_child(_make_buildings(rng, occupied))
		return root
	if prop_texs.is_empty():
		root.add_child(_make_primitive_vegetation(rng, biome))
	else:
		root.add_child(_make_sprite_vegetation(rng, prop_texs, occupied))
	root.add_child(_make_buildings(rng, occupied))

	var facade := _load_tex(def.facade_albedo_path("a"))
	var stand_mat := StandardMaterial3D.new()
	stand_mat.roughness = 0.82
	if facade != null:
		# window/balcony rows read as grandstand seating
		stand_mat.albedo_texture = facade
		stand_mat.uv1_triplanar = true
		stand_mat.uv1_world_triplanar = true
		stand_mat.uv1_scale = Vector3.ONE / 1.5
		stand_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		stand_mat.albedo_color = Color.WHITE
	else:
		stand_mat.albedo_color = Color(0.42, 0.46, 0.55)
	var stand_mesh := BoxMesh.new()
	stand_mesh.size = Vector3(26, 6.5, 7)
	stand_mesh.material = stand_mat
	for idx in [10, 40]:
		for s in [-1.0, 1.0]:
			var stand := MeshInstance3D.new()
			stand.mesh = stand_mesh
			stand.position = centerline[idx] + side_vector(idx) * s * (def.road_half_width + 8.0) + Vector3.UP * 3.25
			stand.rotation.y = atan2(side_vector(idx).x, side_vector(idx).z)
			root.add_child(stand)
	return root


## Evenly distributed, track-following candidates with collision-free spacing.
## footprint_radius covers the widest object placed at a spot (0 for sprites).
func _place_decor(rng: RandomNumberGenerator, count: int, min_lateral: float,
		max_lateral: float, min_gap: float, occupied: Array[Vector3],
		footprint_radius := 0.0) -> Array[Dictionary]:
	var n := sample_count()
	var spots: Array[Dictionary] = []
	var guard := 0
	while spots.size() < count and guard < count * 120:
		guard += 1
		var idx := rng.randi_range(60, n - 13)
		var lateral := rng.randf_range(min_lateral, max_lateral)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := centerline[idx] + side_vector(idx) * side * lateral
		p.y = 0.0
		if min_distance_to_track(p) < def.road_half_width + ROAD_DECOR_MARGIN + footprint_radius:
			continue
		var clear := true
		for q in occupied:
			if p.distance_squared_to(q) < min_gap * min_gap:
				clear = false
				break
		if not clear:
			continue
		occupied.append(p)
		spots.append({"pos": p, "idx": idx, "lateral": lateral, "side": side})
	return spots


func _make_sprite_vegetation(rng: RandomNumberGenerator, prop_texs: Array[Texture2D],
		occupied: Array[Vector3]) -> Node3D:
	var root := Node3D.new()
	var spots := _place_decor(rng, def.prop_count, def.prop_min_lateral,
			def.prop_max_lateral, 3.2, occupied)
	for spot in spots:
		var tex: Texture2D = prop_texs[rng.randi() % prop_texs.size()]
		var lname := tex.resource_name.to_lower() if tex.resource_name != "" else ""
		var small: bool = lname.contains("bush") or lname.contains("rock")
		var h_m := rng.randf_range(1.2, 2.2) if small else rng.randf_range(6.2, 10.0)
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.shaded = true
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.alpha_scissor_threshold = 0.18
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		spr.flip_h = rng.randf() < 0.5
		spr.pixel_size = h_m / float(tex.get_height())
		var shade := rng.randf_range(0.93, 1.06)
		spr.modulate = Color(shade, shade * rng.randf_range(0.98, 1.04), shade * rng.randf_range(0.94, 1.0))
		spr.position = Vector3(spot.pos.x, h_m * 0.5 - 0.035, spot.pos.z)
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(spr)
		if not def.night_racing:
			var aspect := float(tex.get_width()) / float(tex.get_height())
			var shadow := _make_contact_shadow(h_m * aspect * (0.72 if small else 0.55))
			shadow.position = Vector3(spot.pos.x, -0.01, spot.pos.z)
			root.add_child(shadow)
	return root


func _make_buildings(rng: RandomNumberGenerator, occupied: Array[Vector3]) -> Node3D:
	var root := Node3D.new()
	root.name = "Buildings"
	var use_kit := def.urban_canyon and _kit_available()
	if use_kit:
		root.add_child(_make_street_front(rng, occupied))
	var spots: Array[Dictionary] = []
	if def.urban_canyon:
		spots = _place_city_buildings(rng, def.building_count, occupied)
	else:
		spots = _place_decor(rng, def.building_count, def.building_min_lateral,
				def.building_max_lateral, def.building_min_gap, occupied,
				15.0)
	if spots.is_empty():
		return root
	if use_kit:
		for spot in spots:
			var b := _make_kit_building(rng, spot)
			if b != null:
				root.add_child(b)
		if def.skyline_count > 0:
			var sky := Node3D.new()
			sky.name = "Skyline"
			root.add_child(sky)
			_make_kit_skyline(rng, occupied, sky)
	else:
		var mats := _make_facade_materials()
		var concrete := _make_concrete_material()
		for spot in spots:
			root.add_child(_make_building(rng, spot, mats, concrete))
		if def.skyline_count > 0:
			root.add_child(_make_skyline(rng, mats, occupied))
	return root


## True when every building kit GLB is present and importable.
func _kit_available() -> bool:
	for id in BUILDING_KIT:
		if not ResourceLoader.exists("%s/%s.glb" % [BUILDING_KIT_DIR, id]):
			return false
	return true


## Places a real-mesh kit building at spot: pick a variant, rotate along the
## track, jitter scale slightly; camera blocker follows the measured AABB.
## Variants whose real footprint would reach the road are retried, then the
## spot is skipped so no building ever intrudes on the asphalt.
func _make_kit_building(rng: RandomNumberGenerator, spot: Dictionary) -> Node3D:
	for _attempt in 6:
		var id: String = BUILDING_KIT[rng.randi() % BUILDING_KIT.size()]
		var root := _spawn_kit_building(rng, id, spot.pos,
				tangent_yaw(int(spot.idx)) + rng.randf_range(-0.04, 0.04),
				rng.randf_range(0.9, 1.25), float(spot["side"]))
		if root == null:
			return _make_building(rng, spot, _make_facade_materials(), _make_concrete_material())
		if _building_clear(root):
			return root
		root.free()
	return null


## Instantiates one kit building at a world transform: uniform scale, yaw
## aligned to the track, footprint centred on the spot, camera blocker and
## (at night) a neon sign. Returns null when the GLB cannot be loaded.
func _spawn_kit_building(rng: RandomNumberGenerator, id: String, pos: Vector3,
		yaw: float, scale_v: float, side: float) -> Node3D:
	var path := "%s/%s.glb" % [BUILDING_KIT_DIR, id]
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var instance := packed.instantiate() as Node3D
	_tune_kit_materials(instance, def.night_racing)
	var aabb := _kit_local_aabb(path, instance)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale_v
	var w := maxf(aabb.size.x, 4.0)
	var d := maxf(aabb.size.z, 4.0)
	var h := maxf(aabb.size.y, 3.0)
	var center := aabb.get_center()
	var holder := Node3D.new()
	holder.position = Vector3(center.x, 0.0, center.z)
	holder.add_child(instance)
	root.add_child(holder)
	_add_camera_blocker(root, w, h, d)
	root.set_meta("kit_footprint", Vector3(w, h, d) * scale_v)
	if def.night_racing and rng.randf() < 0.56:
		_add_neon_sign(rng, root, w, h, side)
	return root


## True when a spawned kit building's real footprint stays clear of the asphalt.
## Mirrors tools/check_buildings.gd: every mesh's world-space AABB corner must
## stay beyond the road edge, so placement can never fail the checker.
func _building_clear(root: Node3D) -> bool:
	var stack: Array = []
	for child in root.get_children():
		stack.append([child, Transform3D.IDENTITY])
	var root_xf := root.transform
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var aabb: AABB = (root_xf * xf) * (n as MeshInstance3D).get_aabb()
			for corner in _footprint_corners(aabb):
				if min_distance_to_track(corner) < def.road_half_width + 0.5:
					return false
		for child in n.get_children():
			stack.append([child, xf])
	return true


## Dense, nearly continuous front row of kit buildings along both road edges.
## Replaces the low facade band in the urban canyon: a real street wall behind
## the sidewalk with small gaps and the occasional alley. A candidate that
## would reach another stretch of road (the spline folds near itself) is
## skipped, leaving a natural gap.
func _make_street_front(rng: RandomNumberGenerator, occupied: Array[Vector3]) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetFront"
	for side in [-1.0, 1.0]:
		root.add_child(_make_street_front_side(rng, side, occupied))
	return root


func _make_street_front_side(rng: RandomNumberGenerator, side: float,
		occupied: Array[Vector3]) -> Node3D:
	var root := Node3D.new()
	var n := sample_count()
	var sidewalk_outer := def.road_half_width + 7.0
	var total := _arc[n - 1] + centerline[n - 1].distance_to(centerline[0])
	var next_arc := 0.0
	var i := 0
	var placed_count := 0
	while i < n and next_arc < total - 12.0:
		if _arc[i] < next_arc:
			i += 1
			continue
		# Try a few variants at this spot: a building whose real footprint (as
		# measured by the checker) reaches another stretch of road is rejected,
		# then another variant is tried. If none fit, step forward a little and
		# retry, so a rejected slot leaves only a small gap.
		var placed_advance := 0.0
		for _attempt in 6:
			var id: String = FRONT_ROW_KIT[rng.randi() % FRONT_ROW_KIT.size()]
			var path := "%s/%s.glb" % [BUILDING_KIT_DIR, id]
			var s := rng.randf_range(FRONT_ROW_SCALE_MIN, FRONT_ROW_SCALE_MAX)
			var aabb := _kit_aabb_for(path)
			var along := maxf(aabb.size.z, 4.0) * s
			var setback := rng.randf_range(FRONT_ROW_SETBACK_MIN, FRONT_ROW_SETBACK_MAX)
			# Deterministic variation (no RNG draw, so the wall's density
			# pattern is preserved): flip every other block, and swap in a
			# tower every FRONT_ROW_TOWER_PERIOD slots, rescaled to keep the
			# same along-track length.
			var flip := placed_count % 2 == 1
			if placed_count % FRONT_ROW_TOWER_PERIOD == 3:
				var tid: String = FRONT_ROW_TOWERS[(placed_count / FRONT_ROW_TOWER_PERIOD) % FRONT_ROW_TOWERS.size()]
				var tpath := "%s/%s.glb" % [BUILDING_KIT_DIR, tid]
				id = tid
				path = tpath
				aabb = _kit_aabb_for(tpath)
				s = along / maxf(aabb.size.z, 4.0)
			var wide := maxf(aabb.size.x, 4.0) * s
			along = maxf(aabb.size.z, 4.0) * s
			var offset := side * (sidewalk_outer + setback + wide * 0.5)
			var yaw := tangent_yaw(i) + (PI if flip else 0.0) + rng.randf_range(-0.04, 0.04)
			var base := centerline[i] + side_vector(i) * offset
			base.y = 0.0
			var cand_advance := along + _front_row_gap(rng)
			var b := _spawn_kit_building(rng, id, base, yaw, s,
					-side if flip else side)
			if b == null:
				continue
			if not _building_clear(b):
				b.free()
				continue
			_bind_visibility_range(b)
			root.add_child(b)
			occupied.append(Vector3(base.x, 0.0, base.z))
			placed_advance = cand_advance
			placed_count += 1
			break
		next_arc = _arc[i] + (placed_advance if placed_advance > 0.0 else 5.0)
		i += 1
	return root


## Arc gap before the next front-row building: usually a slim joint between
## neighbours, occasionally a wider alley.
func _front_row_gap(rng: RandomNumberGenerator) -> float:
	if rng.randf() < FRONT_ROW_ALLEY_CHANCE:
		return rng.randf_range(FRONT_ROW_ALLEY_MIN, FRONT_ROW_ALLEY_MAX)
	return rng.randf_range(FRONT_ROW_GAP_MIN, FRONT_ROW_GAP_MAX)


## Fades front-row meshes out far from the camera; the skyline covers the
## horizon. Buildings keep casting shadows — the street reads as a real canyon.
func _bind_visibility_range(node: Node3D) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.visibility_range_end = FRONT_ROW_VIS_RANGE
		mi.visibility_range_end_margin = 48.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Cached local-space AABB for a kit variant without leaking the probe instance.
func _kit_aabb_for(path: String) -> AABB:
	if _kit_aabb_cache.has(path):
		return _kit_aabb_cache[path]
	var packed: PackedScene = load(path)
	if packed == null:
		return AABB(Vector3(-5, 0, -5), Vector3(10, 10, 10))
	var probe := packed.instantiate() as Node3D
	var aabb := _kit_local_aabb(path, probe)
	probe.free()
	return aabb


## Combined local-space AABB of all meshes in an instanced kit building.
## Walks with accumulated ancestor transforms (Sketchfab hierarchies carry
## non-trivial matrices on intermediate nodes).
func _kit_local_aabb(path: String, instance: Node3D) -> AABB:
	if _kit_aabb_cache.has(path):
		return _kit_aabb_cache[path]
	var stack: Array = [[instance, Transform3D.IDENTITY]]
	var aabb := AABB()
	var first := true
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var ab: AABB = xf * (n as MeshInstance3D).get_aabb()
			aabb = ab if first else aabb.merge(ab)
			first = false
		for c in n.get_children():
			stack.append([c, xf])
	if first:
		aabb = AABB(Vector3(-5, 0, -5), Vector3(10, 10, 10))
	_kit_aabb_cache[path] = aabb
	return aabb


func _place_city_buildings(rng: RandomNumberGenerator, count: int,
		occupied: Array[Vector3]) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	var n := sample_count()
	var per_side := int(ceil(float(count) * 0.5))
	var first := 18
	var last := n - 18
	var min_spacing := maxf(def.building_min_gap, CITY_BUILDING_MIN_CENTER_DISTANCE)
	var min_lateral := maxf(def.building_min_lateral, CITY_BUILDING_MIN_LATERAL)
	var max_lateral := maxf(def.building_max_lateral, min_lateral + 20.0)
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		for j in per_side:
			if spots.size() >= count:
				break
			var t := float(j) / maxf(float(per_side - 1), 1.0)
			for _attempt in 3:
				var jitter := rng.randf_range(-1.0, 1.0) / maxf(float(per_side), 1.0)
				var candidate_idx := clampi(first + int(float(last - first) * (t + jitter)), first, last)
				var lateral := rng.randf_range(min_lateral, max_lateral)
				var p := centerline[candidate_idx] + side_vector(candidate_idx) * side * lateral
				p.y = 0.0
				if min_distance_to_track(p) < def.road_half_width + ROAD_DECOR_MARGIN + CITY_BUILDING_FOOTPRINT_RADIUS:
					continue
				var clear := true
				for q in occupied:
					if p.distance_squared_to(q) < min_spacing * min_spacing:
						clear = false
						break
				if not clear:
					continue
				occupied.append(p)
				spots.append({"pos": p, "idx": candidate_idx, "lateral": lateral, "side": side})
				break
	return spots


func _make_skyline(rng: RandomNumberGenerator, mats: Array[StandardMaterial3D],
		occupied: Array[Vector3]) -> Node3D:
	var root := Node3D.new()
	root.name = "Skyline"
	var buckets: Dictionary = {}
	for i in def.skyline_count:
		var idx := int(round(float(i) / maxf(float(def.skyline_count), 1.0) * float(centerline.size()))) % centerline.size()
		for attempt in 10:
			# keep the base side from the even spread, flip it on retry
			var side := 1.0 if (i % 2 == 0) == (attempt % 2 == 0) else -1.0
			var lateral := rng.randf_range(125.0, 235.0)
			var p := centerline[idx] + side_vector(idx) * side * lateral
			p.y = 0.0
			if min_distance_to_track(p) < def.road_half_width + ROAD_DECOR_MARGIN + CITY_SKYLINE_FOOTPRINT_RADIUS:
				continue
			var clear := true
			for q in occupied:
				if p.distance_squared_to(q) < CITY_SKYLINE_MIN_GAP * CITY_SKYLINE_MIN_GAP:
					clear = false
					break
			if not clear:
				continue
			occupied.append(p)
			var h := rng.randf_range(26.0, 84.0)
			var w := rng.randf_range(11.0, 22.0)
			var d := rng.randf_range(11.0, 22.0)
			var yaw := tangent_yaw(idx) + rng.randf_range(-0.18, 0.18)
			var transform := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, h, d)), p + Vector3.UP * h * 0.5)
			skyline_transforms.append(transform)
			var mat_idx := rng.randi() % mats.size()
			if not buckets.has(mat_idx):
				buckets[mat_idx] = []
			buckets[mat_idx].append(transform)
			break
	for mat_idx in buckets:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = mats[mat_idx]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = buckets[mat_idx].size()
		multimesh.custom_aabb = AABB(Vector3(-500, -5, -500), Vector3(1000, 140, 1000))
		for i in buckets[mat_idx].size():
			multimesh.set_instance_transform(i, buckets[mat_idx][i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		root.add_child(instance)
	return root


## City skyline built from real kit buildings, scaled up into tower blocks.
## Transforms are appended to skyline_transforms with the unit-cube AABB
## convention, so tools/check_buildings.gd keeps validating them.
func _make_kit_skyline(rng: RandomNumberGenerator, occupied: Array[Vector3],
		root: Node3D) -> Node3D:
	var scenes: Array[PackedScene] = []
	var sizes: Array[Vector3] = []
	for id in BUILDING_KIT_SKYLINE:
		var path := "%s/%s.glb" % [BUILDING_KIT_DIR, id]
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		scenes.append(packed)
		sizes.append(_kit_aabb_for(path).size)
	if scenes.is_empty():
		return root
	for i in def.skyline_count:
		var idx := int(round(float(i) / maxf(float(def.skyline_count), 1.0) * float(centerline.size()))) % centerline.size()
		for attempt in 10:
			var side := 1.0 if (i % 2 == 0) == (attempt % 2 == 0) else -1.0
			var lateral := rng.randf_range(125.0, 235.0)
			var p := centerline[idx] + side_vector(idx) * side * lateral
			p.y = 0.0
			var v := rng.randi() % scenes.size()
			var size := sizes[v]
			var half_diag := Vector2(size.x, size.z).length() * 0.5
			var s_max := CITY_SKYLINE_MAX_HALF_DIAG / maxf(half_diag, 0.1)
			var s := minf(rng.randf_range(1.6, 3.0), s_max)
			var h := size.y * s
			var w := size.x * s
			var d := size.z * s
			var yaw := tangent_yaw(idx) + rng.randf_range(-0.18, 0.18)
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, h, d)),
					p + Vector3.UP * h * 0.5)
			# validate with the same unit-cube AABB convention the checker uses
			if not _skyline_clear(xf):
				continue
			var clear := true
			for q in occupied:
				if p.distance_squared_to(q) < CITY_SKYLINE_MIN_GAP * CITY_SKYLINE_MIN_GAP:
					clear = false
					break
			if not clear:
				continue
			occupied.append(p)
			skyline_transforms.append(xf)
			var instance := scenes[v].instantiate() as Node3D
			instance.position = p
			instance.rotation.y = yaw
			instance.scale = Vector3.ONE * s
			_tune_kit_materials(instance, def.night_racing)
			root.add_child(instance)
			break
	return root


## True when a skyline transform's unit-cube AABB — the convention used by
## tools/check_buildings.gd — stays clear of the asphalt. The enclosing AABB
## of a yaw-rotated block reaches past its true footprint, so validating the
## corners here keeps placement consistent with the checker.
func _skyline_clear(xf: Transform3D) -> bool:
	var box: AABB = xf * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	for corner in _footprint_corners(box):
		if min_distance_to_track(corner) < def.road_half_width + 0.5:
			return false
	return true


## Bottom four corners of an AABB footprint.
static func _footprint_corners(aabb: AABB) -> Array:
	var y := aabb.position.y
	return [
		Vector3(aabb.position.x, y, aabb.position.z),
		Vector3(aabb.end.x, y, aabb.position.z),
		Vector3(aabb.position.x, y, aabb.end.z),
		Vector3(aabb.end.x, y, aabb.end.z),
	]


## Kit GLBs ship with emissive "lights on" windows and neon signs. In daylight
## that reads as glow-through — zero it; at night give it a bit of extra pop.
## Kit buildings ship with baked photo materials; swap the non-emissive ones
## for the shared toon material so the skyline matches the cel-shaded actors.
## Emissive (night window) materials stay standard so they can still glow.
func _tune_kit_materials(instance: Node3D, night: bool) -> void:
	for mi in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as StandardMaterial3D
			if m == null:
				continue
			if m.emission_enabled:
				if not _kit_tuned_materials.has(m):
					_kit_tuned_materials[m] = true
					m.emission_energy_multiplier = 1.5 if night else 0.0
				continue
			var toon: ShaderMaterial = _kit_toon_materials.get(m)
			if toon == null:
				toon = ToonMaterial.from_base(m, -1.0)
				_kit_toon_materials[m] = toon
			(mi as MeshInstance3D).set_surface_override_material(s, toon)


func _make_building(rng: RandomNumberGenerator, spot: Dictionary,
		mats: Array[StandardMaterial3D], concrete: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	root.position = spot.pos
	root.rotation.y = tangent_yaw(int(spot.idx)) + rng.randf_range(-0.04, 0.04)
	var side := float(spot["side"])
	var mat := mats[rng.randi() % mats.size()]
	var kind := rng.randi_range(0, 3)
	var w: float
	var d: float
	var h: float
	var total_h: float
	match kind:
		0: # compact block
			w = rng.randf_range(9.0, 14.0)
			d = rng.randf_range(11.0, 16.0)
			h = rng.randf_range(9.0, 16.0)
			total_h = h
			_add_box(root, Vector3(w, h, d), mat, Vector3(0, h * 0.5, 0))
			_add_roof_details(rng, root, w, d, h, concrete)
		1: # street slab
			w = rng.randf_range(10.0, 16.0)
			d = rng.randf_range(18.0, 24.0)
			h = rng.randf_range(13.0, 22.0)
			total_h = h
			_add_box(root, Vector3(w, h, d), mat, Vector3(0, h * 0.5, 0))
			_add_roof_details(rng, root, w, d, h, concrete)
		2: # podium tower
			w = rng.randf_range(12.0, 17.0)
			d = rng.randf_range(15.0, 21.0)
			h = rng.randf_range(6.0, 9.0)
			_add_box(root, Vector3(w, h, d), mat, Vector3(0, h * 0.5, 0))
			_add_roof_details(rng, root, w, d, h, concrete)
			var tw := w * rng.randf_range(0.55, 0.72)
			var td := d * rng.randf_range(0.55, 0.72)
			var th := rng.randf_range(15.0, 25.0)
			total_h = h + th
			_add_box(root, Vector3(tw, th, td), mat, Vector3(0, h + th * 0.5, 0))
			_add_roof_details(rng, root, tw, td, h + th, concrete)
		_: # stepped tower
			w = rng.randf_range(11.0, 15.0)
			d = rng.randf_range(10.0, 14.0)
			h = rng.randf_range(16.0, 25.0)
			_add_box(root, Vector3(w, h, d), mat, Vector3(0, h * 0.5, 0))
			var w2 := w * rng.randf_range(0.68, 0.80)
			var d2 := d * rng.randf_range(0.68, 0.80)
			var h2 := rng.randf_range(5.0, 10.0)
			total_h = h + h2
			_add_box(root, Vector3(w2, h2, d2), mat, Vector3(0, h + h2 * 0.5, 0))
			_add_roof_details(rng, root, w2, d2, h + h2, concrete)
	_add_camera_blocker(root, w, total_h, d)
	if def.night_racing and rng.randf() < 0.56:
		_add_neon_sign(rng, root, w, h, side)
	return root


func _add_neon_sign(rng: RandomNumberGenerator, parent: Node3D, w: float,
		h: float, side: float) -> void:
	var words := ["NOVA", "DRIVE", "CITY", "24H", "TURBO", "NIGHT", "APEX"]
	var colors := [
		Color(0.08, 2.8, 4.0), Color(3.2, 0.12, 2.4), Color(3.4, 0.7, 0.08),
		Color(2.2, 0.18, 0.08), Color(0.2, 3.2, 1.1),
	]
	var glow: Color = colors[rng.randi() % colors.size()]
	var side_x := -side
	var y := clampf(h * rng.randf_range(0.38, 0.58), 3.2, maxf(h - 2.0, 3.2))
	var panel := BoxMesh.new()
	panel.size = Vector3(0.14, 1.15, rng.randf_range(3.0, 4.4))
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(glow.r * 0.12, glow.g * 0.12, glow.b * 0.12)
	panel_mat.roughness = 0.38
	panel_mat.emission_enabled = true
	panel_mat.emission = glow
	panel_mat.emission_energy_multiplier = 0.32
	panel.material = panel_mat
	var panel_mi := MeshInstance3D.new()
	panel_mi.mesh = panel
	panel_mi.position = Vector3(side_x * (w * 0.5 + 0.09), y, rng.randf_range(-w * 0.22, w * 0.22))
	panel_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(panel_mi)
	var label := Label3D.new()
	label.text = words[rng.randi() % words.size()]
	label.font_size = 128
	label.pixel_size = 0.006
	label.outline_size = 18
	label.modulate = glow
	label.outline_modulate = Color(0.01, 0.012, 0.02)
	label.double_sided = false
	label.position = panel_mi.position + Vector3(side_x * 0.09, 0.0, 0.0)
	label.rotation.y = side_x * PI * 0.5
	parent.add_child(label)
	if rng.randf() < 0.32:
		var light := OmniLight3D.new()
		light.position = panel_mi.position + Vector3(-side_x * 0.45, 0.0, 0.0)
		light.light_color = Color(clampf(glow.r, 0.0, 1.0), clampf(glow.g, 0.0, 1.0), clampf(glow.b, 0.0, 1.0))
		light.light_energy = 1.15
		light.omni_range = 7.5
		light.omni_attenuation = 1.8
		light.shadow_enabled = false
		light.light_volumetric_fog_energy = 0.25
		parent.add_child(light)


func _add_camera_blocker(parent: Node3D, w: float, h: float, d: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	shape.shape = box
	shape.position = Vector3(0.0, h * 0.5, 0.0)
	body.add_child(shape)
	parent.add_child(body)


func _add_box(parent: Node3D, size: Vector3, material: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_roof_details(rng: RandomNumberGenerator, parent: Node3D, w: float,
		d: float, top: float, concrete: StandardMaterial3D) -> void:
	_add_box(parent, Vector3(w + 0.22, 0.18, d + 0.22), concrete, Vector3(0, top + 0.02, 0))
	var parapet_h := rng.randf_range(0.55, 0.85)
	var thickness := 0.24
	for s in [-1.0, 1.0]:
		_add_box(parent, Vector3(w + 0.22, parapet_h, thickness), concrete,
				Vector3(0, top + parapet_h * 0.5, s * (d * 0.5 + 0.11 - thickness * 0.5)))
		_add_box(parent, Vector3(thickness, parapet_h, d + 0.22), concrete,
				Vector3(s * (w * 0.5 + 0.11 - thickness * 0.5), top + parapet_h * 0.5, 0))
	for i in rng.randi_range(1, 3):
		var bw := rng.randf_range(1.0, 3.0)
		var bh := rng.randf_range(0.7, 1.7)
		var bd := rng.randf_range(1.0, 2.4)
		var x := rng.randf_range(-w * 0.35, w * 0.35)
		var z := rng.randf_range(-d * 0.35, d * 0.35)
		_add_box(parent, Vector3(bw, bh, bd), concrete, Vector3(x, top + bh * 0.5 + 0.08, z))


func _make_facade_materials() -> Array[StandardMaterial3D]:
	var mats: Array[StandardMaterial3D] = []
	var emission_energy := {"a": 0.14, "b": 0.18, "c": 0.62, "d": 0.21}
	for suffix in ["a", "b", "c", "d"]:
		var m := StandardMaterial3D.new()
		var albedo := _load_tex(def.facade_night_albedo_path(suffix) if def.night_racing else def.facade_albedo_path(suffix))
		if albedo != null:
			m.albedo_texture = albedo
		m.albedo_color = Color(1.08, 1.08, 1.13)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / 3.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.roughness = 0.85
		m.metallic = 0.0
		var normal := _load_tex(def.facade_normal_path(suffix))
		if normal != null:
			m.normal_enabled = true
			m.normal_texture = normal
		if def.night_racing:
			var emission := _load_tex(def.facade_emission_path(suffix))
			if emission != null:
				m.emission_enabled = true
				m.emission_texture = emission
				m.emission = Color.WHITE
				m.emission_energy_multiplier = emission_energy[suffix]
		mats.append(m)
	return mats


func _make_concrete_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.11, 0.14) if def.night_racing else Color(0.64, 0.64, 0.66)
	m.roughness = 0.82 if def.night_racing else 0.92
	m.metallic = 0.04 if def.night_racing else 0.0
	return m


func _make_contact_shadow(size: float) -> MeshInstance3D:
	if _contact_shadow_mesh == null:
		_contact_shadow_mesh = QuadMesh.new()
		_contact_shadow_mesh.size = Vector2.ONE
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		grad.colors = PackedColorArray([
			Color(0, 0, 0, 0.48), Color(0, 0, 0, 0.16), Color(0, 0, 0, 0.0)
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 128
		tex.height = 128
		_contact_shadow_material = StandardMaterial3D.new()
		_contact_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_contact_shadow_material.albedo_texture = tex
		_contact_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = _contact_shadow_mesh
	mi.material_override = _contact_shadow_material
	mi.scale = Vector3(size, size, 1.0)
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Fallback vegetation from primitive meshes (used when the biome has no
## prop sprites yet).
func _make_primitive_vegetation(rng: RandomNumberGenerator, biome: String) -> Node3D:
	var root := Node3D.new()

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.28
	trunk_mesh.bottom_radius = 0.38
	trunk_mesh.height = 2.4
	var trunk_mat := StandardMaterial3D.new()
	match biome:
		"desert":
			trunk_mat.albedo_color = Color(0.30, 0.48, 0.22)
		"coast":
			trunk_mat.albedo_color = Color(0.42, 0.30, 0.16)
		_:
			trunk_mat.albedo_color = Color(0.36, 0.25, 0.15)
	trunk_mesh.material = trunk_mat

	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.7
	crown_mesh.height = 3.4
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.13, 0.38, 0.16) if biome != "coast" else Color(0.20, 0.52, 0.24)
	crown_mesh.material = crown_mat

	var pine_mesh := CylinderMesh.new()
	pine_mesh.top_radius = 0.08
	pine_mesh.bottom_radius = 1.35
	pine_mesh.height = 3.6
	var pine_mat := StandardMaterial3D.new()
	pine_mat.albedo_color = Color(0.10, 0.30, 0.18)
	pine_mesh.material = pine_mat

	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.16
	arm_mesh.bottom_radius = 0.18
	arm_mesh.height = 1.4
	arm_mesh.material = trunk_mat

	var placed := 0
	var guard := 0
	while placed < 70 and guard < 2000:
		guard += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(120.0, 230.0)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist - 7.0)
		if min_distance_to_track(p) < def.road_half_width + 6.0:
			continue
		var tree := Node3D.new()
		tree.position = p
		var trunk := MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.position.y = 1.2
		match biome:
			"desert":
				trunk.position.y = 1.4
				trunk.scale = Vector3(1.0, 1.15, 1.0)
			"coast":
				trunk.position.y = 1.6
				trunk.scale = Vector3(0.6, 1.4, 0.6)
			"alpine":
				trunk.position.y = 0.8
				trunk.scale = Vector3(1.1, 0.7, 1.1)
		tree.add_child(trunk)
		match biome:
			"desert":
				for s in [-1.0, 1.0]:
					if rng.randf() < 0.7:
						var arm := MeshInstance3D.new()
						arm.mesh = arm_mesh
						arm.position = Vector3(s * 0.42, 1.6, 0)
						arm.rotation.z = s * 0.5
						tree.add_child(arm)
			"alpine":
				var cone := MeshInstance3D.new()
				cone.mesh = pine_mesh
				cone.position.y = 3.0
				cone.scale = Vector3.ONE * rng.randf_range(0.8, 1.5)
				tree.add_child(cone)
			"coast":
				var fronds := MeshInstance3D.new()
				fronds.mesh = crown_mesh
				fronds.position.y = 3.6
				fronds.scale = Vector3(1.5, 0.3, 1.5) * rng.randf_range(0.8, 1.3)
				tree.add_child(fronds)
			_:
				var crown := MeshInstance3D.new()
				crown.mesh = crown_mesh
				crown.position.y = 3.6
				crown.scale = Vector3.ONE * rng.randf_range(0.8, 1.5)
				tree.add_child(crown)
		root.add_child(tree)
		placed += 1
	return root


static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
