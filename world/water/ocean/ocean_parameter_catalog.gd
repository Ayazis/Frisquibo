class_name OceanParameterCatalog
extends RefCounted
## Lists the tunable numbers of an object from its `@export` declarations, so sliders, rules and
## presets all work from one description. A new exported number shows up everywhere by itself.

## Friendlier names than the property name. Each is unique, since rules list them side by side.
const LABELS: Dictionary[StringName, String] = {
	&"swell_height": "Swell height",
	&"swell_period": "Swell period",
	&"swell_direction": "Swell direction",
	&"swell_spread": "Swell spread",
	&"choppiness": "Crest sharpness",
	&"crest_lean": "Crest lean",
	&"white_water_height": "Breaking white water",
	&"short_wave_cutoff": "Smallest waves",
	&"min_jacobian": "Fold limit",
	&"transition_time": "Fade-in time",
	&"surface_height": "Surface wave height",
	&"surface_length": "Surface wave length",
	&"surface_direction": "Surface wave direction",
	&"surface_spread": "Surface wave spread",
	&"spray_amount": "Spray",
	&"gust_strength": "Gusts",
	&"gust_size": "Gust patch size",
	&"capillary_tile": "Ripple size",
	&"capillary_speed": "Ripple drift",
	&"foam_threshold": "Whitecap amount",
	&"foam_gain": "Foam build-up",
	&"foam_lifetime": "Foam lifetime",
	&"foam_scale": "Foam pattern size",
	&"foam_softness": "Foam edge softness",
	&"whitecap_strength": "Whitecap brightness",
	&"foam_cascade_falloff": "Small-wave foam",
	&"foam_far_distance": "Foam detail distance",
	&"foam_streaks": "Wind streaks",
	&"streak_length": "Streak length",
	&"bubble_strength": "Bubble glow",
	&"foam_relief": "Foam lumpiness",
	&"depth": "Open sea depth",
	&"level": "Sea level",
	&"breaker_ratio": "Breaking point",
	&"wave_setup": "Shore set-up",
	&"min_shore_wave": "Smallest shore wave",
	&"shore_wave_depth": "Shore wave depth",
	&"shore_wave_share": "Shore wave share",
	&"shore_lee_share": "Sheltered shore waves",
	&"curl_strength": "Curling breakers",
	&"foreshore_slope": "Beach slope",
	&"shore_foam_width": "Shore foam width",
	&"surf_depth": "Surf zone depth",
	&"absorption_red": "Red absorption",
	&"absorption_green": "Green absorption",
	&"absorption_blue": "Blue absorption",
	&"sss_crest_strength": "Crest glow",
	&"sss_view_strength": "Glow towards the sun",
	&"murk_blur": "Blur through deep water",
	&"refraction_strength": "Refraction",
	&"refraction_full_distance": "Refraction distance",
	&"reflection_distortion": "Reflection wobble",
	&"reflection_blur": "Reflection blur",
	&"base_slope_variance": "Fine ripple roughness",
	&"sun_specular_strength": "Sun glitter",
	&"caustic_strength": "Caustics",
	&"caustic_fade": "Caustic depth fade",
	&"seabed_light_loss": "Seabed light loss",
}

