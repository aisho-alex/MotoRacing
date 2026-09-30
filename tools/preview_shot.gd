extends SceneTree
## Dev tool: boots a scene and saves a screenshot.
## SHOT=menu           -> main menu
## SHOT=race TRACK=0|1 -> race on city/desert

var _frames := 0
var _setup_done := false
var _start_ms := 0
var _start_index := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if not _setup_done:
		_setup_done = true
		_setup()
		_start_ms = Time.get_ticks_msec()
	if OS.get_environment("ANIMATE_TRACK") == "1":
		var track = root.find_child("Track", true, false)
		var bike = root.find_child("Bike", true, false)
		if track != null and bike != null:
			var idx: int = (_start_index + int(float(_frames) * 0.28)) % int(track.sample_count())
			bike.global_position = track.centerline[idx] + Vector3.UP * 0.6
			bike.rotation = Vector3(0.0, track.tangent_yaw(idx), 0.0)
			bike.velocity = -bike.global_transform.basis.z * 24.0
	var target_ms := 700 if OS.get_environment("SHOT") == "menu" else 5600
	if OS.get_environment("WAIT_MS") != "":
		target_ms = int(OS.get_environment("WAIT_MS"))
	if Time.get_ticks_msec() - _start_ms >= target_ms:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/opencode/preview_shot.png")
		if OS.get_environment("STATS") == "1":
			var bike = root.find_child("Bike", true, false)
			var track = root.find_child("Track", true, false)
			var distance = bike.road_distance_fn.call(bike.global_position) if bike != null and bike.road_distance_fn.is_valid() else -1.0
			var nearest := 0
			var best := INF
			if bike != null and track != null:
				for i in track.sample_count():
					var candidate: float = track.centerline[i].distance_squared_to(bike.global_position)
					if candidate < best:
						best = candidate
						nearest = i
			var facing = (-bike.global_transform.basis.z).dot(track.tangents[nearest]) if bike != null and track != null else 0.0
			var height = bike.global_position.y - track.centerline[nearest].y if bike != null and track != null else 0.0
			if OS.get_environment("NEAR_MESHES") == "1":
				var cam := root.get_camera_3d()
				var buildings := root.find_child("Buildings", true, false)
				if buildings != null:
					for mesh in buildings.find_children("*", "MeshInstance3D", true, false):
						var p: Vector3 = mesh.global_position
						var dist: float = p.distance_to(cam.global_position)
						if dist < 80.0:
							var material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
							var world_aabb: AABB = mesh.global_transform * mesh.get_aabb()
							var min_screen := Vector2(99999.0, 99999.0)
							var max_screen := Vector2(-99999.0, -99999.0)
							for corner in [world_aabb.position, world_aabb.end,
									Vector3(world_aabb.position.x, world_aabb.position.y, world_aabb.end.z),
									Vector3(world_aabb.position.x, world_aabb.end.y, world_aabb.position.z),
									Vector3(world_aabb.end.x, world_aabb.position.y, world_aabb.end.z),
									Vector3(world_aabb.end.x, world_aabb.end.y, world_aabb.position.z),
									Vector3(world_aabb.position.x, world_aabb.end.y, world_aabb.end.z),
									Vector3(world_aabb.end.x, world_aabb.position.y, world_aabb.position.z)]:
								var sp := cam.unproject_position(corner)
								min_screen = Vector2(minf(min_screen.x, sp.x), minf(min_screen.y, sp.y))
								max_screen = Vector2(maxf(max_screen.x, sp.x), maxf(max_screen.y, sp.y))
							print("near_building path=", mesh.get_path(), " dist=", dist,
									" screen=", min_screen, ":", max_screen,
									" aabb=", mesh.get_aabb(),
									" albedo=", material.albedo_color if material != null else Color.NAVY_BLUE,
									" texture=", material.albedo_texture.resource_path if material != null and material.albedo_texture != null else "none",
									" emission=", material.emission_energy_multiplier if material != null and material.emission_enabled else -1.0)
					for instance in buildings.find_children("*", "MultiMeshInstance3D", true, false):
						print("multimesh path=", instance.get_path(), " dist=", instance.global_position.distance_to(cam.global_position),
								" aabb=", instance.get_aabb())
			print("draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					" objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
					" primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					" fps=", Performance.get_monitor(Performance.TIME_FPS),
					" speed=", bike.velocity.length() if bike != null else 0.0,
					" nitro=", bike.is_nitro_active() if bike != null else false,
					" road_distance=", distance,
					" nearest=", nearest,
					" facing=", facing,
					" height=", height,
					" half_width=", track.def.road_half_width if track != null else 0.0)
		print("saved /tmp/opencode/preview_shot.png after ", _frames, " frames")
		return true
	return false


