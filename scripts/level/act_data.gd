extends Resource
class_name ActData
## One act, as data.
##
## `layout` is walked left to right by Zone to generate terrain; `objects` are
## placed against the resulting ground. Keeping acts as plain data means the test
## suite can build small fixture levels with the same builder the game uses.
##
## layout entries:
##   {"kind": "flat",   "length": px}
##   {"kind": "slope",  "length": px, "drop": px}          negative drop rises
##   {"kind": "hill",   "length": px, "height": px}        smooth bump
##   {"kind": "valley", "length": px, "depth": px}         smooth dip
##   {"kind": "ramp",   "length": px, "height": px}        launch lip
##   {"kind": "gap",    "length": px}                      bottomless pit
##   {"kind": "loop",   "radius": px}                      full 360 loop
##
## object entries: see Zone._place_objects for the supported "what" values.

@export var zone_name := "GREEN CANYON"
@export var act_number := 1
@export var ground_y := 320.0
@export var start_x := 120.0
@export var music := "music_zone"
@export var time_bonus_cutoff := 90.0
@export var layout: Array[Dictionary] = []
@export var objects: Array[Dictionary] = []


static func make(name: String, number: int, layout_data: Array[Dictionary],
		object_data: Array[Dictionary]) -> ActData:
	var act := ActData.new()
	act.zone_name = name
	act.act_number = number
	act.layout = layout_data
	act.objects = object_data
	return act


func title() -> String:
	return "%s  ACT %d" % [zone_name, act_number]
