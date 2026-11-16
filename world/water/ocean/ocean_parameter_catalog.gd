class_name OceanParameterCatalog
extends RefCounted
## Lists the tunable numbers of an object from its `@export` declarations, so sliders, rules and
## presets all work from one description. A new exported number shows up everywhere by itself.

## Friendlier names than the property name, where that helps.
const LABELS: Dictionary[StringName, String] = {
	&"swell_height": "Swell height",
	&"swell_period": "Swell period",
	&"swell_direction": "Swell direction",
	&"swell_spread": "Swell spread",
	&"fetch": "Open water upwind",
	&"wind_spread": "Wind wave spread",
	&"choppiness": "Crest sharpness",
	&"height_scale": "Vertical size",
	&"wavelength_scale": "Horizontal size",
	&"short_wave_cutoff": "Smoothness",
	&"foam_threshold": "Foam amount",
	&"depth": "Water depth",
	&"level": "Sea level",
	&"breaker_ratio": "Max wave per depth",
	&"wave_setup": "Shore set-up",
	&"min_shore_wave": "Smallest shore wave",
	&"foreshore_slope": "Beach face slope",
	&"shore_wave_depth": "Shore wave depth",
	&"shore_wave_share": "Shore wave share",
	&"shore_lee_share": "Sheltered shore waves",
	&"curl_strength": "Curling breakers",
	&"sss_crest_strength": "Crest glow",
	&"sss_view_strength": "Glow towards the sun",
	&"murk_blur": "Blur through deep water",
	&"refraction_full_distance": "Refraction distance",
	&"base_slope_variance": "Fine ripple roughness",
	&"sun_specular_strength": "Sun glitter",
	&"foam_scale": "Foam pattern size",
	&"foam_cascade_falloff": "Small-wave foam",
	&"surf_depth": "Surf zone depth",
	&"foam_far_distance": "Foam detail distance",
	&"min_jacobian": "Fold limit",
	&"reflection_blur": "Reflection blur",
	&"capillary_tile": "Close-up ripple size",
	&"capillary_speed": "Close-up ripple drift",
	&"bubble_strength": "Bubble glow",
	&"gust_strength": "Wind gusts",
	&"gust_size": "Gust patch size",
}

## Shown as the tooltip of a control. Doc comments are not available in an exported game.
const DESCRIPTIONS: Dictionary[StringName, String] = {
	&"swell_height": "Main waves: long, regular swell from a distant storm. The local wind doesn't change it. 0: none.",
	&"swell_period": "Seconds between swell crests. Longer: longer, faster waves that came from further away.",
	&"swell_direction": "Direction the swell travels in, independent of the local wind.",
	&"swell_spread": "How far swell directions stray from the main one. Small: long, straight crests.",
	&"wind_speed": "Wind 10 m above the sea. Builds the surface waves on top of the swell, about as high as its square.",
	&"wind_direction": "Direction the wind blows the surface waves towards. Can differ from the swell.",
	&"fetch": "Open water the wind crossed to get here. A bay (10 km): small, short chop. Open ocean (500 km): a big sea.",
	&"wind_spread": "Spread of surface wave directions. 1: a real wind sea. Lower: long, aligned crests. Higher: confused.",
	&"choppiness": "Pulls water towards the crests. Long swell is too gentle to sharpen much. Above about 1.2 crests fold.",
	&"short_wave_cutoff": "Removes waves shorter than about this length.",
	&"depth": "Depth of the open sea. Shallow water slows long waves and takes their energy.",
	&"height_scale": "Artistic: multiplies the height of all waves. 1 is what the swell and wind really give.",
	&"wavelength_scale": "Artistic: multiplies the length of the wind waves. 1 is physical. Swell length follows its period.",
	&"foam_threshold": "How easily crests turn white. Higher: more whitecaps.",
	&"foam_gain": "How fast foam builds up where crests break.",
	&"foam_lifetime": "Time for whitecap foam to fade to about a third.",
	&"level": "Rest level of the sea (tide, flooding).",
	&"breaker_ratio": "Crest height allowed per metre of depth. Real waves break at about 0.39.",
	&"wave_setup": "Extra water at the waterline from breaking waves. Real set-up is about 0.2.",
	&"min_shore_wave": "Share of the wave that still reaches the waterline as a lapping wave.",
	&"transition_time": "Seconds a new sea state takes to fade in when it changes the longest waves. 0: at once.",
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
