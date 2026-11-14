extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/ocean_rules_test.gd
const TOLERANCE: float = 0.001
var _failures: int = 0


func _initialize() -> void:
	var values: Dictionary[StringName, float] = {&"wind_speed": 15.0, &"foam_gain": 3.0, &"level": 0.0,
			&"wave_height": 3.0}
	var limits: Dictionary[StringName, Vector2] = {&"foam_gain": Vector2(0.0, 20.0)}

	var none := OceanRuleEngine.evaluate(null, values, limits)
	_check(none.values == values and none.local.count() == 0, "No rules leave the values alone")

	var windy := _rule([_if(&"wind_speed", OceanRuleCondition.Comparison.GREATER, 12.0)],
			[_then(&"foam_gain", OceanRuleEffect.Operation.ADD, 5.0)])
	var result := _run([windy], values, limits)
	_near(result.values[&"foam_gain"], 8.0, "Global rule: wind > 12 then foam_gain += 5")
	values[&"wind_speed"] = 5.0
	_near(_run([windy], values, limits).values[&"foam_gain"], 3.0, "Global rule off below threshold")

	var huge := _rule([], [_then(&"foam_gain", OceanRuleEffect.Operation.MULTIPLY, 100.0)])
	_near(_run([huge], values, limits).values[&"foam_gain"], 20.0, "Results clamp to the parameter range")

	var soft := _if(&"wind_speed", OceanRuleCondition.Comparison.GREATER, 5.0)
	soft.softness = 2.0
	_near(soft.weight(5.0), 0.5, "Soft condition is half-on at its threshold")
	_near(soft.weight(7.0), 1.0, "Soft condition fully on past the fade")

	# Chaining: the second rule sees the wind the first one set.
	var gale := _rule([], [_then(&"wind_speed", OceanRuleEffect.Operation.SET, 20.0)])
	var chained := _run([gale, windy], values, limits)
	_near(chained.values[&"foam_gain"], 8.0, "Rules see the results of earlier rules")

	# The example from the request: if depth < 1 m and wind > 12 then foam += 5, per point.
	values[&"wind_speed"] = 15.0
	var shallow := _rule([_if(&"local_depth", OceanRuleCondition.Comparison.LESS, 1.0), _if(&"wind_speed",
			OceanRuleCondition.Comparison.GREATER, 12.0)], [_then(&"local_foam", OceanRuleEffect.Operation.ADD, 5.0)])
	var local := _run([shallow], values, limits).local
	_check(local.count() == 1, "Local rule compiled for the shader")
	_near(local.evaluate(0.5).x, 5.0, "Local foam in shallow water")
	_near(local.evaluate(3.0).x, 0.0, "No local foam in deep water")
	values[&"wind_speed"] = 5.0
	_near(_run([shallow], values, limits).local.evaluate(0.5).x, 0.0, "Local rule respects its global condition")

	var calm_bay := _rule([_if(&"local_depth", OceanRuleCondition.Comparison.GREATER, 2.0),
			_if(&"local_depth", OceanRuleCondition.Comparison.LESS, 6.0)],
			[_then(&"local_wave_size", OceanRuleEffect.Operation.MULTIPLY, 0.5),
			_then(&"local_water_level", OceanRuleEffect.Operation.ADD, 0.3)])
	var bay := _run([calm_bay], values, limits).local
	_near(bay.evaluate(4.0).y, 0.5, "Depth range: wave size inside")
	_near(bay.evaluate(8.0).y, 1.0, "Depth range: wave size outside")
	_near(bay.evaluate(4.0).z, 0.3, "Local water level")

	var bad := _rule([_if(&"local_depth", OceanRuleCondition.Comparison.LESS, 1.0)],
			[_then(&"wind_speed", OceanRuleEffect.Operation.ADD, 1.0), _then(&"wave_height", OceanRuleEffect.Operation.ADD, 1.0)])
	var unknown := _rule([_if(&"nonsense", OceanRuleCondition.Comparison.LESS, 1.0)], [])
	_check(_run([bad, unknown], values, limits).problems.size() == 3, "Invalid rules are reported")

	var preset: OceanRuleSet = load("res://world/water/ocean/rules/presets/coastal_rules.tres")
	_check(preset != null and preset.rules.size() == 2, "Example rule set loads")
	var spectrum := OceanSpectrum.new()
	var params := OceanRuleEngine.parameters(spectrum)
	_check(params.has(&"wind_speed") and params.has(&"foam_gain"), "Spectrum parameters are rule inputs")
	_check(OceanRuleEngine.limits(spectrum).has(&"wavelength_scale"), "Parameter ranges come from export hints")
	var longer := spectrum.duplicate() as OceanSpectrum
	longer.wavelength_scale = 2.0
	_near(longer.peak_wavelength() / spectrum.peak_wavelength(), 2.0, "Horizontal size doubles the dominant wave length")
	longer.wavelength_scale = 8.0
	var tiles := OceanSimulation.tiles_for(longer, 4)
	_check(tiles[0] >= OceanSimulation.PEAK_WAVES_PER_TILE * longer.peak_wavelength() - TOLERANCE,
			"Longest cascade grows to fit long waves")
	print("Ocean rules: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _run(list: Array[OceanRule], values: Dictionary[StringName, float],
		limits: Dictionary[StringName, Vector2]) -> OceanRuleEngine.Result:
	var set := OceanRuleSet.new()
	set.rules = list
	return OceanRuleEngine.evaluate(set, values, limits)


func _rule(conditions: Array[OceanRuleCondition], effects: Array[OceanRuleEffect]) -> OceanRule:
	var rule := OceanRule.new()
	rule.conditions = conditions
	rule.effects = effects
	return rule


func _if(parameter: StringName, comparison: OceanRuleCondition.Comparison, threshold: float) -> OceanRuleCondition:
	var c := OceanRuleCondition.new()
	c.parameter = parameter
	c.comparison = comparison
	c.threshold = threshold
	return c


func _then(target: StringName, operation: OceanRuleEffect.Operation, amount: float) -> OceanRuleEffect:
	var e := OceanRuleEffect.new()
	e.target = target
	e.operation = operation
	e.amount = amount
	return e


func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) <= TOLERANCE, "%s (got %.3f, expected %.3f)" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", label)
