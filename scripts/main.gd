extends Node3D
## Entry point: builds the world (sky, light, track, bike, camera, HUD),
## runs the race state machine (countdown -> racing -> finished) and
## handles restarting with R.

enum State { COUNTDOWN, RACING, FINISHED }

const COUNTDOWN_TIME := 3.0
const GO_MESSAGE_TIME := 0.9
const MENU_RETURN_DELAY := 6.0
const OPPONENT_IDS := ["scrambler_01", "cruiser_01", "super_01"]
const OPPONENT_SKILLS := [0.90, 0.95, 1.0]
const OPPONENT_OFFSETS := [0.0, -2.2, 2.2]  # personal corridors beside the center
const RUBBER_GAIN := 0.25  # pace offset per lap-fraction gap to the player

var state: State = State.COUNTDOWN
var state_timer := COUNTDOWN_TIME
var go_timer := 0.0
var _last_countdown := 3

var track: TrackBuilder
var bike: RaceBike
var cam: ChaseCamera
var tracker: LapTracker
var hud: Hud
var police: PoliceManager
var traffic: TrafficManager
var racers: Array = []  # {bike, progress, pos, yaw, player}


func _ready() -> void:
	var tdef := Game.track_def()
	_build_environment(tdef)
	Audio.play_music("race_%s" % tdef.biome)

	track = TrackBuilder.new()
	track.name = "Track"
	track.def = tdef
	add_child(track)
	track.build()

	bike = RaceBike.new()
	bike.name = "Bike"
	bike.def = Game.player_bike_def()
	bike.night_lights = tdef.night_racing
	add_child(bike)
	bike.road_half_width = tdef.road_half_width
	_place_bike_at_start()
	racers.append(_racer_entry(bike, true, bike.global_position, track.tangent_yaw(0)))
	_spawn_opponents()

	tracker = LapTracker.new()
	tracker.name = "LapTracker"
	add_child(tracker)
	tracker.setup(track, bike)
	bike.road_distance_fn = Callable(tracker, "road_distance_to")
	tracker.lap_changed.connect(_on_lap_changed)
	tracker.lap_finished.connect(_on_lap_finished)
	tracker.race_finished.connect(_on_race_finished)

	cam = ChaseCamera.new()
	cam.name = "ChaseCamera"
	add_child(cam)
	cam.snap_behind(bike)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.reset_race()
	hud.show_countdown(3)

	bike.wiped_out.connect(_on_player_wipeout)
	bike.remounted.connect(_on_player_remount)

	police = PoliceManager.new()
	police.name = "PoliceManager"
	add_child(police)
	var rider_bikes: Array = []
	for r in racers:
		rider_bikes.append(r.bike)
	police.setup(track, bike, rider_bikes)
	police.busted.connect(_on_busted)
	police.cop_down.connect(_on_cop_down)

	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(track, bike)

	add_child(TouchControls.new())


func _spawn_opponents() -> void:
	var n := track.sample_count()
	for k in OPPONENT_IDS.size():
		var path := "res://assets/data/bikes/%s.tres" % OPPONENT_IDS[k]
		if not ResourceLoader.exists(path):
			continue
		var def := load(path) as BikeDef
		var ai := RaceBike.new()
		ai.name = "AI%d" % k
		ai.def = def
		ai.night_lights = track.def.night_racing
		ai.is_opponent = true
		ai.road_half_width = track.def.road_half_width
		add_child(ai)
		# grid ahead of the player along the start straight: player starts P4
		var idx := (10 + k * 8) % n
		var side := track.side_vector(idx) * (1.8 if k % 2 == 0 else -1.8)
		var pos := track.centerline[idx] + side
		var yaw := track.tangent_yaw(idx)
		ai.reset_to(pos, yaw)
		var driver := AiDriver.new(track, OPPONENT_SKILLS[k], OPPONENT_OFFSETS[k % OPPONENT_OFFSETS.size()])
		driver.base_speed_mult = Game.ai_speed_scale()
		driver.speed_mult = driver.base_speed_mult
		driver.aggression = clampf(0.35 + 0.40 * OPPONENT_SKILLS[k] + 0.05 * Game.track_tier, 0.2, 0.9)
		driver.resync(ai)
		ai.driver = driver
		racers.append(_racer_entry(ai, false, pos, yaw))
	# every racer sees all bikes for avoidance and Road Rash combat
	var all: Array[RaceBike] = []
	for r in racers:
		all.append(r.bike)
	for r in racers:
		r.bike.combat_targets = all
		if not r.player:
			r.bike.driver.bikes = all


