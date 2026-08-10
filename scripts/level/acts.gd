extends RefCounted
class_name Acts
## The act registry: every playable level, in play order.
##
## Positions in `objects` are chosen against the segment run in `layout` above
## them; nothing should sit over a gap except ring trails and the platforms meant
## to carry the player across.

static func count() -> int:
	return 3


static func get_act(index: int) -> ActData:
	match posmod(index, count()):
		1:
			return canyon_act_2()
		2:
			return canyon_act_3()
		_:
			return canyon_act_1()


# --------------------------------------------------------------------------- #
static func canyon_act_1() -> ActData:
	var layout: Array[Dictionary] = [
		{"kind": "flat", "length": 420.0},
		{"kind": "hill", "length": 320.0, "height": 64.0},
		{"kind": "flat", "length": 120.0},
		{"kind": "slope", "length": 256.0, "drop": 96.0},
		{"kind": "valley", "length": 320.0, "depth": 72.0},
		{"kind": "flat", "length": 150.0},
		{"kind": "loop", "radius": 64.0},
		{"kind": "flat", "length": 240.0},
		{"kind": "hill", "length": 280.0, "height": 56.0},
		{"kind": "flat", "length": 90.0},
		{"kind": "gap", "length": 150.0},
		{"kind": "flat", "length": 190.0},
		{"kind": "slope", "length": 240.0, "drop": -120.0},
		{"kind": "flat", "length": 200.0},
		{"kind": "slope", "length": 200.0, "drop": 120.0},
		{"kind": "valley", "length": 280.0, "depth": 64.0},
		{"kind": "loop", "radius": 76.0},
		{"kind": "flat", "length": 260.0},
		{"kind": "hill", "length": 360.0, "height": 88.0},
		{"kind": "flat", "length": 140.0},
		{"kind": "gap", "length": 170.0},
		{"kind": "flat", "length": 300.0},
		{"kind": "ramp", "length": 160.0, "height": 96.0},
		{"kind": "flat", "length": 120.0},
		{"kind": "slope", "length": 180.0, "drop": 96.0},
		{"kind": "flat", "length": 700.0},
	]
	var objects: Array[Dictionary] = [
		{"what": "ring_arc", "x": 300.0, "count": 5, "spacing": 24.0, "y": 34.0, "arc": 26.0},
		{"what": "monitor", "x": 600.0, "y": 0.0, "item": "rings"},
		{"what": "ring_line", "x": 720.0, "count": 4, "spacing": 24.0, "y": 30.0},
		{"what": "badnik", "x": 990.0, "kind": "motobug", "patrol": 80.0, "y": 12.0},
		{"what": "ring_arc", "x": 1180.0, "count": 6, "spacing": 22.0, "y": 60.0, "arc": 34.0},
		{"what": "ring_line", "x": 1480.0, "count": 4, "spacing": 24.0, "y": 40.0},
		{"what": "badnik", "x": 1860.0, "kind": "buzzer", "patrol": 70.0, "y": 96.0},
		{"what": "spring", "x": 2010.0, "y": 8.0, "dir": "up"},
		{"what": "monitor", "x": 2100.0, "y": 0.0, "item": "shoes"},
		{"what": "ring_arc", "x": 2200.0, "count": 5, "spacing": 22.0, "y": 44.0, "arc": 28.0},
		# the first pit: a ring trail baits the jump, the platform is the safe route
		{"what": "ring_line", "x": 2420.0, "count": 5, "spacing": 24.0, "y": 60.0},
		{"what": "platform", "x": 2479.0, "y": 46.0, "travel": Vector2(0, -56), "seconds": 2.4},
		{"what": "checkpoint", "x": 2600.0, "y": 0.0},
		{"what": "ring_line", "x": 2640.0, "count": 3, "spacing": 22.0, "y": 30.0},
		{"what": "spikes", "x": 2700.0, "y": 7.0},
		{"what": "badnik", "x": 2880.0, "kind": "motobug", "patrol": 90.0, "y": 12.0},
		{"what": "monitor", "x": 3050.0, "y": 0.0, "item": "shield"},
		{"what": "ring_arc", "x": 3250.0, "count": 7, "spacing": 22.0, "y": 54.0, "arc": 30.0},
		{"what": "badnik", "x": 4000.0, "kind": "buzzer", "patrol": 90.0, "y": 100.0},
		{"what": "ring_line", "x": 4100.0, "count": 6, "spacing": 22.0, "y": 36.0},
		{"what": "monitor", "x": 4300.0, "y": 0.0, "item": "life"},
		{"what": "spring", "x": 4450.0, "y": 8.0, "dir": "right"},
		{"what": "ring_arc", "x": 4570.0, "count": 5, "spacing": 24.0, "y": 66.0, "arc": 30.0},
		# the second pit
		{"what": "ring_line", "x": 4680.0, "count": 6, "spacing": 24.0, "y": 70.0},
		{"what": "platform", "x": 4741.0, "y": 54.0, "travel": Vector2(0, -64), "seconds": 2.2},
		{"what": "badnik", "x": 4950.0, "kind": "motobug", "patrol": 70.0, "y": 12.0},
		{"what": "spikes", "x": 5060.0, "y": 7.0},
		{"what": "ring_line", "x": 5180.0, "count": 5, "spacing": 22.0, "y": 40.0},
		{"what": "ring_arc", "x": 5320.0, "count": 6, "spacing": 22.0, "y": 48.0, "arc": 30.0},
		{"what": "goal", "x": 5900.0, "y": 0.0},
	]
	return ActData.make("GREEN CANYON", 1, layout, objects)


