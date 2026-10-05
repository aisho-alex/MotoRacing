class_name GraphicsQuality
extends RefCounted
## Runtime picture-quality presets. The heavy levers (3D render scale, MSAA,
## shadow resolution/reach and the Forward+ night post stack) are dialed per
## preset; the menu offers AUTO/LOW/MEDIUM/HIGH and AUTO resolves to LOW on
## mobile exports, HIGH on desktop. Materials/tonemapping stay untouched so the
## cel look holds across tiers.

const LEVELS := ["low", "medium", "high"]

## Keys: scale_3d (render resolution), msaa (Viewport.MSAA_*), deband
## (Viewport.use_debanding), shadow_mode (DirectionalLight3D.SHADOW_*),
## shadow_distance, shadow_blur, shadow_atlas (Viewport positional atlas),
## heavy (Forward+ SSAO/SSR/SDFGI/volumetric fog).
const PRESETS := {
	"low": {
		"scale_3d": 0.7,
		"msaa": Viewport.MSAA_DISABLED,
		"deband": false,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"shadow_distance": 70.0,
		"shadow_blur": 1.0,
		"shadow_atlas": 1024,
		"heavy": false,
	},
	"medium": {
		"scale_3d": 0.85,
		"msaa": Viewport.MSAA_2X,
		"deband": true,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"shadow_distance": 100.0,
		"shadow_blur": 0.8,
		"shadow_atlas": 2048,
		"heavy": false,
	},
	"high": {
		"scale_3d": 1.0,
		"msaa": Viewport.MSAA_4X,
		"deband": false,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"shadow_distance": 140.0,
		"shadow_blur": 0.6,
		"shadow_atlas": 4096,
		"heavy": true,
	},
}


static func has_level(level: String) -> bool:
	return level in LEVELS


## Applies resolution/AA/shadow-atlas settings to a viewport. Safe to call on
## the root window (applies to every 3D scene, menu included).
static func apply_viewport(vp: Viewport, level: String) -> void:
	if vp == null:
		return
	var p: Dictionary = PRESETS.get(level, PRESETS["high"])
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(p["scale_3d"])
	vp.msaa_3d = int(p["msaa"])
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.use_debanding = bool(p["deband"])
	vp.positional_shadow_atlas_size = int(p["shadow_atlas"])


## Applies shadow and post-processing settings to the race environment/light.
## "high" keeps whatever main.gd authored (the full night stack), lower tiers
## drop the expensive Forward+ effects.
static func apply_env(env: Environment, sun: DirectionalLight3D, level: String,
		_night: bool) -> void:
	var p: Dictionary = PRESETS.get(level, PRESETS["high"])
	if sun != null:
		sun.directional_shadow_mode = int(p["shadow_mode"])
		sun.directional_shadow_max_distance = float(p["shadow_distance"])
		sun.shadow_blur = float(p["shadow_blur"])
	if env == null or bool(p["heavy"]):
		return
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
