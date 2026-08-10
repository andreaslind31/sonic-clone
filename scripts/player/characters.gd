extends RefCounted
class_name Characters
## The playable roster.
##
## These are original characters. The movesets are the classic archetypes — a
## balanced runner, a flier, a glider-climber, a striker — because that is what
## makes the level design interesting; the characters themselves are ours.
##
## Only the fields that differ from CharacterStats' SPG defaults are set here.

static func count() -> int:
	return 5


static func get_character(index: int) -> CharacterStats:
	match posmod(index, count()):
		1:
			return flier()
		2:
			return glider()
		3:
			return striker()
		4:
			return smasher()
		_:
			return runner()


static func names() -> PackedStringArray:
	var result := PackedStringArray()
	for i in count():
		result.append(get_character(i).display_name)
	return result


## The reference character: pure SPG values, no mid-air move.
static func runner() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.display_name = "DASH"
	stats.slug = "dash"
	stats.blurb = "fastest on the ground"
	stats.ability = CharacterStats.Ability.NONE
	return stats


## Lighter and slower, but can climb under its own power.
static func flier() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.display_name = "PIP"
	stats.slug = "pip"
	stats.blurb = "jump again to fly"
	stats.ability = CharacterStats.Ability.FLY
	stats.top_speed = 5.5
	stats.acceleration = 0.0439453125
	stats.jump_force = 6.5
	stats.height_radius = 17.0
	stats.roll_height_radius = 13.0
	return stats


## Heavier: a weaker jump, but glides and climbs walls.
static func glider() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.display_name = "BRAWN"
	stats.slug = "brawn"
	stats.blurb = "glides and climbs walls"
	stats.ability = CharacterStats.Ability.GLIDE
	stats.jump_force = 6.0        ## the classic heavier-character jump
	stats.top_speed = 6.0
	stats.can_spindash = true
	return stats


## Trades a little top speed for an attacking air dash.
static func striker() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.display_name = "VOLT"
	stats.slug = "volt"
	stats.blurb = "jump again to air dash"
	stats.ability = CharacterStats.Ability.AIR_DASH
	stats.top_speed = 6.5
	stats.acceleration = 0.05
	stats.jump_force = 6.25
	return stats


## No spindash, but a hammer swing that clears badniks from standing height.
static func smasher() -> CharacterStats:
	var stats := CharacterStats.new()
	stats.display_name = "ROSA"
	stats.slug = "rosa"
	stats.blurb = "jump again to swing"
	stats.ability = CharacterStats.Ability.HAMMER
	stats.top_speed = 5.75
	stats.jump_force = 6.5
	stats.can_spindash = false
	return stats
