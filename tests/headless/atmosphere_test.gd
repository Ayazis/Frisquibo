extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/atmosphere_test.gd
## The time of day and the atmosphere: the sun's path, the air's physics, the light and exposure it
## gives, the weathers and quality tiers, lightning, the sky shader (compiles, same constants as the
## CPU model) and the Atmosphere node in a running tree.

const TIERS: Array[String] = ["low", "medium", "high", "ultra"]
## Quality values that must not shrink from one tier to the next.
const GROWING: Array[StringName] = [&"radiance_size", &"atmosphere_steps", &"radiance_atmosphere_steps",
		&"cloud_steps", &"radiance_cloud_steps", &"cloud_light_steps", &"volumetric_fog_size",
		&"volumetric_fog_depth", &"volumetric_fog_length", &"shadow_distance"]
const WEATHER_FOLDER := "res://world/time_of_day/weather"
const SHADER_FOLDER := "res://world/time_of_day"
const ATMOSPHERE_INCLUDE := "res://world/time_of_day/sky_atmosphere.gdshaderinc"
const LATITUDE := 43.0
const SUMMER := 172.0
const WINTER := 355.0
const EPSILON := 0.01
var _failures := 0


func _initialize() -> void:
	_test_sun_path()
	_test_air()
	_test_lighting()
	_test_weathers()
	_test_quality()
	_test_lightning()
	_test_shaders()
	await _test_node()
	print("Atmosphere: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _test_sun_path() -> void:
	var noon := SunPath.sun_direction(12.0, SUMMER, LATITUDE, 0.0)
	_check(absf(noon.x) < EPSILON and noon.z > 0.0, "Noon sun stands due south (+Z with north at -Z)")
	var expected := 90.0 - LATITUDE + SunPath.AXIAL_TILT_DEGREES
	_check(absf(SunPath.elevation_degrees(noon) - expected) < 0.2, "Midsummer noon sun at 90 - latitude + tilt")
	var winter := SunPath.sun_direction(12.0, WINTER, LATITUDE, 0.0)
	_check(absf(SunPath.elevation_degrees(winter) - (90.0 - LATITUDE - SunPath.AXIAL_TILT_DEGREES)) < 0.2,
			"Midwinter noon sun at 90 - latitude - tilt")
	_check(SunPath.sun_direction(6.0, SUMMER, LATITUDE, 0.0).x > 0.9, "Morning sun in the east (+X)")
	_check(SunPath.sun_direction(18.0, SUMMER, LATITUDE, 0.0).x < -0.9, "Evening sun in the west")
	_check(SunPath.sun_direction(0.0, SUMMER, LATITUDE, 0.0).y < 0.0, "Midnight sun below the horizon")
	_check(noon.y > SunPath.sun_direction(10.0, SUMMER, LATITUDE, 0.0).y, "The sun is highest at noon")
	var turned := SunPath.sun_direction(12.0, SUMMER, LATITUDE, deg_to_rad(90.0))
	_check(turned.is_equal_approx(noon.rotated(Vector3.UP, deg_to_rad(90.0))), "North heading turns the sky")
	var full := SunPath.moon_direction(22.0, SUMMER, LATITUDE, 0.0, 0.5)
	var sun := SunPath.sun_direction(22.0, SUMMER, LATITUDE, 0.0)
	_check(full.dot(sun) < -0.8, "A full moon stands roughly opposite the sun")
	var stars := SunPath.star_basis(21.0, SUMMER, LATITUDE, 0.0)
	_check(stars.orthonormalized().is_equal_approx(stars), "Star basis is a rotation")
	_check(absf(SunPath.elevation_degrees(stars.z) - LATITUDE) < 0.2, "The celestial pole stands at the latitude, north")
	_check(stars.z.z < 0.0, "The celestial pole lies north")


func _test_air() -> void:
	var zenith := AtmosphereModel.transmittance(0.0, 1.0, 1.0)
	_check(zenith.x > 0.85 and zenith.x > zenith.y and zenith.y > zenith.z, "Overhead sun: little loss, blue lost most")
	var low := AtmosphereModel.transmittance(0.0, sin(deg_to_rad(2.0)), 1.0)
	_check(low.x < zenith.x * 0.7 and low.z < low.x * 0.2, "Low sun: dimmer and red")
	_check(AtmosphereModel.transmittance(0.0, sin(deg_to_rad(-3.0)), 1.0) == Vector3.ZERO, "Set sun: no light at the ground")
	_check(AtmosphereModel.transmittance(3000.0, sin(deg_to_rad(-1.0)), 1.0).x > 0.0, "Clouds still see a just-set sun")
	_check(AtmosphereModel.transmittance(0.0, 0.3, 4.0).x < AtmosphereModel.transmittance(0.0, 0.3, 1.0).x,
			"Haze dims the sun")
	var high_sun := _towards(60.0)
	var blue := AtmosphereModel.sky_radiance(Vector3.UP, high_sun, 1.0, 1.0)
	_check(blue.z > blue.y and blue.y > blue.x, "Day zenith is blue")
	var ratio := AtmosphereModel.luminance(blue)
	_check(ratio > 0.005 and ratio < 0.1, "Zenith radiance is a plausible share of the sun's irradiance (%.4f)" % ratio)
	var horizon := AtmosphereModel.sky_radiance(Vector3(1.0, 0.03, 0.0).normalized(), high_sun, 1.0, 1.0)
	_check(AtmosphereModel.luminance(horizon) > ratio, "The horizon is brighter than the zenith")
	var setting := _towards(2.0)
	var towards_sun := AtmosphereModel.sky_radiance(Vector3(0.0, 0.05, -1.0).normalized(), setting, 1.0, 1.0)
	_check(towards_sun.x > towards_sun.y and towards_sun.y > towards_sun.z, "Sunset sky glows orange towards the sun")
	var twilight := AtmosphereModel.sky_radiance(Vector3.UP, _towards(-4.0), 1.0, 1.0)
	_check(twilight.z > twilight.x and AtmosphereModel.luminance(twilight) < ratio * 0.1,
			"Twilight zenith: dim and still blue (ozone)")
	var night := AtmosphereModel.sky_radiance(Vector3.UP, _towards(-30.0), 1.0, 1.0)
	_check(AtmosphereModel.luminance(night) < 1e-6, "No sunlight in the night sky")
	_check(absf(AtmosphereModel.column(0.0, 1.0, AtmosphereModel.RAYLEIGH_HEIGHT) - AtmosphereModel.RAYLEIGH_HEIGHT)
			< 0.05 * AtmosphereModel.RAYLEIGH_HEIGHT, "Overhead air column is one scale height")


func _test_lighting() -> void:
	var fair := load(WEATHER_FOLDER.path_join("fair.tres")) as SkyWeather
	var moon := SunPath.moon_direction(23.0, SUMMER, LATITUDE, 0.0, 0.45)
	var noon := AtmosphereLighting.evaluate(_towards(60.0), moon, 0.45, fair)
	_check(noon.sun_energy > 1.2 and noon.sun_color.b > 0.7, "Noon sun: bright and near white")
	_check(noon.sun_casts_shadows and noon.night < EPSILON, "Noon: the sun casts the shadows, no stars")
	var evening := AtmosphereLighting.evaluate(_towards(3.0), moon, 0.45, fair)
	_check(evening.sun_color.g < 0.6 and evening.sun_color.b < evening.sun_color.g, "Low sun light is orange")
	_check(evening.exposure > noon.exposure, "The exposure opens up as the light fades")
	var night := AtmosphereLighting.evaluate(SunPath.sun_direction(23.0, SUMMER, LATITUDE, 0.0), moon, 0.45, fair)
	_check(night.sun_energy == 0.0 and night.moon_energy > 0.0, "Night: moonlight only")
	_check(not night.sun_casts_shadows, "Night: the moon casts the shadows")
	_check(night.night > 0.99, "Night: the stars are out")
	_check(night.moon_color.b > night.moon_color.r, "Moonlight is cool")
	var reference := AtmosphereLighting.EXPOSURE_KEY / AtmosphereLighting.reference_radiance()
	_check(night.exposure <= reference * AtmosphereLighting.MAX_GAIN + EPSILON, "Night exposure is capped")
	_check(night.exposure > evening.exposure * 0.99, "Night is exposed at least as far as the evening")
	var overcast := load(WEATHER_FOLDER.path_join("overcast.tres")) as SkyWeather
	var grey := AtmosphereLighting.evaluate(_towards(60.0), moon, 0.45, overcast)
	_check(grey.sun_energy < noon.sun_energy * 0.5, "Overcast hides most of the sun")
	_check(grey.cloud_light.x > noon.sun_energy * 0.5, "Clouds are still sunlit from above")
	_check(AtmosphereLighting.illuminated_fraction(0.0) < EPSILON and AtmosphereLighting.illuminated_fraction(0.5) > 0.99,
			"Moon phases: new is dark, full is lit")


func _test_weathers() -> void:
	var names: Array[String] = []
	for file: String in DirAccess.get_files_at(WEATHER_FOLDER):
		if file.get_extension() != "tres":
			continue
		var w := load(WEATHER_FOLDER.path_join(file)) as SkyWeather
		_check(w != null, "Weather loads: " + file)
		if w == null:
			continue
		names.append(w.display_name)
		_check(w.cloud_top > w.cloud_bottom, "%s: cloud top above its base" % file)
		_check(w.fog_density >= 0.0 and w.volumetric_fog_density >= 0.0, "%s: fog not negative" % file)
	_check(names.size() >= 4, "At least four weathers")
	var clear := load(WEATHER_FOLDER.path_join("clear.tres")) as SkyWeather
	var storm := load(WEATHER_FOLDER.path_join("storm.tres")) as SkyWeather
	_check(storm.cloud_coverage > clear.cloud_coverage and storm.lightning_per_minute > 0.0, "Storms are cloudy, with lightning")
	_check(is_equal_approx(SkyWeather.blend(clear, storm, 0.0).cloud_coverage, clear.cloud_coverage), "Blend 0 is the first")
	_check(is_equal_approx(SkyWeather.blend(clear, storm, 1.0).turbidity, storm.turbidity), "Blend 1 is the second")
	var half := SkyWeather.blend(clear, storm, 0.5)
	_check(is_equal_approx(half.fog_density, (clear.fog_density + storm.fog_density) / 2.0), "Blend 0.5 is halfway")
	_check(half.wind.is_equal_approx(clear.wind.lerp(storm.wind, 0.5)), "Wind blends too")


func _test_quality() -> void:
	var previous: AtmosphereQuality = null
	for tier: String in TIERS:
		var current := load("res://data/quality/atmosphere_%s.tres" % tier) as AtmosphereQuality
		_check(current != null, "Tier atmosphere_%s loads" % tier)
		if previous != null and current != null:
			for key: StringName in GROWING:
				_check(_number(current.get(key)) >= _number(previous.get(key)),
						"atmosphere_%s: %s does not shrink from the tier below" % [tier, key])
		previous = current
	var high := load("res://data/quality/atmosphere_high.tres") as AtmosphereQuality
	_check(Atmosphere.DEFAULT_QUALITY.resource_path == high.resource_path, "Desktop defaults to High")
	_check(high.volumetric_fog and high.ssao and high.ssil and high.cloud_detail, "High has the full look")
	_check(high.sun_angular_diameter > 0.5, "High: soft shadows of the sun's real size")
	_check(Atmosphere.WEB_QUALITY.resource_path.ends_with("atmosphere_low.tres"), "The web uses Low")


func _test_lightning() -> void:
	var a := LightningStrikes.new(3)
	var b := LightningStrikes.new(3)
	var peak := 0.0
	var same := true
	for i in range(60 * 120):
		var fa := a.advance(1.0 / 60.0, 6.0)
		var fb := b.advance(1.0 / 60.0, 6.0)
		same = same and is_equal_approx(fa, fb)
		peak = maxf(peak, fa)
	_check(same, "Lightning repeats for the same seed")
	_check(peak > 0.3, "Six strikes a minute flash within two minutes")
	var calm := LightningStrikes.new(3)
	var any := 0.0
	for i in range(600):
		any = maxf(any, calm.advance(0.1, 0.0))
	_check(any == 0.0, "No strikes at rate 0")
	_check(LightningStrikes.flash(0.0) >= 1.0 and LightningStrikes.flash(2.0) < 1e-3, "A strike flashes, then fades")


func _test_shaders() -> void:
	var count := 0
	for file: String in DirAccess.get_files_at(SHADER_FOLDER):
		if file.get_extension() == "gdshader":
			count += 1
			var shader := load(SHADER_FOLDER.path_join(file)) as Shader
			_check(shader != null and not shader.get_shader_uniform_list().is_empty(), "Compiles: " + file)
	_check(count > 0, "Found the sky shader")
	var source := FileAccess.get_file_as_string(ATMOSPHERE_INCLUDE)
	_check_constant(source, "EARTH_RADIUS", AtmosphereModel.EARTH_RADIUS)
	_check_constant(source, "ATMOSPHERE_RADIUS", AtmosphereModel.ATMOSPHERE_RADIUS)
	_check_constant(source, "RAYLEIGH_HEIGHT", AtmosphereModel.RAYLEIGH_HEIGHT)
	_check_constant(source, "MIE_SCATTERING", AtmosphereModel.MIE_SCATTERING)
	_check_constant(source, "MIE_EXTINCTION", AtmosphereModel.MIE_EXTINCTION)
	_check_constant(source, "MIE_HEIGHT", AtmosphereModel.MIE_HEIGHT)
	_check_constant(source, "MIE_ANISOTROPY", AtmosphereModel.MIE_ANISOTROPY)
	_check_constant(source, "MULTIPLE_SCATTERING", AtmosphereModel.MULTIPLE_SCATTERING)
	_check_constant(source, "EARTH_SHADOW_SOFTNESS", AtmosphereModel.EARTH_SHADOW_SOFTNESS)
	_check_vector(source, "RAYLEIGH", AtmosphereModel.RAYLEIGH)
	_check_vector(source, "OZONE", AtmosphereModel.OZONE)


func _test_node() -> void:
	var time := TimeOfDay.new()
	time.hour = 13.0
	var atmosphere := Atmosphere.new()
	atmosphere.time = time
	root.add_child(time)
	root.add_child(atmosphere)
	for i in range(5):
		await process_frame
	_check(atmosphere.environment != null and atmosphere.environment.sky != null, "The atmosphere builds its sky")
	_check(atmosphere.sun.visible and not atmosphere.moon.visible, "Afternoon: the sun shines, the moon light is off")
	_check(atmosphere.environment.tonemap_mode == Environment.TONE_MAPPER_AGX, "Filmic (AgX) tone mapping")
	var shadow_down := -atmosphere.sun.global_basis.z
	_check(shadow_down.dot(time.sun_direction()) < -0.999, "The sun light shines from the sun")
	time.hour = 23.0
	atmosphere.update_now()
	await process_frame
	_check(not atmosphere.sun.visible, "Night: the sun light is off")
	var storm := load(WEATHER_FOLDER.path_join("storm.tres")) as SkyWeather
	atmosphere.set_weather(storm, 0.5)
	for i in range(3):
		await process_frame
	var partway := atmosphere.current_weather().cloud_coverage
	_check(partway < storm.cloud_coverage, "The weather changes gradually")
	time.hours_per_second = 1.0
	var start := time.hour
	await create_timer(0.7).timeout
	_check(atmosphere.current_weather().cloud_coverage > partway, "The change goes on")
	_check(not is_equal_approx(time.hour, start), "The clock runs")
	atmosphere.queue_free()
	time.queue_free()
	await process_frame


## A sun `degrees` above the horizon, due north (-Z).
func _towards(degrees: float) -> Vector3:
	var e := deg_to_rad(degrees)
	return Vector3(0.0, sin(e), -cos(e))


func _check_constant(source: String, constant: String, expected: float) -> void:
	var regex := RegEx.create_from_string("const float %s = ([-0-9.e]+);" % constant)
	var found := regex.search(source)
	_check(found != null and _close(found.get_string(1).to_float(), expected),
			"Shader constant %s matches AtmosphereModel" % constant)


func _check_vector(source: String, constant: String, expected: Vector3) -> void:
	var regex := RegEx.create_from_string(
			"const vec3 %s = vec3\\(([-0-9.e]+), ([-0-9.e]+), ([-0-9.e]+)\\)( \\* ([-0-9.e]+))?;" % constant)
	var found := regex.search(source)
	if found == null:
		_check(false, "Shader constant %s found" % constant)
		return
	var scale := found.get_string(5).to_float() if found.get_string(5) != "" else 1.0
	var value := Vector3(found.get_string(1).to_float(), found.get_string(2).to_float(), found.get_string(3).to_float()) * scale
	_check(_close(value.x, expected.x) and _close(value.y, expected.y) and _close(value.z, expected.z),
			"Shader constant %s matches AtmosphereModel" % constant)


## Equal to a part in 10^5: the constants are tiny (per-metre coefficients), so a relative test.
func _close(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-5 * maxf(absf(a), absf(b))


func _number(value: Variant) -> float:
	if value is int:
		var whole: int = value
		return float(whole)
	var real: float = value
	return real


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
