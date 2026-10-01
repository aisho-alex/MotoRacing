extends SceneTree
## Dev tool: validates the four added mechanics —
##   * track records (Game): best lap / full-race time per track+tier, persistence
##   * health pickups: add_health heal + clamp, pickup amount
##   * slipstream: draft lock behind a rider, release when the target is gone
##   * near-miss: clean tight pass pays nitro, contact/wide passes do not, chain x2
## and the pickup placement on every track (counts, no shared slots).
## The real progress.cfg is snapshotted and restored afterwards, because records
## are persisted through Game._save_progress().
## Run: godot --headless --path . -s tools/check_mechanics.gd

const SAVE := "user://progress.cfg"
const TRACKS_DIR := "res://assets/data/tracks"

var _deferred := true
var BikeScript
var DefScript
var TrafficScript
var HealthScript
var NitroScript


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	BikeScript = load("res://scripts/race_bike.gd")
	DefScript = load("res://scripts/bike_def.gd")
	TrafficScript = load("res://scripts/traffic.gd")
	HealthScript = load("res://scripts/health_pickup.gd")
	NitroScript = load("res://scripts/nitro_pickup.gd")
	var backup := _read(SAVE)
	var failures := 0
	failures += _check_health_pickup()
	failures += _check_traffic_pickups()
	failures += _check_draft()
	failures += _check_near_miss()
	failures += _check_records()
	failures += _check_pickup_placement()
	_restore(SAVE, backup)
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


# --- helpers ---------------------------------------------------------------

func _make_bike() -> Node:
	var b = BikeScript.new()
	b.def = DefScript.load_default()
	b.is_opponent = true
	root.add_child(b)
	b.control_enabled = true
	b.velocity = Vector3.ZERO
	return b


func _check_health_pickup() -> int:
	var failures := 0
	if float(HealthScript.AMOUNT) <= 0.0:
		print("health: pickup amount must be positive")
		failures += 1
	var a = _make_bike()
	a.health = 40.0
	a.add_health(float(HealthScript.AMOUNT))
	if not is_equal_approx(a.health, 40.0 + float(HealthScript.AMOUNT)):
		print("health: heal wrong (%.1f)" % a.health)
		failures += 1
	a.health = BikeScript.HEALTH_MAX - 5.0
	a.add_health(float(HealthScript.AMOUNT))
	if not is_equal_approx(a.health, BikeScript.HEALTH_MAX):
		print("health: heal not clamped to max (%.1f)" % a.health)
		failures += 1
	a.queue_free()
	return failures


## Traffic cars are RaceBikes too, so they must be filtered out of the pickup and
## boost-pad handlers: only racers (player + AI opponents) collect them.
func _check_traffic_pickups() -> int:
	var failures := 0
	# nitro bottle: ignored by traffic, still collected by a racer
	var nitro_pickup = NitroScript.new()
	root.add_child(nitro_pickup)
	var traffic = _make_bike()
	traffic.is_traffic = true
	traffic.nitro = 10.0
	nitro_pickup._on_body_entered(traffic)
	if not is_equal_approx(traffic.nitro, 10.0):
		print("traffic: nitro bottle collected by a traffic car (%.1f)" % traffic.nitro)
		failures += 1
	if nitro_pickup._respawn > 0.0:
		print("traffic: nitro bottle was consumed by a traffic car")
		failures += 1
	var racer = _make_bike()
	racer.nitro = 10.0
	nitro_pickup._on_body_entered(racer)
	if racer.nitro <= 10.0:
		print("traffic: nitro bottle no longer collected by a racer (%.1f)" % racer.nitro)
		failures += 1
	# health pack: ignored by traffic, still collected by a racer
	var health_pickup = HealthScript.new()
	root.add_child(health_pickup)
	var traffic2 = _make_bike()
	traffic2.is_traffic = true
	traffic2.health = 20.0
	health_pickup._on_body_entered(traffic2)
	if not is_equal_approx(traffic2.health, 20.0):
		print("traffic: health pack collected by a traffic car (%.1f)" % traffic2.health)
		failures += 1
	if health_pickup._respawn > 0.0:
		print("traffic: health pack was consumed by a traffic car")
		failures += 1
	var racer2 = _make_bike()
	racer2.health = 20.0
	health_pickup._on_body_entered(racer2)
	if racer2.health <= 20.0:
		print("traffic: health pack no longer collected by a racer (%.1f)" % racer2.health)
		failures += 1
	# boost pad: ignored by traffic, still fires for a racer
	var track := TrackBuilder.new()
	root.add_child(track)
	var traffic3 = _make_bike()
	traffic3.is_traffic = true
	traffic3._pad_boost_timer = 0.0
	track._on_pad_body_entered(traffic3)
	if traffic3._pad_boost_timer > 0.0:
		print("traffic: boost pad fired for a traffic car (%.2f)" % traffic3._pad_boost_timer)
		failures += 1
	var racer3 = _make_bike()
	racer3._pad_boost_timer = 0.0
	track._on_pad_body_entered(racer3)
	if racer3._pad_boost_timer <= 0.0:
		print("traffic: boost pad no longer fires for a racer")
		failures += 1
	for n in [nitro_pickup, health_pickup, track, traffic, traffic2, traffic3, racer, racer2, racer3]:
		n.queue_free()
	return failures