func _racer_entry(racer: RaceBike, is_player: bool, spawn_pos: Vector3, spawn_yaw: float) -> Dictionary:
	var prog := RacerProgress.new()
	prog.bike = racer
	prog.track = track
	prog.reset()
	return {"bike": racer, "progress": prog, "pos": spawn_pos, "yaw": spawn_yaw, "player": is_player}


## Arcade rubber-band: an opponent far behind the player gets up to +10% pace,
## one far ahead eases off up to -8%. Keeps the pack wheel-to-wheel without
## overriding the base campaign pace (BikeTuning.ai_speed_scale).
func _apply_rubber_band(r: Dictionary, player_metric: float, delta: float) -> void:
	var driver: AiDriver = r.bike.driver
	if driver == null:
		return
	var gap: float = player_metric - r.progress.progress_metric()  # >0 = AI behind
	var target := driver.base_speed_mult + clampf(gap * RUBBER_GAIN, -0.08, 0.10)
	driver.speed_mult = lerpf(driver.speed_mult, target, 1.0 - exp(-1.5 * delta))


## Live race position of the player (1-based).
func _player_position() -> int:
	var mine := tracker.progress_metric()
	var pos := 1
	for r in racers:
		if r.player:
			continue
		if r.progress.progress_metric() > mine:
			pos += 1
	return pos


func _set_racing_control(enabled: bool) -> void:
	bike.control_enabled = enabled
	for r in racers:
		if not r.player:
			r.bike.control_enabled = enabled


func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.RACING
				_set_racing_control(true)
				tracker.start_race()
				police.start()
				traffic.start()
				hud.show_go()
				Audio.play_ui("countdown_go")
				go_timer = GO_MESSAGE_TIME
			else:
				var n := int(ceilf(state_timer))
				if n != _last_countdown:
					_last_countdown = n
					hud.show_countdown(n)
					Audio.play_ui("countdown_%d" % clampi(n, 1, 3))
		State.RACING:
			if go_timer > 0.0:
				go_timer -= delta
				if go_timer <= 0.0:
					hud.clear_center()
		State.FINISHED:
			pass
	hud.set_speed(bike.speed_kmh())
	hud.set_nitro(bike.nitro_ratio(), bike.is_nitro_active())
	hud.set_health(bike.health / RaceBike.HEALTH_MAX)
	hud.update_race_info(tracker.lap_time, tracker.best_lap, tracker.last_lap)
	var player_metric := tracker.progress_metric()
	for r in racers:
		if not r.player:
			r.progress.update()
			_apply_rubber_band(r, player_metric, delta)
	hud.set_position(_player_position(), racers.size())
	hud.set_police(police.is_hunting())
	if Input.is_action_just_pressed("restart"):
		_restart_race()


func _place_bike_at_start() -> void:
	bike.reset_to(track.centerline[0], track.tangent_yaw(0))


func _restart_race() -> void:
	state = State.COUNTDOWN
	state_timer = COUNTDOWN_TIME
	go_timer = 0.0
	_last_countdown = -1
	_set_racing_control(false)
	_place_bike_at_start()
	for r in racers:
		if r.player:
			continue
		r.bike.reset_to(r.pos, r.yaw)
		r.bike.driver.resync(r.bike)
		r.progress.reset()
	tracker.reset()
	cam.snap_behind(bike)
	hud.reset_race()
	hud.show_countdown(3)
	if police != null:
		police.clear()
	if traffic != null:
		traffic.clear()
	track.reset_pickups()


func _on_lap_changed(current: int, total: int) -> void:
	hud.set_lap(current, total)


func _on_player_wipeout(_bike: RaceBike) -> void:
	hud.show_message("WIPEOUT!", Color(1.0, 0.42, 0.35))


func _on_player_remount(_bike: RaceBike) -> void:
	hud.clear_center()


func _on_lap_finished(lap_time: float, best: float) -> void:
	Audio.play_ui("lap")
	hud.update_race_info(tracker.lap_time, best, lap_time)


func _on_race_finished(total: float) -> void:
	state = State.FINISHED
	_set_racing_control(false)
	police.stop()
	traffic.stop()
	var pos := _player_position()
	var earned := Game.record_result(true, pos)
	_burst_confetti()
	Audio.play_ui("finish")
	hud.show_finish(total, tracker.best_lap, pos, earned)
	get_tree().create_timer(MENU_RETURN_DELAY).timeout.connect(_return_to_menu)


## Caught by the police: the race is over with no prize.
func _on_busted() -> void:
	if state != State.RACING:
		return
	state = State.FINISHED
	_set_racing_control(false)
	police.stop()
	traffic.stop()
	Audio.play_ui("error")
	hud.show_message("BUSTED!", Color(1.0, 0.35, 0.2),
		"%s — no prize\nPress R to restart" % Game.track_name())
	get_tree().create_timer(MENU_RETURN_DELAY).timeout.connect(_return_to_menu)


