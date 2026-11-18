class_name OceanLook
extends Resource
## How the sea looks once the waves exist: the colour and clarity of the water, foam, caustics.
## Every value has the name of the ocean.gdshader uniform it drives; OceanLookBinding pushes them.
## The defaults are the shader's own, so an untouched look changes nothing.

@export_group("Water colour")
## Light lost per metre of water, per colour. Red dies first, which is what makes the sea blue-green.
@export_range(0.0, 2.0, 0.005, "or_greater", "suffix:/m") var absorption_red := 0.42
@export_range(0.0, 2.0, 0.005, "or_greater", "suffix:/m") var absorption_green := 0.07
@export_range(0.0, 2.0, 0.005, "or_greater", "suffix:/m") var absorption_blue := 0.045
## Colour of light scattered back out of deep water.
@export var scatter_color := Color(0.012, 0.095, 0.11)
## Glow of sunlight passing through thin wave crests.
@export var sss_color := Color(0.06, 0.42, 0.36)
## Seen from below, outside the bright window overhead.
@export var deep_color := Color(0.004, 0.03, 0.04)
@export_range(0.0, 10.0, 0.05, "or_greater") var sss_crest_strength := 3.2
@export_range(0.0, 2.0, 0.01, "or_greater") var sss_view_strength := 0.35
## Screen mip levels of blur on what is seen through deep water.
@export_range(0.0, 8.0, 0.1) var murk_blur := 3.0

@export_group("Surface light")
@export_range(0.0, 0.3, 0.005, "or_greater") var refraction_strength := 0.06
## The refraction offset shrinks beyond this distance.
@export_range(0.5, 50.0, 0.5, "or_greater", "suffix:m") var refraction_full_distance := 8.0
@export_range(0.0, 0.2, 0.001, "or_greater") var reflection_distortion := 0.035
## Blur of the mirrored world by ripples too small to see. 1 is physical; 0 is a sharp mirror.
@export_range(0.0, 3.0, 0.01, "or_greater") var reflection_blur := 1.0
## Roughness from ripples smaller than the simulation resolves.
@export_range(0.0, 0.01, 0.0001, "or_greater") var base_slope_variance := 0.0006
@export_range(0.0, 4.0, 0.05, "or_greater") var sun_specular_strength := 1.0

@export_group("Wind")
## Metres covered by the close-up ripple pattern; its ripples are about a sixth of this.
@export_range(0.2, 10.0, 0.05, "or_greater", "suffix:m") var capillary_tile := 1.2
## How fast the close-up ripples drift downwind.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:m/s") var capillary_speed := 0.25
## Uneven wind: drifting patches of rougher and glassier water. 0 is an even wind.
@export_range(0.0, 1.0, 0.01) var gust_strength := 0.5
@export_range(5.0, 500.0, 1.0, "or_greater", "suffix:m") var gust_size := 60.0

@export_group("Foam")
@export var foam_color := Color(0.86, 0.9, 0.9)
@export_range(0.02, 2.0, 0.01, "or_greater") var foam_scale := 0.22
@export_range(0.01, 1.0, 0.01) var foam_softness := 0.18
@export_range(0.0, 4.0, 0.05, "or_greater") var whitecap_strength := 1.0
## Smaller wave scales make thinner, shorter-lived foam.
@export_range(0.0, 1.0, 0.01) var foam_cascade_falloff := 0.6
@export_range(20.0, 2000.0, 10.0, "or_greater", "suffix:m") var foam_far_distance := 250.0
## Cover of wind-blown foam streaks in a full gale; they start at Beaufort 7 and grow with the wind.
@export_range(0.0, 1.0, 0.01) var foam_streaks := 0.35
@export_range(1.0, 60.0, 0.5) var streak_length := 24.0
## Turquoise glow of bubbles pushed under the surface by fresh whitecaps.
@export_range(0.0, 2.0, 0.01, "or_greater") var bubble_strength := 0.5
## Lumpiness of thick foam.
@export_range(0.0, 3.0, 0.05, "or_greater") var foam_relief := 1.0

@export_group("Beach")
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:m") var shore_foam_width := 0.9
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var surf_depth := 1.6

@export_group("Caustics")
## 1: the light the simulated waves really focus onto the seabed.
@export_range(0.0, 4.0, 0.05, "or_greater") var caustic_strength := 1.0
## Extra fading with depth, on top of the blur the sun's size gives deep caustics.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:/m") var caustic_fade := 0.1
## Light on the seabed already crossed the water once on its way down. 1 is physical.
@export_range(0.0, 1.0, 0.01) var seabed_light_loss := 1.0

@export_group("Crest shape")
## Crests are held back where the surface would compress below this (see choppiness).
@export_range(0.0, 1.0, 0.01) var min_jacobian := 0.12