func _check_draft() -> int:
	var failures := 0
	var a = _make_bike()
	var b = _make_bike()
	a.velocity = Vector3(0, 0, -15.0)
	b.velocity = Vector3(0, 0, -15.0)
	a.combat_targets = [b]
	# target directly ahead -> locks the draft
	b.global_position = a.global_position + Vector3(0, 0, -6.0)
	a._draft_mult = 1.0
	for _i in 40:
		a._update_draft(0.05, 15.0)
	if not a._drafting:
		print("draft: target ahead not detected")
		failures += 1
	if not (a._draft_mult > 1.0 and a._draft_mult <= BikeScript.DRAFT_MAX_MULT + 0.0001):
		print("draft: multiplier out of range (%.3f)" % a._draft_mult)
		failures += 1
	# target behind -> releases
	b.global_position = a.global_position + Vector3(0, 0, 6.0)
	for _i in 80:
		a._update_draft(0.05, 15.0)
	if a._drafting or a._draft_mult > 1.001:
		print("draft: not released behind target (mult=%.3f)" % a._draft_mult)
		failures += 1
	# target too slow -> no draft
	b.global_position = a.global_position + Vector3(0, 0, -6.0)
	b.velocity = Vector3.ZERO
	for _i in 80:
		a._update_draft(0.05, 15.0)
	if a._drafting or a._draft_mult > 1.001:
		print("draft: slow target should not draft (mult=%.3f)" % a._draft_mult)
		failures += 1
	a.queue_free()
	b.queue_free()
	return failures


func _check_near_miss() -> int:
	var failures := 0
	var mgr = TrafficScript.new()
	root.add_child(mgr)
	var a = _make_bike()
	a.velocity = Vector3(0, 0, -15.0)
	var car = _make_bike()
	mgr.player = a
	mgr.cars = [car]
	var hits: Array = []
	mgr.near_miss.connect(func(chain, reward): hits.append([chain, reward]))
	# clean tight pass at 2.4 m lateral -> reward
	_pass(mgr, a, car, 2.4)
	if hits.size() != 1 or int(hits[0][0]) != 1:
		print("near-miss: clean pass did not pay (%s)" % str(hits))
		failures += 1
	elif not is_equal_approx(float(hits[0][1]), float(TrafficScript.NM_REWARD)):
		print("near-miss: wrong first reward (%.1f)" % float(hits[0][1]))
		failures += 1
	# contact pass at 1.0 m -> no reward
	_pass(mgr, a, car, 1.0)
	if hits.size() != 1:
		print("near-miss: contact pass wrongly paid")
		failures += 1
	# wide pass at 4.0 m -> no reward
	_pass(mgr, a, car, 4.0)
	if hits.size() != 1:
		print("near-miss: wide pass wrongly paid")
		failures += 1
	# two more clean passes -> chain reaches 3 and doubles
	_pass(mgr, a, car, 2.4)
	_pass(mgr, a, car, 2.4)
	if hits.size() != 3:
		print("near-miss: chained passes not registered (%d)" % hits.size())
		failures += 1
	elif int(hits[2][0]) < int(TrafficScript.NM_CHAIN_TARGET):
		print("near-miss: chain count too low (%d)" % int(hits[2][0]))
		failures += 1
	elif not is_equal_approx(float(hits[2][1]), float(TrafficScript.NM_REWARD) * 2.0):
		print("near-miss: chain reward not doubled (%.1f)" % float(hits[2][1]))
		failures += 1
	a.queue_free()
	car.queue_free()
	mgr.queue_free()
	return failures


