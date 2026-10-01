class_name Bosses
extends RefCounted
## Campaign bosses: named rivals that replace one opponent on selected tracks.
## They ride a dedicated (purchasable) bike and pay a one-time credit bonus the
## first time the player wins their race. Data-only: add an entry to DATA.

## track_id -> {name, bike, bonus, skill, aggression}
const DATA := {
	"canyon_01": {
		"name": "ATLAS", "bike": "boss_atlas", "bonus": 500,
		"skill": 1.0, "aggression": 0.9,
	},
	"sakura_01": {
		"name": "KITSUNE", "bike": "boss_kitsune", "bonus": 700,
		"skill": 1.0, "aggression": 0.92,
	},
	"volcano_01": {
		"name": "CINDER", "bike": "boss_cinder", "bonus": 900,
		"skill": 1.0, "aggression": 0.95,
	},
}


## Boss riding on the given track, or an empty dictionary when there is none.
static func for_track(track_id: String) -> Dictionary:
	return DATA.get(track_id, {})


static func has_boss(track_id: String) -> bool:
	return DATA.has(track_id)