func _setup() -> void:
	var shot := OS.get_environment("SHOT")
	var scene_path := "res://scenes/main.tscn"
	if shot == "menu":
		scene_path = "res://scenes/menu.tscn"
	else:
		var game := root.get_node_or_null("/root/Game")
		if game != null and OS.get_environment("TRACK") != "":
			game.track_index = int(OS.get_environment("TRACK"))
		if game != null and OS.get_environment("BIKE") != "":
			game.bike_index = int(OS.get_environment("BIKE"))
	var main := (load(scene_path) as PackedScene).instantiate()
	root.add_child(main)
	var start_index := OS.get_environment("START_INDEX")
	if start_index != "":
		var track = main.get("track")
		var bike = main.get("bike")
		var idx := clampi(int(start_index), 0, int(track.sample_count() - 1))
		_start_index = idx
		bike.reset_to(track.centerline[idx], track.tangent_yaw(idx))
		main.get("cam").snap_behind(bike)
	if OS.get_environment("AUTO_DRIVE") == "1":
		var bike = main.get("bike")
		var track = main.get("track")
		var driver = load("res://scripts/ai_driver.gd").new(track, 1.0, 0.0)
		driver.resync(bike)
		bike.driver = driver
		bike.control_enabled = true
	if OS.get_environment("HIDE_WORLD") == "1":
		var track := main.get_node_or_null("Track")
		if track != null:
			track.visible = false
		for node in main.get_children():
			if node.name == "Bike" or node.name.begins_with("AI"):
				node.visible = false
	elif OS.get_environment("HIDE_BUILDINGS") == "1":
		var buildings := main.find_child("Buildings", true, false)
		if buildings != null:
			buildings.visible = false
	elif OS.get_environment("HIDE_DECOR") == "1":
		var decor := main.find_child("Decor", true, false)
		if decor != null:
			decor.visible = false
	elif OS.get_environment("HIDE_FACADE_EMISSION") == "1":
		var buildings := main.find_child("Buildings", true, false)
		if buildings != null:
			for mesh in buildings.find_children("*", "MeshInstance3D", true, false):
				var material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
				if material != null and material.emission_texture != null:
					material.emission_enabled = false
	elif OS.get_environment("HIDE_NEON") == "1":
		var buildings := main.find_child("Buildings", true, false)
		if buildings != null:
			for light in buildings.find_children("*", "OmniLight3D", true, false):
				light.visible = false
			for label in buildings.find_children("*", "Label3D", true, false):
				label.visible = false
	elif OS.get_environment("HIDE_STREETLIGHTS") == "1":
		var street_lights := main.find_child("StreetLights", true, false)
		if street_lights != null:
			street_lights.visible = false
	elif OS.get_environment("HIDE_REFLECTIONS") == "1":
		var reflections := main.find_child("ReflectionProbes", true, false)
		if reflections != null:
			reflections.visible = false
	elif OS.get_environment("HIDE_SPEED_VFX") == "1":
		var speed_vfx := main.find_child("SpeedStreaks", true, false)
		if speed_vfx != null:
			speed_vfx.visible = false
	elif OS.get_environment("HIDE_HEADLIGHTS") == "1":
		var player_bike := main.get_node_or_null("Bike")
		if player_bike != null:
			for light in player_bike.find_children("*", "SpotLight3D", true, false):
				light.visible = false
	elif OS.get_environment("HIDE_BIKE_VFX") == "1":
		var player_bike := main.get_node_or_null("Bike")
		if player_bike != null:
			for particles in player_bike.find_children("*", "GPUParticles3D", true, false):
				particles.visible = false
