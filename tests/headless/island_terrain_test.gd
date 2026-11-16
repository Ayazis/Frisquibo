extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/island_terrain_test.gd
## The demo island holds its water: the pond doesn't spill except into the river, the river stays
## between its banks and runs downhill, and a sandy beach runs all the way round into the sea.
const ANGLES := 72
var _failures: int = 0


func _initialize() -> void:
	var t := IslandTerrain.new()
	_check(t.height(IslandTerrain.POND_CENTRE.x, IslandTerrain.POND_CENTRE.y)
			< IslandTerrain.POND_LEVEL - IslandTerrain.POND_DEPTH * 0.8, "The pond is deep in the middle")
	var spills := 0
	for i in range(ANGLES):
		var a := TAU * i / ANGLES
		var rim := IslandTerrain.POND_CENTRE + Vector2(cos(a), sin(a)) * (IslandTerrain.POND_RADIUS + 3.0)
		# The outlet is the one way out: east, where the river starts.
		var outlet := absf(rim.y - t.river_centre(rim.x)) < IslandTerrain.RIVER_BANK_DISTANCE and rim.x > IslandTerrain.POND_CENTRE.x
		if not outlet and t.height(rim.x, rim.y) < IslandTerrain.POND_LEVEL:
			spills += 1
	_check(spills == 0, "The pond's banks hold its water (%d low points)" % spills)
	# The pond's water is a square (IslandScene): outside the pond, the ground must cover it.
	var half := IslandTerrain.POND_RADIUS + IslandScene.POND_MARGIN
	var showing := 0
	for iz in range(-20, 21):
		for ix in range(-20, 21):
			var p := IslandTerrain.POND_CENTRE + Vector2(ix, iz) * half / 20.0
			var outside := p.distance_to(IslandTerrain.POND_CENTRE) > IslandTerrain.POND_RADIUS + 2.0
			if outside and not _near_river(t, p) and t.height(p.x, p.y) < IslandTerrain.POND_LEVEL + 0.1:
				showing += 1
	_check(showing == 0, "The ground covers the pond's square outside the pond (%d points under water)" % showing)

	var previous := INF
	var x := IslandTerrain.RIVER_START_X + 2.0
	while x < t.river_end_x() - 15.0:
		var level := t.river_level(x)
		var centre := t.river_centre(x)
		_check(level <= previous, "The river runs downhill at x = %.0f" % x)
		previous = level
		_check(t.height(x, centre) < level - 0.5, "The river is deep enough at x = %.0f" % x)
		for side: float in [-1.0, 1.0]:
			var bank := t.height(x, centre + side * IslandTerrain.RIVER_BANK_DISTANCE)
			_check(bank > level, "The river's bank holds it at x = %.0f" % x)
		x += 5.0
	_check(t.river_level(t.river_end_x()) < IslandTerrain.SEA_LEVEL + 0.2, "The river meets the sea")

	for i in range(ANGLES):
		var a := TAU * i / ANGLES
		var coast := t.coast_radius(a)
		var dir := Vector2(cos(a), sin(a))
		var land := dir * (coast - 15.0)
		var sea := dir * (coast + 30.0)
		_check(t.height(land.x, land.y) > IslandTerrain.SEA_LEVEL, "Land inside the coast at %d degrees" % (i * 5))
		_check(t.height(sea.x, sea.y) < IslandTerrain.SEA_LEVEL, "Sea outside the coast at %d degrees" % (i * 5))
		_check(t.height(land.x, land.y) < IslandTerrain.BEACH_TOP + 1.5 or _near_river(t, land),
				"A beach, not a cliff, at %d degrees" % (i * 5))
	# An island in open sea: deep, blue water a few hundred metres out, all the way round.
	for i in range(ANGLES):
		var a := TAU * i / ANGLES
		var out := Vector2(cos(a), sin(a)) * (t.coast_radius(a) + 300.0)
		_check(t.height(out.x, out.y) < -50.0, "Deep water 300 m off the coast at %d degrees" % (i * 5))
	var deep := Vector2(IslandTerrain.COAST_RADIUS + 800.0, 0.0)
	_check(t.height(deep.x, deep.y) < -50.0, "Deep water past the drop-off")
	var radii := IslandGround.ring_radii()
	_check(radii[radii.size() - 1] >= IslandGround.OUTER_RADIUS, "The ground reaches far out to sea")
	print("Island terrain: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


## In the river's corridor, including its outlet from the pond.
func _near_river(t: IslandTerrain, p: Vector2) -> bool:
	return p.x > IslandTerrain.RIVER_START_X - IslandTerrain.RIVER_BANK_DISTANCE and absf(p.y - t.river_centre(p.x)) < IslandTerrain.RIVER_BANK_DISTANCE * 2.0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
