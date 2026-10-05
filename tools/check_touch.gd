extends SceneTree
## Dev tool: checks the mobile virtual gamepad layout and input plumbing.
## Verifies finger-sized layout (no overlaps, inside the viewport), multi-touch
## (throttle + nitro held together), analog steering strength and combat taps.
## Run: godot --headless --path . -s tools/check_touch.gd

const EPS := 0.02
const STEER_TRAVEL := 0.42

var _deferred := true
var _failures := 0


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if _deferred:
		_deferred = false
		_run()
		print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
		quit(0 if _failures == 0 else 1)
	return true


func _run() -> void:
	var tc := TouchControls.new()
	root.add_child(tc)
	tc.visible = true

	_layout_at(tc, Vector2i(1280, 720))
	_layout_checks(tc)
	_layout_at(tc, Vector2i(2340, 1080))
	_layout_checks(tc)
	_layout_at(tc, Vector2i(1280, 720))
	_multitouch_check(tc)
	_steer_checks(tc)
	_combat_checks(tc)
	_release_check(tc)

	tc.queue_free()


## Headless windows default to a tiny size; pin a phone-like viewport so the
## relative layout is exercised for real.
func _layout_at(tc: TouchControls, size: Vector2i) -> void:
	root.size = size
	tc._layout()


func _layout_checks(tc: TouchControls) -> void:
	var vs := root.get_visible_rect().size
	var rects: Array[Rect2] = []
	for b in tc._buttons:
		rects.append(b.rect as Rect2)
	var min_size := INF
	var max_size := 0.0
	for r in rects:
		min_size = minf(min_size, r.size.x)
		max_size = maxf(max_size, r.size.x)
		if r.position.x < -0.5 or r.position.y < -0.5 \
				or r.end.x > vs.x + 0.5 or r.end.y > vs.y + 0.5:
			_fail("button %s outside viewport: %s" % [r, vs])
	_report("button size %.0f..%.0f px on %.0fx%.0f (>=0.12h)"
			% [min_size, max_size, vs.x, vs.y], min_size >= vs.y * 0.12)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j], true):
				_fail("buttons %d and %d overlap: %s / %s"
						% [i, j, rects[i], rects[j]])
	var zone: Rect2 = tc._steer_zone_rect
	for i in rects.size():
		if zone.intersects(rects[i], true):
			_fail("steering zone overlaps button %d: %s / %s" % [i, zone, rects[i]])
	_report("layout separated (zone %.0fx%.0f)"
			% [zone.size.x, zone.size.y], true)
	_nitro_reach_check(tc)


## Nitro must sit directly above the throttle pedal: same X centre, a small
## vertical gap — reachable by the right thumb without lifting off the gas.
func _nitro_reach_check(tc: TouchControls) -> void:
	var gas := _find(tc, "accelerate")
	var nitro := _find(tc, "nitro")
	var dx := absf(gas.get_center().x - nitro.get_center().x)
	var gap := gas.position.y - nitro.end.y
	_report("nitro centered over throttle (dx %.0f, gap %.0f)" % [dx, gap],
			dx <= 2.0 and gap >= -0.5 and gap <= gas.size.y * 0.5)


func _find(tc: TouchControls, action: String) -> Rect2:
	for b in tc._buttons:
		if b.action == action:
			return b.rect
	return Rect2()


func _multitouch_check(tc: TouchControls) -> void:
	Input.action_release("accelerate")
	Input.action_release("nitro")
	# Two fingers on the right: thumb on the throttle, index on nitro above it.
	_touch(tc, 0, _find(tc, "accelerate").get_center(), true)
	_touch(tc, 1, _find(tc, "nitro").get_center(), true)
	var both := Input.is_action_pressed("accelerate") and Input.is_action_pressed("nitro")
	_report("throttle + nitro held simultaneously", both)
	# Releasing one must not drop the other.
	_touch(tc, 1, _find(tc, "nitro").get_center(), false)
	_report("nitro release keeps throttle",
			Input.is_action_pressed("accelerate") and not Input.is_action_pressed("nitro"))
	_touch(tc, 0, _find(tc, "accelerate").get_center(), false)
	_touch(tc, 2, _find(tc, "brake").get_center(), true)
	_report("brake is a separate hold",
			Input.is_action_pressed("brake") and not Input.is_action_pressed("accelerate"))
	_touch(tc, 2, _find(tc, "brake").get_center(), false)


func _steer_checks(tc: TouchControls) -> void:
	var zone: Rect2 = tc._steer_zone_rect
	var cy := zone.position.y + zone.size.y * 0.5
	var center := zone.position.x + zone.size.x * 0.5
	var travel := zone.size.x * STEER_TRAVEL
	_touch(tc, 0, Vector2(center, cy), true)
	_report("steer centre neutral",
			absf(Input.get_axis("steer_left", "steer_right")) < EPS)
	_drag(tc, 0, Vector2(center + travel * 0.5, cy))
	_report("steer half-right = +0.5",
			absf(Input.get_axis("steer_left", "steer_right") - 0.5) < EPS)
	_drag(tc, 0, Vector2(center + travel * 2.0, cy))
	_report("steer clamps to +1.0",
			absf(Input.get_axis("steer_left", "steer_right") - 1.0) < EPS)
	_drag(tc, 0, Vector2(center - travel * 2.0, cy))
	_report("steer clamps to -1.0",
			absf(Input.get_axis("steer_left", "steer_right") + 1.0) < EPS)
	_drag(tc, 0, Vector2(center + travel * 0.02, cy))
	_report("steer deadzone",
			absf(Input.get_axis("steer_left", "steer_right")) < EPS)
	_touch(tc, 0, Vector2(center, cy), false)
	_report("steer release neutral",
			absf(Input.get_axis("steer_left", "steer_right")) < EPS)


func _combat_checks(tc: TouchControls) -> void:
	for pair in [["attack_left", 0], ["attack_right", 1], ["kick", 2]]:
		var action: String = pair[0]
		_touch(tc, pair[1], _find(tc, action).get_center(), true)
		_report("%s tap" % action, Input.is_action_pressed(action))
		_touch(tc, pair[1], _find(tc, action).get_center(), false)


func _release_check(tc: TouchControls) -> void:
	for action in ["accelerate", "brake", "nitro", "attack_left", "attack_right", "kick",
			"steer_left", "steer_right"]:
		if Input.is_action_pressed(action):
			_fail("%s stuck after release" % action)
	_report("no stuck actions", true)


func _touch(tc: TouchControls, index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	tc._input(ev)


func _drag(tc: TouchControls, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	tc._input(ev)


func _report(label: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _fail(msg: String) -> void:
	print("FAIL %s" % msg)
	_failures += 1