## Simulates the player slipping past a car at the given lateral offset: the car
## is placed just ahead, then just behind, with a frame in between so the
## minimum distance and the ahead->behind crossing are both sampled.
func _pass(mgr, player, car, lateral: float) -> void:
	car.global_position = player.global_position + Vector3(lateral, 0, -0.5)
	mgr._update_near_miss(0.05)
	car.global_position = player.global_position + Vector3(lateral, 0, 0.5)
	mgr._update_near_miss(0.05)


func _check_records() -> int:
	var failures := 0
	var gs = _new_game()
	gs.records = {}
	gs.unlocked_tracks = 3
	if gs.best_lap_at(0, 0) >= 0.0:
		print("records: a fresh game should have no lap record")
		failures += 1
	if not gs.record_lap(0, 0, 50.0):
		print("records: first lap record rejected")
		failures += 1
	if not is_equal_approx(gs.best_lap_at(0, 0), 50.0):
		print("records: lap record not stored (%.2f)" % gs.best_lap_at(0, 0))
		failures += 1
	if gs.record_lap(0, 0, 55.0):
		print("records: slower lap reported as a record")
		failures += 1
	if not gs.record_lap(0, 0, 48.0) or not is_equal_approx(gs.best_lap_at(0, 0), 48.0):
		print("records: faster lap did not replace the record")
		failures += 1
	if not gs.record_race(0, 0, 160.0) or gs.record_race(0, 0, 170.0):
		print("records: race record logic is wrong")
		failures += 1
	if not gs.record_race(0, 0, 150.0) or not is_equal_approx(gs.best_race_at(0, 0), 150.0):
		print("records: faster race did not replace the record")
		failures += 1
	if gs.record_lap(99, 0, 10.0) or gs.record_lap(0, 9, 10.0):
		print("records: invalid slot accepted a record")
		failures += 1
	# tiers are independent
	if gs.best_lap_at(0, 1) >= 0.0:
		print("records: tier 2 leaked a tier 1 record")
		failures += 1
	gs.record_lap(0, 1, 60.0)
	if not is_equal_approx(gs.best_lap_at(0, 1), 60.0) or not is_equal_approx(gs.best_lap_at(0, 0), 48.0):
		print("records: per-tier records not isolated")
		failures += 1
	if gs.record_hint(0, 0) == "no record":
		print("records: hint should not say 'no record' when records exist")
		failures += 1
	# persistence roundtrip
	var loaded = _new_game()
	if not is_equal_approx(loaded.best_lap_at(0, 0), 48.0):
		print("records: lap record lost on reload (%.2f)" % loaded.best_lap_at(0, 0))
		failures += 1
	if not is_equal_approx(loaded.best_race_at(0, 0), 150.0):
		print("records: race record lost on reload (%.2f)" % loaded.best_race_at(0, 0))
		failures += 1
	if not is_equal_approx(loaded.best_lap_at(0, 1), 60.0):
		print("records: tier record lost on reload")
		failures += 1
	return failures


func _check_pickup_placement() -> int:
	var failures := 0
	for id in _discover_tracks():
		var res := load("res://assets/data/tracks/%s.tres" % id) as TrackDef
		if res == null:
			continue
		var track := TrackBuilder.new()
		track.name = "Track"
		track.def = res
		root.add_child(track)
		track.build()
		var nitro := track.find_child("NitroPickups", true, false)
		var health := track.find_child("HealthPickups", true, false)
		if nitro == null or nitro.get_child_count() != int(track.NITRO_BOTTLE_COUNT):
			print("%s: nitro pickup count wrong (%s)" % [id, "none" if nitro == null else str(nitro.get_child_count())])
			failures += 1
		if health == null or health.get_child_count() != int(track.HEALTH_PACK_COUNT):
			print("%s: health pickup count wrong (%s)" % [id, "none" if health == null else str(health.get_child_count())])
			failures += 1
		# no pack may share a nitro bottle slot (sampled flat position)
		if nitro != null and health != null:
			for h in health.get_children():
				for b in nitro.get_children():
					if h.global_position.distance_to(b.global_position) < 0.01:
						print("%s: health pack overlaps a nitro bottle" % id)
						failures += 1
						break
		track.queue_free()
	return failures


func _discover_tracks() -> PackedStringArray:
	var ids: PackedStringArray = []
	var da := DirAccess.open(TRACKS_DIR)
	if da == null:
		return ids
	for f in da.get_files():
		if f.get_extension() == "tres":
			ids.append(f.get_basename())
	ids.sort()
	return ids


func _new_game() -> Node:
	var gs: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs)
	return gs


func _read(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _restore(path: String, data: PackedByteArray) -> void:
	if data.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)
