class_name IslandScene
extends Node3D
## The water demo: an island in the FFT ocean. The sea runs up a sandy beach all round; inland a pond
## sits above sea level and a river runs from it down to the east coast. Boats and barrels float.

const STATES: Array[OceanSpectrum] = [
	preload("res://world/water/ocean/presets/calm_sea.tres"),
	preload("res://world/water/ocean/presets/fresh_breeze.tres"),
	preload("res://world/water/ocean/presets/storm.tres"),
	preload("res://world/water/ocean/presets/breeze_over_swell.tres")]
const STATE_NAMES: Array[String] = ["Calm", "Fresh breeze", "Storm", "Breeze over swell"]
const RULES: OceanRuleSet = preload("res://world/water/ocean/rules/presets/coastal_rules.tres")
## Water types the L key cycles through on the sea and the pond.
const WATER_TYPES: Array[OceanLook] = [
	preload("res://world/water/ocean/looks/clear_ocean.tres"),
	preload("res://world/water/ocean/looks/coastal.tres"),
	preload("res://world/water/ocean/looks/murky.tres")]
const WATER_TYPE_NAMES: Array[String] = ["Clear ocean", "Coastal", "Murky"]
const POND_LOOK: OceanLook = preload("res://world/water/ocean/looks/coastal.tres")
## Seabed baked for the ocean's shore damping and swash: area around the island and texels per side.
const SEABED_SIZE := 1200.0
const SEABED_RESOLUTION := 768
## Web build: a coarser seabed, because baking it in GDScript is several times slower there.
const WEB_SEABED_RESOLUTION := 384
## The pond's water square reaches this far past its waterline, under the banks, up to the river.
const POND_MARGIN := 2.0
const POND_SUBDIVISIONS := 160
## A pond on a calm day: small, short waves and fine ripples.
const POND_WAVE_AMPLITUDE := 0.03
const POND_WAVE_LENGTH := 3.0
const POND_STEEPNESS := 0.3
const POND_DETAIL := 0.2
const POND_REFLECTION_SCALE := 0.5
## Width of the tuner panel; it runs down to the bottom of the screen.
const CONTROLS_VIEW_SIZE := Vector2(560, 0)
const TREE_COUNT := 160
const TREE_HEIGHT := Vector2(5.0, 10.0)
## Trees grow on grass only: this far above the sand, and clear of the pond and the river.
const TREE_ABOVE_BEACH := 0.6
const TREE_WATER_CLEARANCE := 6.0
const BARK_COLOR := Color(0.25, 0.17, 0.1)
const LEAF_COLOR := Color(0.1, 0.26, 0.08)
## Boats for scale, as (direction from the island centre in degrees, metres off the coast): off the
## south beach, off the river mouth, and out in deep water past the drop-off.
const BOATS: Array[Vector2] = [Vector2(-95.0, 60.0), Vector2(8.0, 55.0), Vector2(-120.0, 520.0)]
const BOAT_HEADINGS: Array[float] = [1.2, 0.3, 2.0]
## Barrels just off the south beach: directions (degrees) and their distance off the coast.
const BARREL_DIRECTIONS: Array[float] = [-93.0, -91.5, -90.0, -88.5]
const BARREL_OFFSHORE := 12.0
const DROP_HEIGHT := 0.6
const BARREL_RADIUS := 0.45
const BARREL_HEIGHT := 1.1
const BARREL_MASS := 50.0

var terrain := IslandTerrain.new()
var ocean: Ocean
var pond: Sea
var river: IslandRiver
var notes := ""
var _state := 1
## Editable copy of the active preset; the sliders write into it.
var _live: OceanSpectrum
var _panel: OceanTunerPanel
## -1: the ocean's own look; otherwise an index into WATER_TYPES.
var _water_type := -1


