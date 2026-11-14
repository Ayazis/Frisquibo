class_name OceanParameterCatalog
extends RefCounted
## Lists the tunable numbers of an object from its `@export` declarations, so sliders, rules and
## presets all work from one description. A new exported number shows up everywhere by itself.

## Friendlier names than the property name, where that helps.
const LABELS: Dictionary[StringName, String] = {
	&"height_scale": "Vertical size",
	&"wavelength_scale": "Horizontal size",
	&"short_wave_cutoff": "Smoothness",
	&"foam_threshold": "Foam amount",
	&"depth": "Water depth",
	&"level": "Sea level",
	&"breaker_ratio": "Max wave per depth",
	&"wave_setup": "Shore set-up",
	&"min_shore_wave": "Smallest shore wave",
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
}

## Shown as the tooltip of a control. Doc comments are not available in an exported game.
const DESCRIPTIONS: Dictionary[StringName, String] = {
	&"wind_speed": "Wind 10 m above the sea. Wave height grows roughly with its square.",
	&"wind_direction": "Direction the wind blows the waves towards.",
	&"fetch": "Open water the wind has blown over. Short (a bay): short, choppy waves. Long: swell.",
	&"depth": "Depth of the open sea. Shallow water slows long waves and takes their energy.",
	&"swell": "0: young wind sea with waves in many directions. Higher: long, aligned crests.",
	&"spread": "0: physical spreading of wave directions. 1: waves from every direction.",
	&"short_wave_cutoff": "Removes waves shorter than about this length.",
	&"choppiness": "Sharpens crests by pulling water towards them. Above about 1.2 the surface folds.",
	&"height_scale": "Artistic: multiplies wave height. 1 is what the wind and fetch really give.",
	&"wavelength_scale": "Artistic: multiplies the length of the dominant waves. 1 is physical.",
	&"foam_threshold": "How easily crests turn white. Higher: more whitecaps.",
	&"foam_gain": "How fast foam builds up where crests break.",
	&"foam_lifetime": "Time for whitecap foam to fade to about a third.",
	&"level": "Rest level of the sea (tide, flooding).",
	&"breaker_ratio": "Crest height allowed per metre of depth. Real waves break at about 0.39.",
	&"wave_setup": "Extra water at the waterline from breaking waves. Real set-up is about 0.2.",
	&"min_shore_wave": "Share of the wave that still reaches the waterline as a lapping wave.",
	&"absorption_red": "Red light lost per metre of water. Red dies first: that makes the sea blue-green.",
	&"absorption_green": "Green light lost per metre. Higher: bluer, darker water.",
	&"absorption_blue": "Blue light lost per metre. Higher (silt, algae): greener, murkier water.",
	&"sss_crest_strength": "Sunlight glowing through thin wave crests.",
	&"sss_view_strength": "Glow in the water when looking towards the sun.",
	&"murk_blur": "How much the seabed blurs when seen through deep water.",
	&"refraction_strength": "How far waves bend the view of what lies under water.",
	&"refraction_full_distance": "Beyond this distance the bending shrinks, so far water doesn't smear.",
	&"reflection_distortion": "How far waves bend the mirrored world.",
	&"base_slope_variance": "Roughness from ripples too small to simulate. Higher: wider, softer sun glitter.",
	&"sun_specular_strength": "Brightness of the sun's glitter. 1 is physical.",
	&"foam_scale": "Size of the foam bubble pattern.",
	&"foam_softness": "Softness of foam edges.",
	&"whitecap_strength": "Brightness of whitecaps on breaking crests.",
	&"foam_cascade_falloff": "Foam from the smaller wave scales: lower gives thinner, shorter-lived streaks.",
	&"shore_foam_width": "Width of the foam line where water meets land.",
	&"surf_depth": "Breaking-wave foam thins out in water deeper than this.",
	&"foam_far_distance": "Beyond this distance foam loses its fine pattern.",
	&"caustic_strength": "Brightness of the light patterns on the seabed.",
	&"caustic_scale": "Size of the light patterns on the seabed.",
	&"caustic_fade": "How fast the light patterns fade with depth.",
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
