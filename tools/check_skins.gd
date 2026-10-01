extends SceneTree
## Dev tool: validates the rider-skin system — catalog resources load, unlock
## gating and shop economy work, selection persists, decal art exists, and the
## Rider builds with a skin applied (colors + decal overlays).
## The real progress.cfg is snapshotted and restored afterwards.
## Run: godot --headless --path . -s tools/check_skins.gd

const SAVE := "user://progress.cfg"

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	var backup := _read(SAVE)
	var failures := 0
	var gs: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs)

	gs.races_done = 0
	gs.best_pos = 0
	gs.credits = 0
	gs.selected_skin = "stock"
	gs.owned_skins = []
	gs.owned_bikes = []
	gs.bosses_beaten = {}

	failures += _check_catalog(gs)
	failures += _check_shop(gs)
	failures += _check_progression(gs)
	failures += _check_persistence(gs)
	failures += _check_rider(gs)

	_restore(SAVE, backup)
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _check_catalog(gs: Node) -> int:
	var failures := 0
	for id in gs.SKIN_IDS:
		var path := "res://assets/data/skins/%s.tres" % id
		if not ResourceLoader.exists(path):
			print("catalog: missing %s" % path)
			failures += 1
			continue
		var def = load(path)
		if def == null or def.id != id:
			print("catalog: bad def for %s (id=%s)" % [id, def.id if def != null else "<null>"])
			failures += 1
		if def != null and def.decal_dir != "" and not def.has_decals():
			print("catalog: decal listed but missing for %s" % id)
			failures += 1
	if not gs.is_skin_unlocked("stock"):
		print("catalog: stock must be free")
		failures += 1
	return failures


func _check_shop(gs: Node) -> int:
	var failures := 0
	var id := "flame"
	if gs.is_skin_unlocked(id):
		print("shop: %s should start locked" % id)
		failures += 1
	if gs.skin_price(id) != gs.SHOP_SKINS[id]:
		print("shop: bad price for %s" % id)
		failures += 1
	if gs.buy_skin(id):
		print("shop: bought without credits")
		failures += 1
	gs.credits = gs.skin_price(id) - 1
	if gs.can_afford_skin(id):
		print("shop: affordable one credit short")
		failures += 1
	gs.credits = gs.skin_price(id) + 500
	if not gs.buy_skin(id):
		print("shop: buy failed with funds")
		failures += 1
	if not gs.is_skin_unlocked(id):
		print("shop: bought skin still locked")
		failures += 1
	if gs.selected_skin != id:
		print("shop: buy did not select skin")
		failures += 1
	if gs.credits != 500:
		print("shop: credits not deducted (%d)" % gs.credits)
		failures += 1
	return failures


func _check_progression(gs: Node) -> int:
	var failures := 0
	var rose := "rose"
	if gs.is_skin_unlocked(rose):
		print("progress: %s should be boss-gated" % rose)
		failures += 1
	gs.bosses_beaten["sakura_01"] = true
	if not gs.is_skin_unlocked(rose):
		print("progress: %s not unlocked after boss" % rose)
		failures += 1
	if not gs.select_skin(rose):
		print("progress: select_skin failed for unlocked rose")
		failures += 1
	if gs.select_skin("gold"):
		print("progress: selected a still-locked skin")
		failures += 1
	return failures


func _check_persistence(gs: Node) -> int:
	var failures := 0
	gs.selected_skin = "rose"
	gs.owned_skins = ["flame"]
	gs._save_progress()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs2)
	if gs2.selected_skin != "rose":
		print("persist: selected_skin=%s (want rose)" % gs2.selected_skin)
		failures += 1
	if not ("flame" in gs2.owned_skins):
		print("persist: owned_skins lost flame")
		failures += 1
	gs2.queue_free()
	return failures


func _check_rider(gs: Node) -> int:
	var failures := 0
	var bike_def = load("res://assets/data/bikes/sport_01.tres")
	var skin = load("res://assets/data/skins/flame.tres")
	var rider = load("res://scripts/rider.gd").new()
	root.add_child(rider)
	rider.setup(bike_def.rider_color, bike_def.helmet_color, bike_def, skin)
	if rider.suit_color != skin.suit_color:
		print("rider: suit color not applied (%s)" % rider.suit_color)
		failures += 1
	if rider.accent_color != skin.accent_color:
		print("rider: accent color not applied (%s)" % rider.accent_color)
		failures += 1
	if rider._decal_suit == null:
		print("rider: suit decal texture not loaded")
		failures += 1
	var decal_quads := 0
	for child in rider.get_node("Skeleton").get_children():
		if child is BoneAttachment3D:
			for mi in child.get_children():
				if mi is MeshInstance3D and mi.mesh is PlaneMesh:
					decal_quads += 1
	if decal_quads == 0:
		print("rider: no decal overlay quads built")
		failures += 1
	rider.queue_free()
	return failures


func _read(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return data


func _restore(path: String, data: PackedByteArray) -> void:
	if data.is_empty():
		DirAccess.remove_absolute(path)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(data)
	f.close()