# --------------------------------------------------------------------------- #
## Act 2 is built around the block geometry: a low road along the ground and a
## ledge route above it, so characters that can fly, glide or climb have a reason
## to leave the floor.
static func canyon_act_2() -> ActData:
	var layout: Array[Dictionary] = [
		{"kind": "flat", "length": 360.0},
		{"kind": "slope", "length": 200.0, "drop": -80.0},
		{"kind": "flat", "length": 180.0},
		{"kind": "loop", "radius": 72.0},
		{"kind": "flat", "length": 200.0},
		{"kind": "gap", "length": 130.0},
		{"kind": "flat", "length": 340.0},
		{"kind": "hill", "length": 300.0, "height": 72.0},
		{"kind": "flat", "length": 260.0},
		{"kind": "valley", "length": 260.0, "depth": 80.0},
		{"kind": "flat", "length": 220.0},
		{"kind": "slope", "length": 220.0, "drop": -140.0},
		{"kind": "flat", "length": 300.0},
		{"kind": "gap", "length": 160.0},
		{"kind": "flat", "length": 280.0},
		{"kind": "ramp", "length": 150.0, "height": 110.0},
		{"kind": "flat", "length": 160.0},
		{"kind": "slope", "length": 200.0, "drop": 130.0},
		{"kind": "loop", "radius": 88.0},
		{"kind": "flat", "length": 620.0},
	]
	var objects: Array[Dictionary] = [
		{"what": "ring_line", "x": 240.0, "count": 4, "spacing": 24.0, "y": 32.0},
		# stacked ledges: the upper shelf carries the reward, the ground road is safe
		{"what": "block", "x": 640.0, "y": 80.0, "width": 112.0, "height": 20.0},
		{"what": "ring_line", "x": 600.0, "count": 3, "spacing": 22.0, "y": 112.0},
		{"what": "monitor", "x": 640.0, "y": 80.0, "item": "rings"},
		{"what": "badnik", "x": 640.0, "kind": "motobug", "patrol": 70.0, "y": 12.0},
		{"what": "ring_arc", "x": 1080.0, "count": 6, "spacing": 22.0, "y": 40.0, "arc": 28.0},
		{"what": "ring_line", "x": 1180.0, "count": 4, "spacing": 24.0, "y": 66.0},
		{"what": "platform", "x": 1205.0, "y": 40.0, "travel": Vector2(0, -60), "seconds": 2.2},
		{"what": "checkpoint", "x": 1360.0, "y": 0.0},
		# a roofed corridor: only reachable from above, and it needs a ceiling
		{"what": "block", "x": 1560.0, "y": 96.0, "width": 200.0, "height": 24.0},
		{"what": "ring_line", "x": 1500.0, "count": 5, "spacing": 22.0, "y": 130.0},
		{"what": "monitor", "x": 1560.0, "y": 96.0, "item": "shield"},
		{"what": "badnik", "x": 1620.0, "kind": "motobug", "patrol": 60.0, "y": 12.0},
		{"what": "spring", "x": 1840.0, "y": 8.0, "dir": "up"},
		{"what": "badnik", "x": 2080.0, "kind": "buzzer", "patrol": 90.0, "y": 110.0},
		{"what": "ring_arc", "x": 2260.0, "count": 7, "spacing": 22.0, "y": 48.0, "arc": 32.0},
		{"what": "spikes", "x": 2500.0, "y": 7.0},
		{"what": "monitor", "x": 2620.0, "y": 0.0, "item": "shoes"},
		{"what": "wall", "x": 2900.0, "y": 0.0, "height": 64.0},
		{"what": "ring_line", "x": 2960.0, "count": 3, "spacing": 22.0, "y": 178.0},
		{"what": "block", "x": 3040.0, "y": 150.0, "width": 120.0, "height": 90.0},
		{"what": "monitor", "x": 3040.0, "y": 150.0, "item": "life"},
		{"what": "ring_line", "x": 3210.0, "count": 5, "spacing": 24.0, "y": 74.0},
		{"what": "platform", "x": 3274.0, "y": 56.0, "travel": Vector2(0, -70), "seconds": 2.0},
		{"what": "badnik", "x": 3600.0, "kind": "buzzer", "patrol": 80.0, "y": 104.0},
		{"what": "ring_arc", "x": 3760.0, "count": 6, "spacing": 22.0, "y": 52.0, "arc": 30.0},
		{"what": "spring", "x": 3980.0, "y": 8.0, "dir": "right"},
		{"what": "ring_line", "x": 4450.0, "count": 6, "spacing": 22.0, "y": 44.0},
		{"what": "badnik", "x": 4640.0, "kind": "motobug", "patrol": 80.0, "y": 12.0},
		{"what": "goal", "x": 4800.0, "y": 0.0},
	]
	return ActData.make("GREEN CANYON", 2, layout, objects)


