class_name TrafficDef
extends BikeDef
## Per-type tuning for civilian traffic. Cars and motorcycles share the
## RaceBike lane driver; these fields change how each type behaves on the road:
## how fast it rolls, how much it weaves in its lane and how snug a pass has to
## be before it counts as a near miss.

@export var speed_mult := 0.35   # fraction of the lane driver's base pace
@export var weave_amp := 0.0     # lateral wander amplitude (m), 0 = dead straight
@export var weave_rate := 0.0    # wander angular rate (rad/s)
@export var nm_width := 2.8      # widest gap that still counts as a near miss (m)
