class_name BikeTuning
extends RefCounted
## Balance tables for the per-bike upgrade shop: three parts (engine / tires /
## nitro), up to MAX_LEVEL levels each, priced in credits. Stat changes are
## multiplicative per level and never mutate the base BikeDef resource — apply()
## returns a tuned duplicate so shared/AI defs stay untouched.

const PARTS := ["engine", "tires", "nitro"]
const PART_LABELS := {"engine": "ENGINE", "tires": "TIRES", "nitro": "NITRO"}
const MAX_LEVEL := 3

## Cumulative multiplier per level, raised to the level power in apply().
const PART_MULTS := {
	"engine": {"max_speed": 1.04, "accel": 1.08},
	"tires": {"grip": 1.08, "steer_rate": 1.05, "offroad_grip": 1.06},
	"nitro": {"nitro_max": 1.08, "nitro_regen": 1.08, "nitro_speed_mult": 1.02},
}

## Cost of reaching level 1, 2, 3 (index = target level - 1).
const COSTS := [400, 900, 1600]

## Pricier machines cost more to upgrade.
const BIKE_COST_MULT := {
	"scrambler_01": 1.0,
	"sport_01": 1.2,
	"cruiser_01": 1.5,
	"super_01": 2.0,
	"dirt_01": 1.1,
	"chopper_01": 1.6,
	"electric_01": 1.3,
}

## Credits awarded for finishing a race, by position.
const REWARDS := {1: 300, 2: 200, 3: 140, 4: 90}
const REWARD_DEFAULT := 60

## How much faster opponents get per total upgrade level the player owns.
const AI_SCALE_PER_LEVEL := 0.012

## Campaign ladder / per-track difficulty tiers.
const TRACK_TIERS := 3
const LADDER_AI := 0.015      # opponent pace per track position in the ladder
const TIER_AI := 0.025        # opponent pace per difficulty tier
const LADDER_REWARD := 0.08   # reward bonus per track position in the ladder
const TIER_REWARD := 0.5      # reward bonus per difficulty tier


static func empty_levels() -> Dictionary:
	var levels := {}
	for part in PARTS:
		levels[part] = 0
	return levels


static func sanitize(levels: Dictionary) -> Dictionary:
	var out := empty_levels()
	for part in PARTS:
		out[part] = clampi(int(levels.get(part, 0)), 0, MAX_LEVEL)
	return out


static func total_levels(levels: Dictionary) -> int:
	var total := 0
	for part in PARTS:
		total += clampi(int(levels.get(part, 0)), 0, MAX_LEVEL)
	return total


## Cost of buying the next level for a part, or -1 when maxed.
static func cost(bike_id: String, current_level: int) -> int:
	var level := clampi(current_level, 0, MAX_LEVEL)
	if level >= MAX_LEVEL:
		return -1
	var mult: float = BIKE_COST_MULT.get(bike_id, 1.0)
	var raw := float(COSTS[level]) * mult
	return int(round(raw / 10.0)) * 10


static func reward_for(pos: int) -> int:
	return int(REWARDS.get(pos, REWARD_DEFAULT))


static func ai_speed_scale(total: int) -> float:
	return 1.0 + AI_SCALE_PER_LEVEL * float(total)


## Opponent pace from campaign position and difficulty tier (multiplies on top
## of the upgrade rubber-band).
static func track_ai_scale(track_index: int, tier: int) -> float:
	return 1.0 + LADDER_AI * float(maxi(track_index, 0)) + TIER_AI * float(clampi(tier, 0, TRACK_TIERS - 1))


## Credits for finishing a race, scaled up by campaign position and tier.
static func track_reward(pos: int, track_index: int, tier: int) -> int:
	var raw := float(reward_for(pos))
	raw *= 1.0 + LADDER_REWARD * float(maxi(track_index, 0))
	raw *= 1.0 + TIER_REWARD * float(clampi(tier, 0, TRACK_TIERS - 1))
	return int(round(raw / 10.0)) * 10


## Returns a tuned copy of def with all upgrade multipliers applied. The input
## resource is left unchanged.
static func apply(def: BikeDef, levels: Dictionary) -> BikeDef:
	var tuned := def.duplicate() as BikeDef
	if tuned == null:
		return def
	var clean := sanitize(levels)
	for part in PARTS:
		var level: int = clean[part]
		if level <= 0:
			continue
		for prop in PART_MULTS[part]:
			tuned.set(prop, float(def.get(prop)) * pow(float(PART_MULTS[part][prop]), level))
	return tuned