func _ready() -> void:
	add_child(IslandGround.build_mesh(terrain))
	add_child(IslandGround.build_collision(terrain))
	ocean = Ocean.new()
	_live = STATES[_state].duplicate() as OceanSpectrum
	ocean.spectrum = _live
	ocean.rules = RULES
	ocean.foreshore_slope = terrain.beach.beach_slope
	add_child(ocean)
	var half := SEABED_SIZE / 2.0
	var seabed_resolution := WEB_SEABED_RESOLUTION if OS.has_feature("web") else SEABED_RESOLUTION
	ocean.set_seabed(terrain.height, Rect2(-half, -half, SEABED_SIZE, SEABED_SIZE), seabed_resolution)
	_make_pond()
	river = IslandRiver.new(terrain)
	add_child(river)
	_plant_trees()
	for i in range(BOATS.size()):
		var boat := ScaleBoat.new(ocean.height_at)
		boat.position = off_coast(BOATS[i].x, BOATS[i].y)
		boat.rotation.y = BOAT_HEADINGS[i]
		add_child(boat)
	for direction: float in BARREL_DIRECTIONS:
		_add_barrel(off_coast(direction, BARREL_OFFSHORE))
	_update_notes()


## A point on the sea `offshore` metres off the coast, in the direction `degrees` from the centre,
## just above sea level.
func off_coast(degrees: float, offshore: float) -> Vector3:
	var angle := deg_to_rad(degrees)
	var r := terrain.coast_radius(angle) + offshore
	return Vector3(cos(angle) * r, IslandTerrain.SEA_LEVEL + DROP_HEIGHT, sin(angle) * r)


## Height of whichever water lies at `xz`: the pond, the river, or the sea.
func water_height_at(xz: Vector2) -> float:
	if terrain.is_in_pond(xz):
		return pond.surface_height_at(xz)
	if terrain.is_in_river(xz):
		return river.height_at(xz)
	return ocean.height_at(xz)


## Current of the water at `xz` (only the river flows).
func water_velocity_at(xz: Vector2) -> Vector3:
	if terrain.is_in_river(xz):
		return river.velocity_at(xz)
	return Vector3.ZERO


func cycle_sea_state() -> void:
	set_sea_state(_state + 1)


## Index into STATES of the sea state now.
func sea_state() -> int:
	return _state


## Curling breakers on or off (curl strength 1 or 0), to compare with spilling ones. Returns whether on.
func toggle_curls() -> bool:
	var on := ocean.parameter_value(&"curl_strength") <= 0.0
	ocean.set_parameter(&"curl_strength", 1.0 if on else 0.0)
	_update_notes()
	return on


func set_sea_state(index: int) -> void:
	_state = posmod(index, STATES.size())
	_live = STATES[_state].duplicate() as OceanSpectrum
	ocean.set_spectrum(_live)
	if _panel:
		_panel.mark_defaults()
	_update_notes()


## Next water type for the sea and the pond; returns its name.
func cycle_water_type() -> String:
	_water_type = (_water_type + 1) % WATER_TYPES.size()
	ocean.set_look(WATER_TYPES[_water_type].duplicate() as OceanLook)
	pond.set_look(WATER_TYPES[_water_type])
	if _panel:
		_panel.mark_defaults()
	_update_notes()
	return WATER_TYPE_NAMES[_water_type]


## The ocean tuner and rule editor, as tabs.
func make_controls() -> Control:
	var tabs := TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	_panel = OceanTunerPanel.new(ocean)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Big seas are long seas: start with horizontal size following vertical size.
	_panel.set_link(OceanTunerLinks.Link.STEEPNESS, true)
	var sea := ScrollContainer.new()
	sea.name = "Sea"
	sea.custom_minimum_size = CONTROLS_VIEW_SIZE
	sea.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sea.add_child(_panel)
	tabs.add_child(sea)
	var scroll := ScrollContainer.new()
	scroll.name = "Rules"
	scroll.custom_minimum_size = CONTROLS_VIEW_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var editor := OceanRuleEditor.new(RULES, ocean.rule_parameters(), ocean.rule_targets())
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.rules_changed.connect(func(rule_set: OceanRuleSet) -> void:
		ocean.set_rules(rule_set)
		editor.show_problems(ocean.rule_problems()))
	editor.show_problems(ocean.rule_problems())
	scroll.add_child(editor)
	tabs.add_child(scroll)
	return tabs


