extends SceneTree
## Dev tool: checks the picture-quality presets (GraphicsQuality) and the Game
## setting plumbing: preset values reach the viewport/env/light, AUTO resolves by
## platform, and the choice survives a save/load round-trip. The real
## progress.cfg is snapshotted and restored afterwards.
## Run: godot --headless --path . -s tools/check_quality.gd

const SAVE := "user://progress.cfg"

var _deferred := true
var _failures := 0


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	_run()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
	return true


func _run() -> void:
	var backup: Variant = _read(SAVE)

	_check_presets()
	_check_auto_mapping()
	_check_round_trip()

	_restore(SAVE, backup)


func _check_presets() -> void:
	var sun := _shadow_sun()
	root.add_child(sun)
	for level in GraphicsQuality.LEVELS:
		var p: Dictionary = GraphicsQuality.PRESETS[level]
		var vp := SubViewport.new()
		GraphicsQuality.apply_viewport(vp, level)
		_report("%s viewport scale=%.3f" % [level, vp.scaling_3d_scale],
				is_equal_approx(vp.scaling_3d_scale, float(p["scale_3d"])))
		_report("%s viewport msaa=%d" % [level, vp.msaa_3d],
				vp.msaa_3d == int(p["msaa"]))
		_report("%s viewport deband=%s" % [level, vp.use_debanding],
				vp.use_debanding == bool(p["deband"]))
		_report("%s shadow atlas=%d" % [level, vp.positional_shadow_atlas_size],
				vp.positional_shadow_atlas_size == int(p["shadow_atlas"]))
		vp.free()

		var env := _night_env()
		GraphicsQuality.apply_env(env, sun, level, true)
		_report("%s sun shadow mode=%d" % [level, sun.directional_shadow_mode],
				sun.directional_shadow_mode == int(p["shadow_mode"]))
		_report("%s sun shadow distance=%.0f" % [level, sun.directional_shadow_max_distance],
				is_equal_approx(sun.directional_shadow_max_distance, float(p["shadow_distance"])))
		var heavy_out := not env.ssao_enabled and not env.ssr_enabled \
				and not env.sdfgi_enabled and not env.volumetric_fog_enabled
		if bool(p["heavy"]):
			_report("%s keeps night post stack" % level, not heavy_out)
		else:
			_report("%s drops night post stack" % level, heavy_out)
		env.free()
	root.remove_child(sun)
	sun.free()


## AUTO must pick LOW on mobile (FORCE_TOUCH / export feature) and HIGH on desktop.
func _check_auto_mapping() -> void:
	var gs: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs)
	gs.quality = "auto"
	var mobile := TouchControls.mobile_layout_active()
	var expected := "low" if mobile else "high"
	_report("auto -> %s (mobile=%s)" % [gs.effective_quality(), mobile],
			gs.effective_quality() == expected)
	_report("auto label", gs.quality_label() == "AUTO (%s)" % expected.to_upper())
	root.remove_child(gs)
	gs.free()


func _check_round_trip() -> void:
	var gs: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs)
	gs.set_quality("low")
	_report("set quality low", gs.quality == "low")
	_report("low label is LOW", gs.effective_quality() == "low" and gs.quality_label() == "LOW")
	root.remove_child(gs)
	gs.free()

	var reloaded: Node = load("res://scripts/game_state.gd").new()
	root.add_child(reloaded)
	_report("quality persisted", reloaded.quality == "low")
	# cycle wraps low -> medium
	reloaded.cycle_quality(1)
	_report("cycle low->medium", reloaded.quality == "medium")
	_report("reject unknown", not reloaded.set_quality("ultra") and reloaded.quality == "medium")
	root.remove_child(reloaded)
	reloaded.free()


func _night_env() -> Environment:
	var env := Environment.new()
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.sdfgi_enabled = true
	env.volumetric_fog_enabled = true
	return env


func _shadow_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	return sun


func _read(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	return data


func _restore(path: String, backup: Variant) -> void:
	if backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(backup)
	f.close()


func _report(label: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_failures += 1
