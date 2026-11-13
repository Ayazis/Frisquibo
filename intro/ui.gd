extends CanvasLayer
## Medieval-styled HUD: objective scroll, interaction prompt, dialogue box, fades and title card.

var root: Control
var objective: Label
var objective_panel: PanelContainer
var prompt: Label
var dialog_panel: PanelContainer
var dialog_name: Label
var dialog_text: Label
var fade: ColorRect
var title: Label
var subtitle: Label
var footer: Label
var help: Label


func _parchment(alpha := 0.92) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.77, 0.58, alpha)
	sb.border_color = Color(0.32, 0.2, 0.09)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	return sb


func _label(text: String, size: int, col: Color, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02))
	return l


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 20
	root = Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	objective_panel = PanelContainer.new()
	objective_panel.add_theme_stylebox_override("panel", _parchment())
	objective_panel.position = Vector2(24, 24)
	var ov := VBoxContainer.new()
	ov.add_child(_label("Quest", 15, Color(0.45, 0.1, 0.06)))
	objective = _label("", 22, Color(0.18, 0.1, 0.04))
	ov.add_child(objective)
	objective_panel.add_child(ov)
	objective_panel.modulate.a = 0.0
	root.add_child(objective_panel)

	prompt = _label("", 26, Color(1.0, 0.92, 0.7), 8)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.offset_top = -170
	prompt.offset_bottom = -130
	root.add_child(prompt)

	dialog_panel = PanelContainer.new()
	dialog_panel.add_theme_stylebox_override("panel", _parchment(0.96))
	dialog_panel.anchor_left = 0.18
	dialog_panel.anchor_right = 0.82
	dialog_panel.anchor_top = 1.0
	dialog_panel.anchor_bottom = 1.0
	dialog_panel.offset_top = -210
	dialog_panel.offset_bottom = -40
	var dv := VBoxContainer.new()
	dialog_name = _label("", 22, Color(0.5, 0.08, 0.05))
	dialog_text = _label("", 24, Color(0.15, 0.09, 0.03))
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont := _label("[E] continue", 15, Color(0.4, 0.28, 0.14))
	cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dv.add_child(dialog_name)
	dv.add_child(dialog_text)
	dv.add_child(cont)
	dialog_panel.add_child(dv)
	dialog_panel.visible = false
	root.add_child(dialog_panel)

	help = _label("WASD move   Shift sprint   Space jump   Mouse look   Click/F swing   E interact   Esc free mouse", 15, Color(1, 0.95, 0.85, 0.75), 4)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 20
	help.offset_top = -34
	root.add_child(help)

	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

	var tb := VBoxContainer.new()
	tb.set_anchors_preset(Control.PRESET_FULL_RECT)
	tb.alignment = BoxContainer.ALIGNMENT_CENTER
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = _label("FRISQUIBO", 110, Color(0.98, 0.8, 0.38), 14)
	subtitle = _label("", 30, Color(0.95, 0.9, 0.8), 8)
	footer = _label("", 18, Color(0.9, 0.85, 0.75, 0.8), 5)
	for l in [title, subtitle, footer]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.add_child(l)
	tb.modulate.a = 0.0
	tb.name = "TitleCard"
	root.add_child(tb)


func set_objective(text: String) -> void:
	objective.text = text
	var tw := create_tween()
	tw.tween_property(objective_panel, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(objective_panel, "scale", Vector2(1.06, 1.06), 0.15)
	tw.tween_property(objective_panel, "scale", Vector2.ONE, 0.2)


func show_prompt(text: String) -> void:
	prompt.text = text


func show_dialog(who: String, text: String) -> void:
	dialog_name.text = who
	dialog_text.text = text
	dialog_text.visible_ratio = 0.0
	dialog_panel.visible = true
	create_tween().tween_property(dialog_text, "visible_ratio", 1.0, text.length() * 0.018)


func hide_dialog() -> void:
	dialog_panel.visible = false


func fade_to(alpha: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, dur)
	return tw


func title_card(sub: String, foot: String, show: bool, dur := 1.5) -> Tween:
	subtitle.text = sub
	footer.text = foot
	var tw := create_tween()
	tw.tween_property(root.get_node("TitleCard"), "modulate:a", 1.0 if show else 0.0, dur)
	return tw


func hide_hud() -> void:
	objective_panel.modulate.a = 0.0
	help.visible = false
	prompt.text = ""
