extends Resource
class_name CharacterStats
## Per-character movement values and the one special move each has.
##
## The defaults are the Sonic Retro Physics Guide numbers, so a character that
## overrides nothing moves exactly like the guide describes. Characters that do
## override something (a weaker jump, a shorter hitbox, a higher cap) change only
## that field, which keeps the reference values in one place.

enum Ability {
	NONE,      ## no mid-air move
	FLY,       ## hold jump to climb, for a limited time
	GLIDE,     ## steer a slow descent, grab and climb walls on contact
	AIR_DASH,  ## snap toward a nearby badnik, or dash straight ahead
	HAMMER,    ## short-range swing that also nudges the player upward
}

@export var display_name := "MASCOT"
@export var slug := "mascot"
@export var ability: Ability = Ability.NONE
@export var blurb := "all-rounder"

## Ground movement
@export var acceleration := 0.046875
@export var deceleration := 0.5
@export var friction := 0.046875
@export var top_speed := 6.0

## Air movement
@export var air_acceleration := 0.09375
@export var gravity := 0.21875
@export var jump_force := 6.5

## Rolling
@export var roll_friction := 0.0234375
@export var roll_deceleration := 0.125
@export var roll_top_speed := 16.0
@export var can_spindash := true

## Hitbox radii
@export var width_radius := 9.0
@export var height_radius := 19.0
@export var roll_width_radius := 7.0
@export var roll_height_radius := 14.0
@export var push_radius := 10.0

## Ability tuning
@export var fly_frames := 480          ## how long flight can be sustained
@export var fly_lift := 0.125          ## upward acceleration while flying
@export var fly_max_rise := 1.0        ## fastest climb rate
@export var glide_speed := 4.0         ## horizontal speed entering a glide
@export var glide_fall := 0.5          ## terminal descent while gliding
@export var climb_speed := 1.0
@export var dash_speed := 8.0
@export var dash_frames := 16
@export var homing_range := 128.0
@export var hammer_frames := 20
@export var hammer_lift := 4.0


func sprite_sheet() -> String:
	return "res://assets/sprites/player_%s.png" % slug