# --------------------------------------------------------------------------- #
## Act 3 is the zone's climax: a short, fast approach into a sealed arena where
## the pod is waiting. No goal sign here — the capsule that appears once the boss
## is beaten is what ends the act.
static func canyon_act_3() -> ActData:
	var layout: Array[Dictionary] = [
		{"kind": "flat", "length": 300.0},
		{"kind": "slope", "length": 180.0, "drop": -60.0},
		{"kind": "loop", "radius": 68.0},
		{"kind": "flat", "length": 160.0},
		{"kind": "gap", "length": 120.0},
		{"kind": "flat", "length": 200.0},
		{"kind": "hill", "length": 260.0, "height": 64.0},
		{"kind": "flat", "length": 180.0},
		{"kind": "ramp", "length": 140.0, "height": 80.0},
		{"kind": "slope", "length": 200.0, "drop": 140.0},
		# the arena: deliberately flat and featureless, so the fight is the fight
		{"kind": "flat", "length": 620.0},
	]
	var objects: Array[Dictionary] = [
		{"what": "ring_line", "x": 200.0, "count": 4, "spacing": 24.0, "y": 32.0},
		{"what": "badnik", "x": 400.0, "kind": "motobug", "patrol": 60.0, "y": 12.0},
		{"what": "ring_arc", "x": 780.0, "count": 6, "spacing": 22.0, "y": 44.0, "arc": 28.0},
		{"what": "ring_line", "x": 930.0, "count": 5, "spacing": 24.0, "y": 62.0},
		{"what": "platform", "x": 990.0, "y": 48.0, "travel": Vector2(0, -54), "seconds": 2.2},
		{"what": "monitor", "x": 1180.0, "y": 0.0, "item": "rings"},
		{"what": "badnik", "x": 1320.0, "kind": "buzzer", "patrol": 80.0, "y": 96.0},
		{"what": "checkpoint", "x": 1560.0, "y": 0.0},
		{"what": "ring_line", "x": 1620.0, "count": 4, "spacing": 22.0, "y": 34.0},
		{"what": "monitor", "x": 1760.0, "y": 0.0, "item": "shield"},
		# stocking up before the pod: the fight is winnable but not forgiving
		{"what": "ring_arc", "x": 1900.0, "count": 5, "spacing": 22.0, "y": 40.0, "arc": 24.0},
		{"what": "boss", "x": 2340.0, "arena": 230.0, "height": 104.0},
	]
	var act := ActData.make("GREEN CANYON", 3, layout, objects)
	act.time_bonus_cutoff = 120.0
	return act