## Shown as the tooltip of a control. Doc comments are not available in an exported game.
const DESCRIPTIONS: Dictionary[StringName, String] = {
	&"surface_spread": "Spread of surface wave directions. 1: a real sea. Lower: long, aligned crests. Higher: confused.",
	&"surface_direction": "Direction the surface waves travel in. Usually close to the wind's.",
	&"surface_length": "Crest-to-crest length of the bigger surface waves. Short: choppy. Long: rolling.",
	&"surface_height": "Shorter, irregular waves on top of the swell. Set directly: the wind doesn't change them. 0: none.",
	&"swell_height": "Long, regular waves from a distant storm: the main shape of the sea. 0: none.",
	&"swell_period": "Seconds between swell crests. Longer: longer, faster waves.",
	&"swell_direction": "Direction the swell travels in.",
	&"swell_spread": "How far swell directions stray from the main one. Small: long, straight crests.",
	&"wind_speed": "Wind 10 m above the sea. Drives ripples, gusts, spray and foam streaks. Doesn't change the waves.",
	&"wind_direction": "Direction the wind blows towards: ripples, foam drift, spray and streaks follow it.",
	&"choppiness": "Pulls water towards the crests: sharp peaks, wide troughs. Above about 1.2 crests fold.",
	&"short_wave_cutoff": "Removes waves shorter than about this length. Higher: smoother water.",
	&"crest_lean": "Surface wave crests lean forward: steeper front, gentler back. Gentle swell barely changes.",
	&"white_water_height": "Height of the tumbling white water on breaking crests, as a share of the wave. 0: smooth crests.",
	&"spray_amount": "Spray the wind tears off breaking crests, from Beaufort 6 up. 1 is natural, 0: none.",
	&"depth": "Depth of the open sea. Shallow water slows long waves and takes their energy.",
	&"foam_threshold": "How easily crests turn white. Higher: more whitecaps. Auto follows the wind.",
	&"foam_gain": "How fast foam builds up where crests break.",
	&"foam_lifetime": "Time for whitecap foam to fade to about a third.",
	&"level": "Rest level of the sea (tide, flooding).",
	&"breaker_ratio": "How high a crest may get per metre of depth before it breaks. Real waves: about 0.39.",
	&"wave_setup": "Extra water at the waterline from breaking waves. Real set-up is about 0.2.",
	&"min_shore_wave": "Share of the wave that still reaches the waterline as a lapping wave.",
	&"transition_time": "Seconds a new sea state takes to fade in when its longest waves change. 0: at once.",
	&"foreshore_slope": "Slope of the sand at the waterline. Steeper beaches: waves run further up (wet sand, swash).",
	&"shore_wave_depth": "Water shallower than this turns the waves to meet the beach, where they steepen and break.",
	&"shore_wave_share": "Share of the open sea's wave energy that becomes waves breaking on the beach.",
	&"shore_lee_share": "Shore waves left on a coast facing away from the open sea's waves.",
	&"curl_strength": "How hard breakers plunge where the beach makes them. 1 is physical, 0: all breakers spill.",
	&"absorption_red": "Red light lost per metre of water. Red dies first: that makes the sea blue-green.",
	&"absorption_green": "Green light lost per metre. Higher: bluer, darker water.",
	&"absorption_blue": "Blue light lost per metre. Higher (silt, algae): greener, murkier water.",
	&"sss_crest_strength": "Sunlight glowing through thin wave crests.",
	&"sss_view_strength": "Glow in the water when looking towards the sun.",
	&"murk_blur": "How much the seabed blurs when seen through deep water.",
	&"refraction_strength": "How far waves bend the view of what lies under water.",
	&"refraction_full_distance": "Beyond this distance the bending shrinks, so far water doesn't smear.",
	&"reflection_distortion": "How far waves bend the mirrored world.",
	&"reflection_blur": "How much ripples too small to see smear the mirrored world into streaks. 1 is physical.",
	&"base_slope_variance": "Roughness from ripples too small to simulate. Higher: wider, softer sun glitter.",
	&"sun_specular_strength": "Brightness of the sun's glitter. 1 is physical.",
	&"capillary_tile": "Size of the fine ripples drawn close to the camera (the fine-ripple roughness, resolved).",
	&"capillary_speed": "How fast the fine close-up ripples drift downwind.",
	&"gust_strength": "Patches of rougher and glassier water that drift downwind, as real wind is never even.",
	&"gust_size": "Size of the gust patches.",
	&"foam_scale": "Size of the foam bubble pattern.",
	&"foam_softness": "Softness of foam edges.",
	&"whitecap_strength": "Brightness of whitecaps on breaking crests.",
	&"foam_cascade_falloff": "Foam from the smaller wave scales: lower gives thinner, shorter-lived streaks.",
	&"shore_foam_width": "Width of the foam line where water meets land.",
	&"surf_depth": "Breaking-wave foam thins out in water deeper than this.",
	&"foam_far_distance": "Beyond this distance foam loses its fine pattern.",
	&"bubble_strength": "Turquoise glow of bubbles that fresh whitecaps push under the surface.",
	&"foam_relief": "Lumpiness of thick foam: it catches the light on one side.",
	&"foam_streaks": "Foam blown into lines along the wind in a gale. Starts at Beaufort 7, full at 10.",
	&"streak_length": "How many times longer than wide the wind-blown foam streaks are.",
	&"caustic_strength": "Light the waves focus onto the seabed. 1 is physical; the pattern comes from the waves.",
	&"caustic_fade": "Extra fading of the light patterns with depth (deep ones already blur by the sun's size).",
	&"seabed_light_loss": "Light reaching the seabed crossed the water on the way down: deep sand is darker and bluer. 1 is physical.",
	&"min_jacobian": "Crests are held back where the surface would fold. Lower: sharper crests, more folding.",
}


## Names of the exported numbers per script, for names_of(): the declarations don't change while the
## game runs, and the Ocean reads its parameters every frame.
static var _names_by_script: Dictionary[Script, PackedStringArray] = {}


## Names of the exported numbers of `object`, as of() lists them; cached per script.
static func names_of(object: Object) -> PackedStringArray:
	var script: Script = object.get_script()
	if script != null and _names_by_script.has(script):
		return _names_by_script[script]
	var names := PackedStringArray()
	for parameter: OceanParameter in of(object, ""):
		names.append(parameter.name)
	if script != null:
		_names_by_script[script] = names
	return names


## Exported numbers of `object`, in declaration order. `default_group` names the ones declared
## outside an `@export_group`.
static func of(object: Object, default_group: String) -> Array[OceanParameter]:
	var result: Array[OceanParameter] = []
	var group := default_group
	for property: Dictionary in object.get_property_list():
		var usage: int = property.usage
		var property_name: String = property.name
		if (usage & PROPERTY_USAGE_CATEGORY) != 0:
			group = default_group
		elif (usage & PROPERTY_USAGE_GROUP) != 0:
			group = property_name if property_name != "" else default_group
		elif _is_exported_float(property):
			result.append(_describe(property, group))
	return result


static func _describe(property: Dictionary, group: String) -> OceanParameter:
	var parameter := OceanParameter.new()
	var property_name: String = property.name
	parameter.name = StringName(property_name)
	parameter.group = group
	parameter.label = LABELS.get(parameter.name, _sentence_case(property_name))
	parameter.description = DESCRIPTIONS.get(parameter.name, "")
	var hint_type: int = property.hint
	if hint_type == PROPERTY_HINT_RANGE:
		var hint: String = property.hint_string
		parameter.read_range_hint(hint)
	return parameter


## "wind_speed" becomes "Wind speed".
static func _sentence_case(property_name: String) -> String:
	var words := property_name.replace("_", " ")
	return words.left(1).to_upper() + words.substr(1)


static func _is_exported_float(property: Dictionary) -> bool:
	var type: int = property.type
	var usage: int = property.usage
	return (type == TYPE_FLOAT and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
			and (usage & PROPERTY_USAGE_EDITOR) != 0)