func _on_cop_down(bonus: int) -> void:
	Game.add_credits(bonus)
	hud.show_message("COP DOWN!", Color(0.45, 0.85, 1.0), "+%d CREDITS" % bonus)


## Returns to the menu after the finish screen. The timer cannot be cancelled,
## so the state guard keeps a manual R-restart from being interrupted.
func _return_to_menu() -> void:
	if state != State.FINISHED:
		return
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _burst_confetti() -> void:
	var p := GPUParticles3D.new()
	p.name = "Confetti"
	p.one_shot = true
	p.amount = 90
	p.lifetime = 1.8
	p.explosiveness = 1.0
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -7.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.3, 0.3))
	grad.set_color(1, Color(0.3, 0.55, 1.0))
	grad.add_point(0.25, Color(1.0, 0.85, 0.25))
	grad.add_point(0.5, Color(0.35, 1.0, 0.5))
	grad.add_point(0.75, Color(1.0, 0.5, 0.9))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_initial_ramp = ramp
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.28)
	p.draw_pass_1 = mesh
	add_child(p)
	p.global_position = bike.global_position + Vector3.UP * 2.5
	p.emitting = true
	get_tree().create_timer(5.0).timeout.connect(p.queue_free)


func _build_environment(tdef: TrackDef) -> void:
	var sun := DirectionalLight3D.new()
	if tdef.night_racing:
		sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
		sun.light_color = Color(0.48, 0.62, 1.0)
		sun.light_energy = 0.26
		sun.light_specular = 0.35
	else:
		sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
		sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if ResourceLoader.exists(tdef.sky_path()):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(tdef.sky_path())
		sky.sky_material = pano
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		if tdef.night_racing:
			sky_mat.sky_top_color = Color(0.008, 0.014, 0.045)
			sky_mat.sky_horizon_color = Color(0.20, 0.055, 0.018)
			sky_mat.ground_bottom_color = Color(0.004, 0.006, 0.012)
			sky_mat.ground_horizon_color = Color(0.12, 0.025, 0.008)
		else:
			sky_mat.sky_top_color = Color(0.22, 0.48, 0.84)
			sky_mat.sky_horizon_color = Color(0.71, 0.82, 0.92)
			sky_mat.ground_bottom_color = Color(0.2, 0.24, 0.2)
			sky_mat.ground_horizon_color = Color(0.65, 0.75, 0.85)
		sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.glow_enabled = true
	env.adjustment_enabled = true
	if tdef.night_racing:
		env.background_energy_multiplier = 0.70
		env.ambient_light_energy = 0.102
		env.ambient_light_sky_contribution = 0.50
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 4.0
		env.tonemap_exposure = 1.10
		env.fog_enabled = true
		env.fog_light_color = Color(0.022, 0.034, 0.075)
		env.fog_light_energy = 0.85
		env.fog_density = 0.0042
		env.fog_sky_affect = 0.10
		env.fog_aerial_perspective = 0.30
		env.fog_height = 2.0
		env.fog_height_density = 0.010
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_normalized = true
		env.glow_hdr_threshold = 1.05
		env.glow_hdr_scale = 1.35
		env.glow_intensity = 0.68
		env.glow_strength = 0.9
		env.glow_bloom = 0.035
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.08
		env.adjustment_saturation = 1.12
		env.ssao_enabled = true
		env.ssao_radius = 2.2
		env.ssao_intensity = 1.75
		env.ssao_power = 1.7
		env.ssao_detail = 0.7
		env.ssao_horizon = 0.08
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_cascade0_distance = 18.0
		env.sdfgi_min_cell_size = 0.22
		env.sdfgi_energy = 0.75
		env.sdfgi_normal_bias = 1.2
		env.sdfgi_probe_bias = 1.2
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_in = 0.12
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.18
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.007
		env.volumetric_fog_albedo = Color(0.36, 0.42, 0.58)
		env.volumetric_fog_emission = Color(0.018, 0.028, 0.070)
		env.volumetric_fog_emission_energy = 0.28
		env.volumetric_fog_gi_inject = 0.70
		env.volumetric_fog_anisotropy = 0.60
		env.volumetric_fog_length = 96.0
		env.volumetric_fog_ambient_inject = 0.20
		env.volumetric_fog_sky_affect = 0.22
	else:
		env.ambient_light_energy = 1.0
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		env.fog_light_color = Color(0.65, 0.72, 0.82)
		env.fog_density = 0.004
		env.fog_sky_affect = 0.2
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05
		env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)
