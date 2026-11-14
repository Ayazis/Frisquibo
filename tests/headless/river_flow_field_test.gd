extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/river_flow_field_test.gd
const SPEED: float = 2.0
const HALF_WIDTH: float = 5.0
const ROCK: Vector3 = Vector3(0.0, 0.0, 1.0)
const TOLERANCE: float = 0.05
var _failures: int = 0

func _initialize() -> void:
	var straight: Callable = func(_x: float) -> float: return 0.0
	var plain: RiverFlowField = RiverFlowField.new(Rect2(-10, -6, 20, 12), 2.0, straight, HALF_WIDTH, SPEED, [])
	_near(plain.channel_velocity(Vector2(3, 0)).x, SPEED, "Full speed mid-channel")
	_near(plain.channel_velocity(Vector2(3, HALF_WIDTH)).length(), 0.0, "Still water at the bank")
	_near(plain.sample(Vector2(0.3, 0.2)).r, plain.sample_exact(Vector2(0.3, 0.2)).r, "Baked grid matches exact field")
	_near(plain.sample(Vector2(50, 0)).r, 0.0, "Outside the grid: still water")

	var rocks: Array[Vector3] = [ROCK]
	var field: RiverFlowField = RiverFlowField.new(Rect2(-10, -6, 20, 12), 2.0, straight, HALF_WIDTH, SPEED, rocks)
	var inside: Color = field.sample_exact(Vector2(0.2, 0.1))
	_near(Vector2(inside.r, inside.g).length(), 0.0, "No current inside the rock")
	var front: Color = field.sample_exact(Vector2(-1.02, 0.0))
	_check(Vector2(front.r, front.g).length() < SPEED * 0.1, "Stagnation point in front of the rock")
	_check(front.a > 0.0, "Bow wave piles up in front of the rock")
	var side: Color = field.sample_exact(Vector2(0.0, 1.02))
	_check(side.r > SPEED * 1.5, "Current speeds up past the side of the rock")
	var wake: Color = field.sample_exact(Vector2(2.5, 0.0))
	var open: Color = field.sample_exact(Vector2(2.5, 3.0))
	_check(wake.r < open.r, "Wake behind the rock is slower than the open channel")
	_check(wake.b > open.b, "Wake behind the rock is more turbulent")
	var upstream_far: Color = field.sample_exact(Vector2(-8.0, 0.0))
	_check(absf(upstream_far.r - SPEED) < SPEED * 0.05, "Far upstream the rock barely matters")
	print("River flow field: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)

func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) <= TOLERANCE, "%s (got %.3f, expected %.3f)" % [label, actual, expected])

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", label)
