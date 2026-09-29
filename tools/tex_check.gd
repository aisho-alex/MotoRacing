extends SceneTree
func _init():
	var p := "res://assets/environments/city/facade_a.webp"
	print("exists=", ResourceLoader.exists(p))
	var t = load(p)
	print("loaded=", t != null, " size=", t.get_size() if t != null else Vector2.ZERO)
	quit()
