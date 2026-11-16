class_name OceanTunerReadouts
extends VBoxContainer
## What the current sea state amounts to, in physical terms, and warnings when it stops being a sea
## that could exist.

const REFRESH_INTERVAL := 0.25
const WARNING_COLOR := Color(1.0, 0.72, 0.35)

var _ocean: Ocean
var _summary := Label.new()
var _warnings := Label.new()
var _until_refresh := 0.0


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	add_child(_summary)
	_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warnings.add_theme_color_override("font_color", WARNING_COLOR)
	add_child(_warnings)


func _process(delta: float) -> void:
	_until_refresh -= delta
	if _until_refresh > 0.0 or not is_visible_in_tree():
		return
	_until_refresh = REFRESH_INTERVAL
	refresh()


func refresh() -> void:
	var sea := _ocean.spectrum
	if sea == null:
		return
	var measured := _ocean.wave_height()
	var wind := sea.wind_speed
	var lines := PackedStringArray([
		"Beaufort %d: %s (%.1f m/s)" % [OceanSeaStats.beaufort(wind), OceanSeaStats.beaufort_name(wind), wind],
		"Wave height %.2f m (expected in deep water: %.2f m)" % [measured, OceanSeaStats.expected_wave_height(sea)],
	])
	if sea.swell_height > 0.0:
		lines.append("Main waves: %.2f m, period %.1f s, length %.0f m, speed %.1f m/s" % [
				OceanSeaStats.swell_wave_height(sea), sea.swell_period, sea.swell_wavelength(),
				sea.swell_wavelength() / sea.swell_period])
	else:
		lines.append("Main waves: none (swell height is 0)")
	lines.append("Surface waves: %.2f m, period %.1f s, length %.0f m, steepness 1/%.0f" % [
			OceanSeaStats.surface_wave_height(sea), OceanSeaStats.peak_period(sea), sea.peak_wavelength(),
			1.0 / maxf(OceanSeaStats.steepness(sea, measured), 1.0e-4)])
	_summary.text = "\n".join(lines)
	var warnings := OceanSeaStats.warnings(sea, measured)
	_warnings.text = "\n".join(warnings)
	_warnings.visible = not warnings.is_empty()