func _make_pond() -> void:
	pond = Sea.new()
	pond.size = (IslandTerrain.POND_RADIUS + POND_MARGIN) * 2.0
	pond.subdivisions = POND_SUBDIVISIONS
	pond.level = IslandTerrain.POND_LEVEL
	pond.reflection_slot = 1
	pond.reflection_resolution_scale = POND_REFLECTION_SCALE
	pond.look = POND_LOOK
	pond.position = Vector3(IslandTerrain.POND_CENTRE.x, 0.0, IslandTerrain.POND_CENTRE.y)
	add_child(pond)
	pond.material.set_shader_parameter("wave_amplitude", POND_WAVE_AMPLITUDE)
	pond.material.set_shader_parameter("wave_length", POND_WAVE_LENGTH)
	pond.material.set_shader_parameter("wave_steepness", POND_STEEPNESS)
	pond.material.set_shader_parameter("detail_strength", POND_DETAIL)


## Simple trees on the grass, so the pond and the sea have something to mirror.
func _plant_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var bark := StandardMaterial3D.new()
	bark.albedo_color = BARK_COLOR
	bark.roughness = 0.95
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = LEAF_COLOR
	leaves.roughness = 0.85
	var planted := 0
	var attempts := 0
	while planted < TREE_COUNT and attempts < TREE_COUNT * 20:
		attempts += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * IslandTerrain.COAST_RADIUS
		var ground := terrain.height(p.x, p.y)
		if ground < IslandTerrain.BEACH_TOP + TREE_ABOVE_BEACH or _near_fresh_water(p):
			continue
		var tall := rng.randf_range(TREE_HEIGHT.x, TREE_HEIGHT.y)
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.12
		trunk.bottom_radius = 0.22
		trunk.height = tall * 0.45
		trunk.material = bark
		_add_mesh(trunk, Vector3(p.x, ground + tall * 0.225, p.y))
		var crown := CylinderMesh.new()
		crown.top_radius = 0.0
		crown.bottom_radius = tall * 0.24
		crown.height = tall * 0.75
		crown.material = leaves
		_add_mesh(crown, Vector3(p.x, ground + tall * 0.62, p.y))
		planted += 1


func _near_fresh_water(p: Vector2) -> bool:
	if p.distance_to(IslandTerrain.POND_CENTRE) < IslandTerrain.POND_RADIUS + TREE_WATER_CLEARANCE:
		return true
	return p.x > IslandTerrain.RIVER_START_X - TREE_WATER_CLEARANCE \
			and absf(p.y - terrain.river_centre(p.x)) < IslandTerrain.RIVER_BANK_DISTANCE + TREE_WATER_CLEARANCE


func _add_mesh(mesh: Mesh, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)


func _add_barrel(at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = BARREL_MASS
	body.position = at
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = BARREL_RADIUS
	cylinder.bottom_radius = BARREL_RADIUS
	cylinder.height = BARREL_HEIGHT
	cylinder.material = WaterProp.material(Color(0.28, 0.13, 0.055), 0.8)
	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = BARREL_RADIUS
	shape.height = BARREL_HEIGHT
	collision.shape = shape
	body.add_child(collision)
	var buoyancy := Buoyancy.new()
	buoyancy.body = body
	buoyancy.water_height = ocean.height_at
	body.add_child(buoyancy)
	var wake := RippleEmitter.new()
	wake.body = body
	wake.water_height = ocean.height_at
	wake.radius = BARREL_RADIUS
	body.add_child(wake)
	add_child(body)


func _update_notes() -> void:
	var mode: String = "FFT" if OceanSimulation.is_supported() else "Gerstner fallback"
	var look := WATER_TYPE_NAMES[_water_type] if _water_type >= 0 else "default water"
	var curls := "curls on" if ocean == null or ocean.parameter_value(&"curl_strength") > 0.0 else "curls off"
	notes = "%s | %s, %s, %s | C: next sea state | L: water type | K: curls" % [mode, STATE_NAMES[_state], look, curls]
