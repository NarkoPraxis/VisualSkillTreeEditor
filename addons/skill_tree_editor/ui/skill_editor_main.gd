## Main-screen canvas for the Skill Tree Editor.
##
## Provides a zoomable, pannable graph where each skill is a draggable node card.
## Dependency arrows connect parent→child.  Two interaction modes (Create,
## Delete) control what actions are available.  Left-click draws green (unlock)
## arrows; right-click draws gold (maxed) arrows.  Clicking an existing arrow
## with the opposite button toggles its type.
##
## Canvas architecture:
##   _canvas_clip (Panel, dark-blue background, clip_contents=true)
##     _arrow_layer  (CanvasDrawLayer, z=0, added first) ← grid + arrows
##     PanelContainer cards (z=0, added after arrow_layer) ← draw on top by creation order
##     _overlay_layer (CanvasDrawLayer, z=1) ← handles + delete buttons
##
## NOTE: z_index=-1 on a CanvasItem child causes Godot to skip its _draw() call
## (visible rect is zero). Always use z>=0 and rely on sibling creation order.
##
## Draw layers are sized explicitly via _canvas_clip.resized signal.
## Cards are positioned in screen space using _w2s(world_pos).
@tool
extends Control

const CanvasDrawLayer = preload("res://addons/skill_tree_editor/ui/canvas_draw_layer.gd")
const _ICONS := "res://addons/skill_tree_editor/icons/"

# ── Constants ────────────────────────────────────────────────────────────

const NODE_W := 180.0
const NODE_H := 82.0
const HANDLE_RADIUS := 10.0
const DELETE_BTN_R := 9.0
const ARROW_HIT_DIST := 12.0
const ZOOM_MIN := 0.12
const ZOOM_MAX := 4.0
const ZOOM_STEP := 0.1

const GRP_BG := {
	"-e": Color(0.27, 0.24, 0.14),
	"-c": Color(0.27, 0.15, 0.15),
	"-p": Color(0.14, 0.27, 0.17),
	"-r": Color(0.13, 0.20, 0.35),
	"-d": Color(0.22, 0.15, 0.30),
	"-x": Color(0.19, 0.21, 0.26),
}
const GRP_BORDER := {
	"-e": Color(0.92, 0.78, 0.32, 0.70),
	"-c": Color(0.92, 0.42, 0.42, 0.70),
	"-p": Color(0.38, 0.82, 0.48, 0.70),
	"-r": Color(0.40, 0.60, 0.92, 0.70),
	"-d": Color(0.72, 0.48, 0.92, 0.70),
	"-x": Color(0.62, 0.62, 0.62, 0.70),
}
const DEFAULT_BG       := Color(0.21, 0.21, 0.25)
const DEFAULT_BORDER   := Color(0.48, 0.48, 0.48, 0.70)
const SEL_BORDER       := Color(0.40, 0.75, 1.00, 1.00)
const PURCHASED_BORDER := Color(1.00, 1.00, 1.00, 0.90)
const MAXED_BORDER     := Color(1.00, 0.80, 0.15, 1.00)
const RANKUP_BORDER    := Color(1.00, 0.20, 0.20, 1.00)
const RANKUP_ARROW     := Color(1.00, 0.25, 0.25)
const RANKUP_ARROW_SEL := Color(1.00, 0.50, 0.50)

# ── State ────────────────────────────────────────────────────────────────

var _ctx: RefCounted  # SkillEditorContext
var _cam_off := Vector2(20, 50)
var _cam_zoom := 1.0

# UI refs
var _canvas_clip: Panel
var _arrow_layer: Control
var _overlay_layer: Control
var _mode_toggle: Button
var _title_lbl: Label
var _file_dlg: EditorFileDialog
var _file_dlg_mode: String = ""
var _empty_lbl: Label
var _drag_hover: bool = false

## id → { panel, style, name_lbl, cost_lbl, max_lbl, emote_lbl }
var _cards: Dictionary = {}

var _bold_font: Font = null  # set in _ready() from editor theme

# Interaction
var _panning := false
var _pan_start_mouse := Vector2.ZERO
var _pan_start_off := Vector2.ZERO
var _drag_id := ""
var _drag_off := Vector2.ZERO
var _conn_from := ""
var _conn_end := Vector2.ZERO
var _conn_is_rankup := false


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(ctx: RefCounted) -> void:
	_ctx = ctx


func _ready() -> void:
	# The editor's main-screen parent is a VBoxContainer — use size flags so it
	# gives this panel all remaining vertical space.  Anchors are ignored there.
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	set_anchors_preset(PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(root)

	if Engine.is_editor_hint():
		_bold_font = get_theme_font("bold", "EditorFonts")

	_build_toolbar(root)
	_build_canvas(root)
	_wire()
	call_deferred("_auto_load_game_tree")

	if _ctx.nodes.is_empty():
		_show_empty()

	# Layout hasn't run yet when _ready fires; defer so canvas has its real size.
	call_deferred("_sync_layer_sizes")
	call_deferred("_on_data")


# ── Toolbar ──────────────────────────────────────────────────────────────

func _build_toolbar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	parent.add_child(bar)

	bar.add_child(_tb_file(_ICONS + "icon_save.svg", "Save", _on_save))
	bar.add_child(_tb_file(_ICONS + "icon_save_as.svg", "Save As\u2026", _on_save_as))
	bar.add_child(_tb_file(_ICONS + "icon_open.svg", "Open\u2026", _on_open))
	bar.add_child(_tb_icon_text(_ICONS + "icon_load_game.svg", "Load Game\u2019s Config", _on_load_game_tree))

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_title_lbl = Label.new()
	_title_lbl.text = "(unsaved)"
	_title_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	bar.add_child(_title_lbl)


func _tb(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _tb_file(icon_path: String, tooltip: String, cb: Callable) -> Button:
	var b := Button.new()
	var icon := load(icon_path) as Texture2D
	if icon:
		b.icon = icon
	else:
		b.text = tooltip
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(32, 32)
	b.pressed.connect(cb)
	return b


func _tb_icon_text(icon_path: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	var icon := load(icon_path) as Texture2D
	if icon:
		b.icon = icon
	b.text = text
	b.pressed.connect(cb)
	return b


func _tb_icon(icon_name: String, tooltip: String, cb: Callable) -> Button:
	var b := Button.new()
	if Engine.is_editor_hint():
		var icon := EditorInterface.get_base_control().get_theme_icon(icon_name, "EditorIcons")
		if icon:
			b.icon = icon
		else:
			b.text = tooltip
	else:
		b.text = tooltip
	b.tooltip_text = tooltip
	b.pressed.connect(cb)
	return b


# ── Canvas ───────────────────────────────────────────────────────────────

func _build_canvas(parent: VBoxContainer) -> void:
	_canvas_clip = Panel.new()
	_canvas_clip.clip_contents = true
	_canvas_clip.size_flags_vertical = SIZE_EXPAND_FILL
	_canvas_clip.size_flags_horizontal = SIZE_EXPAND_FILL
	_canvas_clip.custom_minimum_size = Vector2(120, 120)
	_canvas_clip.mouse_filter = MOUSE_FILTER_STOP
	_canvas_clip.gui_input.connect(_on_input)

	# Dark blue "blueprint" background
	var bg_sty := StyleBoxFlat.new()
	bg_sty.bg_color = Color(0.06, 0.09, 0.16)
	_canvas_clip.add_theme_stylebox_override("panel", bg_sty)

	parent.add_child(_canvas_clip)

	# Arrow/grid layer sits behind all cards
	_arrow_layer = CanvasDrawLayer.new()
	_arrow_layer.draw_target = self
	_arrow_layer.layer_id = "arrows"
	_arrow_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_arrow_layer.z_index = 0  # creation order puts it behind cards (also z=0) added later
	_canvas_clip.add_child(_arrow_layer)

	# Overlay layer sits on top of all cards
	_overlay_layer = CanvasDrawLayer.new()
	_overlay_layer.draw_target = self
	_overlay_layer.layer_id = "overlay"
	_overlay_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay_layer.z_index = 1  # above all cards (z=0)
	_canvas_clip.add_child(_overlay_layer)

	# Resize draw layers to match canvas whenever canvas is laid out
	_canvas_clip.resized.connect(_sync_layer_sizes)

	_build_mode_toggle()


func _build_mode_toggle() -> void:
	_mode_toggle = Button.new()
	_mode_toggle.flat = true
	_mode_toggle.mouse_filter = MOUSE_FILTER_STOP
	_mode_toggle.z_index = 2
	_mode_toggle.custom_minimum_size = Vector2(64, 64)
	_mode_toggle.expand_icon = true
	_mode_toggle.pressed.connect(_toggle_mode)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.20, 0.85)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_mode_toggle.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	_mode_toggle.add_theme_stylebox_override("hover", hover_style)

	_canvas_clip.add_child(_mode_toggle)
	_mode_toggle.set_anchors_preset(PRESET_TOP_RIGHT)
	_mode_toggle.offset_left = -76
	_mode_toggle.offset_top = 8
	_mode_toggle.offset_right = -12
	_mode_toggle.offset_bottom = 72

	_update_mode_toggle_icon()


# ── Coordinate math ──────────────────────────────────────────────────────

func _w2s(wp: Vector2) -> Vector2:
	return wp * _cam_zoom + _cam_off

func _s2w(sp: Vector2) -> Vector2:
	return (sp - _cam_off) / _cam_zoom

func _visible_world_rect() -> Rect2:
	var sz := _canvas_clip.size if _canvas_clip else Vector2(800, 600)
	var tl := _s2w(Vector2.ZERO)
	var br := _s2w(sz)
	return Rect2(tl, br - tl)

func _node_center(id: String) -> Vector2:
	var pos: Vector2 = _ctx.nodes[id]["position"]
	return Vector2(pos.x + NODE_W * 0.5, pos.y + _node_h(id) * 0.5)

func _node_edge_point(id: String, other_center: Vector2) -> Vector2:
	var center: Vector2 = _node_center(id)
	var d: Vector2 = other_center - center
	if d.length_squared() < 0.001:
		return center
	var dir: Vector2 = d.normalized()
	var half_w: float = NODE_W * 0.5
	var half_h: float = _node_h(id) * 0.5
	var t: float = INF
	if dir.x > 0.0001:
		t = minf(t, half_w / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, -half_w / dir.x)
	if dir.y > 0.0001:
		t = minf(t, half_h / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, -half_h / dir.y)
	if t == INF:
		return center
	return center + dir * t

func _sync_layer_sizes() -> void:
	var sz := _canvas_clip.size
	_arrow_layer.position = Vector2.ZERO
	_arrow_layer.size = sz
	_overlay_layer.position = Vector2.ZERO
	_overlay_layer.size = sz
	_redraw_arrows()
	_redraw_overlay()

func _apply_transform() -> void:
	_update_all_card_transforms()
	_redraw_arrows()
	_redraw_overlay()

func _update_all_card_transforms() -> void:
	for id in _cards:
		var c: Dictionary = _cards[id]
		var panel: PanelContainer = c["panel"]
		if is_instance_valid(panel) and _ctx.nodes.has(id):
			panel.position = _w2s(_ctx.nodes[id]["position"])
			panel.scale = Vector2(_cam_zoom, _cam_zoom)

func _zoom_at(sp: Vector2, delta: float) -> void:
	var old := _cam_zoom
	_cam_zoom = clampf(_cam_zoom + delta, ZOOM_MIN, ZOOM_MAX)
	var r := _cam_zoom / old
	_cam_off = sp - (sp - _cam_off) * r
	_update_all_card_transforms()
	_redraw_arrows()
	_redraw_overlay()


# ── Signals ──────────────────────────────────────────────────────────────

func _wire() -> void:
	if not _ctx:
		return
	_ctx.data_changed.connect(_on_data)
	_ctx.mode_changed.connect(func(_m):
		_redraw_overlay()
		_update_mode_toggle_icon()
	)
	_ctx.connection_rejected.connect(_shake_card)
	_canvas_clip.set_drag_forwarding(Callable(), can_drop_data, drop_data)
	_canvas_clip.mouse_exited.connect(func():
		if _drag_hover:
			_drag_hover = false
			_redraw_overlay())


func _on_data() -> void:
	_rebuild_cards()
	_redraw_arrows()
	_redraw_overlay()
	_update_title()


# ── Card management ──────────────────────────────────────────────────────

func _rebuild_cards() -> void:
	# Remove stale
	var stale: Array[String] = []
	for id in _cards:
		if not _ctx.nodes.has(id):
			stale.append(id)
	for id in stale:
		if is_instance_valid(_cards[id]["panel"]):
			_cards[id]["panel"].queue_free()
		_cards.erase(id)

	# Add / update
	for id in _ctx.nodes:
		if _cards.has(id):
			_refresh_card(id)
		else:
			_create_card(id)
			_refresh_card(id)

	if _empty_lbl and _ctx.nodes.size() > 0:
		_empty_lbl.queue_free()
		_empty_lbl = null


func _create_card(id: String) -> void:
	var d: Dictionary = _ctx.nodes[id]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
	panel.size = panel.custom_minimum_size
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.position = _w2s(d["position"])
	panel.scale = Vector2(_cam_zoom, _cam_zoom)

	var grp: String = d.get("group", "")
	var sty := StyleBoxFlat.new()
	sty.set_corner_radius_all(8)
	sty.bg_color = GRP_BG.get(grp, DEFAULT_BG)
	sty.border_color = GRP_BORDER.get(grp, DEFAULT_BORDER)
	sty.set_border_width_all(2)
	sty.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sty)

	# Main layout: HBox with optional icon column on the left
	var main_hb := HBoxContainer.new()
	main_hb.mouse_filter = MOUSE_FILTER_IGNORE
	main_hb.add_theme_constant_override("separation", 6)
	panel.add_child(main_hb)

	# Icon column (left of name + cost) — square, scaled to fit node height
	var icon_size: float = NODE_H - 16.0  # subtract content margins (8px each side)
	var icon_tex := TextureRect.new()
	icon_tex.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.mouse_filter = MOUSE_FILTER_IGNORE
	icon_tex.size_flags_vertical = SIZE_SHRINK_CENTER
	icon_tex.visible = false
	main_hb.add_child(icon_tex)

	var emote := Label.new()
	emote.text = d.get("emoticon", "")
	emote.visible = false
	emote.mouse_filter = MOUSE_FILTER_IGNORE
	emote.add_theme_font_size_override("font_size", 44)
	emote.size_flags_vertical = SIZE_SHRINK_CENTER
	main_hb.add_child(emote)

	_apply_icon(d.get("emoticon", ""), emote, icon_tex)

	# Right column: name + cost rows
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = SIZE_EXPAND_FILL
	main_hb.add_child(vb)

	# Row 1: name + badge
	var top := HBoxContainer.new()
	top.mouse_filter = MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 4)
	vb.add_child(top)

	var nlbl := Label.new()
	nlbl.text = d["name"]
	nlbl.add_theme_font_size_override("font_size", 15)
	nlbl.mouse_filter = MOUSE_FILTER_IGNORE
	nlbl.clip_text = true
	nlbl.size_flags_horizontal = SIZE_EXPAND_FILL
	if _bold_font:
		nlbl.add_theme_font_override("font", _bold_font)
	top.add_child(nlbl)

	# Secondary Unlock badge (top-right, inline with title — first 3 chars)
	var sec: String = d.get("secondary_unlock", "")
	var badge_text: String = sec.left(3) if (sec != "" and sec != "NONE") else ""
	var badge_sty := StyleBoxFlat.new()
	badge_sty.set_corner_radius_all(3)
	badge_sty.bg_color = Color(0, 0, 0, 0)
	badge_sty.border_color = sty.border_color
	badge_sty.set_border_width_all(1)
	badge_sty.set_content_margin_all(1)
	var badge_panel := PanelContainer.new()
	badge_panel.mouse_filter = MOUSE_FILTER_IGNORE
	badge_panel.visible = badge_text != ""
	badge_panel.add_theme_stylebox_override("panel", badge_sty)
	var badge_lbl := Label.new()
	badge_lbl.text = badge_text
	badge_lbl.add_theme_font_size_override("font_size", 16)
	badge_lbl.add_theme_color_override("font_color", sty.border_color)
	badge_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	if _bold_font:
		badge_lbl.add_theme_font_override("font", _bold_font)
	badge_panel.add_child(badge_lbl)
	top.add_child(badge_panel)

	# Row 2: cost + purchase spinner
	var stats := HBoxContainer.new()
	stats.mouse_filter = MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 6)
	vb.add_child(stats)

	var clbl := Label.new()
	clbl.text = _cost_text(d)
	clbl.add_theme_font_size_override("font_size", 11)
	clbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.35))
	clbl.mouse_filter = MOUSE_FILTER_IGNORE
	clbl.size_flags_horizontal = SIZE_EXPAND_FILL
	stats.add_child(clbl)

	var purchased: int = d.get("purchased", 0)
	var max_val: int   = d.get("max", 1)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = max_val
	spin.value = purchased
	spin.step = 1
	spin.suffix = "/ %d" % max_val
	spin.custom_minimum_size = Vector2(86, 0)
	spin.add_theme_font_size_override("font_size", 11)
	spin.add_theme_constant_override("buttons_width", 16)
	spin.add_theme_constant_override("field_and_buttons_separator", 2)
	spin.add_theme_constant_override("buttons_vertical_separation", 0)
	spin.value_changed.connect(_on_purchase_spinbox_changed.bind(id))
	stats.add_child(spin)
	_canvas_clip.add_child(panel)
	# SpinBox font/size overrides don't cascade to its internal LineEdit — set directly.
	var le := spin.get_line_edit()
	le.add_theme_font_size_override("font_size", 11)
	le.add_theme_constant_override("minimum_character_width", 1)
	_cards[id] = {
		"panel": panel, "style": sty,
		"name_lbl": nlbl, "cost_lbl": clbl, "emote_lbl": emote, "icon_tex": icon_tex,
		"count_spin": spin,
		"badge_panel": badge_panel, "badge_lbl": badge_lbl, "badge_sty": badge_sty,
	}


func _refresh_card(id: String) -> void:
	if not _cards.has(id) or not _ctx.nodes.has(id):
		return
	var d: Dictionary = _ctx.nodes[id]
	var c: Dictionary = _cards[id]
	var panel: PanelContainer = c["panel"]
	if not is_instance_valid(panel):
		_cards.erase(id)
		return
	panel.position = _w2s(d["position"])
	c["name_lbl"].text = d["name"]
	c["cost_lbl"].text = _cost_text(d)
	var em: String = d.get("emoticon", "")
	_apply_icon(em, c["emote_lbl"], c["icon_tex"])
	var sec: String = d.get("secondary_unlock", "")
	var badge_text: String = sec.left(3) if (sec != "" and sec != "NONE") else ""
	if c.has("badge_lbl") and is_instance_valid(c["badge_lbl"]):
		c["badge_lbl"].text = badge_text
		c["badge_panel"].visible = badge_text != ""
	var purchased: int = d.get("purchased", 0)
	var max_val: int   = d.get("max", 1)
	if c.has("count_spin") and is_instance_valid(c["count_spin"]):
		var spin: SpinBox = c["count_spin"]
		spin.set_block_signals(true)
		spin.max_value = max_val
		spin.value = purchased
		spin.suffix = "/ %d" % max_val
		spin.set_block_signals(false)
	var grp: String = d.get("group", "")
	var sty: StyleBoxFlat = c["style"]
	# Always sync background so group changes take effect immediately
	sty.bg_color = GRP_BG.get(grp, DEFAULT_BG)
	var border_col: Color
	if id == _ctx.selected_skill_id:
		border_col = SEL_BORDER
		sty.set_border_width_all(3)
	elif _ctx.is_rank_up_child(id) and purchased >= max_val and max_val > 0:
		border_col = RANKUP_BORDER
		sty.set_border_width_all(3)
	elif purchased >= max_val and max_val > 0:
		border_col = MAXED_BORDER
		sty.set_border_width_all(3)
	elif purchased >= 1:
		border_col = PURCHASED_BORDER
		sty.set_border_width_all(2)
	else:
		border_col = GRP_BORDER.get(grp, DEFAULT_BORDER)
		sty.set_border_width_all(2)
	sty.border_color = border_col
	if c.has("badge_sty") and is_instance_valid(c["badge_sty"]):
		c["badge_sty"].border_color = border_col
		c["badge_lbl"].add_theme_color_override("font_color", border_col)


const _IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "svg"]

func _is_image_path(text: String) -> bool:
	var ext := text.get_extension().to_lower()
	return ext in _IMAGE_EXTENSIONS


func _apply_icon(icon_value: String, emote_lbl: Label, icon_tex: TextureRect) -> void:
	## Sets either the emoji label or the texture rect visible, depending on
	## whether icon_value is an image file path or an emoji/symbol string.
	if icon_value == "":
		emote_lbl.visible = false
		icon_tex.visible = false
		return
	if _is_image_path(icon_value):
		emote_lbl.visible = false
		var tex: Texture2D = null
		if icon_value.begins_with("res://") and ResourceLoader.exists(icon_value):
			tex = load(icon_value)
		elif FileAccess.file_exists(icon_value):
			var img := Image.new()
			if img.load(icon_value) == OK:
				tex = ImageTexture.create_from_image(img)
		icon_tex.texture = tex
		icon_tex.visible = tex != null
	else:
		icon_tex.visible = false
		emote_lbl.text = icon_value
		emote_lbl.visible = true


# ── Drawing callback ─────────────────────────────────────────────────────

func _draw_layer(ci: CanvasItem, lid: String) -> void:
	match lid:
		"arrows":  _paint_arrows(ci)
		"overlay": _paint_overlay(ci)


func _paint_arrows(ci: CanvasItem) -> void:
	_paint_grid(ci)

	for i in range(_ctx.connections.size()):
		var conn: Dictionary = _ctx.connections[i]
		var fid: String = conn["from"]
		var tid: String = conn["to"]
		if not _ctx.nodes.has(fid) or not _ctx.nodes.has(tid):
			continue
		var cf: Vector2 = _node_center(fid)
		var ct: Vector2 = _node_center(tid)
		var a: Vector2 = _w2s(_node_edge_point(fid, ct))
		var b: Vector2 = _w2s(_node_edge_point(tid, cf))
		var dir: Vector2 = (ct - cf).normalized()
		var ctrl_len: float = maxf(cf.distance_to(ct) * _cam_zoom * 0.4, 60.0)
		var c1: Vector2 = a + dir * ctrl_len
		var c2: Vector2 = b - dir * ctrl_len

		var conn_type: String = conn["type"]
		var is_sel: bool = (i == _ctx.selected_connection_index)
		var col: Color
		if conn_type == "rank_up":
			col = RANKUP_ARROW_SEL if is_sel else RANKUP_ARROW
		elif conn_type == "purchased":
			col = Color(0.50, 1.00, 0.60) if is_sel else Color(0.30, 0.90, 0.40)
		else:
			col = Color(1.00, 0.95, 0.50) if is_sel else Color(1.00, 0.80, 0.15)
		var w: float = 5.0 if is_sel else 4.0
		_draw_bezier(ci, a, b, col, w, c1, c2)

	# Temp connection preview
	if _conn_from != "" and _ctx.nodes.has(_conn_from):
		var cf: Vector2 = _node_center(_conn_from)
		var mouse_w: Vector2 = _conn_end
		var a: Vector2 = _w2s(_node_edge_point(_conn_from, mouse_w))
		var end_s: Vector2 = _w2s(mouse_w)
		var dir: Vector2 = (mouse_w - cf).normalized()
		var ctrl_len: float = maxf(cf.distance_to(mouse_w) * _cam_zoom * 0.4, 60.0)
		var c1: Vector2 = a + dir * ctrl_len
		var c2: Vector2 = end_s - dir * ctrl_len
		var col: Color
		if _conn_is_rankup:
			col = Color(1.00, 0.25, 0.25, 0.65)
		else:
			var is_p: bool = _ctx.current_arrow_type == _ctx.ArrowType.PURCHASED
			col = Color(0.30, 0.90, 0.40, 0.65) if is_p else Color(1.00, 0.80, 0.15, 0.65)
		_draw_bezier(ci, a, end_s, col, 3.5, c1, c2)


func _draw_bezier(ci: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float, c1: Vector2, c2: Vector2) -> void:
	var pts := PackedVector2Array()
	var steps := 20
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		var it := 1.0 - t
		pts.append(Vector2(
			it*it*it*from.x + 3.0*it*it*t*c1.x + 3.0*it*t*t*c2.x + t*t*t*to.x,
			it*it*it*from.y + 3.0*it*it*t*c1.y + 3.0*it*t*t*c2.y + t*t*t*to.y))
	if pts.size() >= 2:
		var tip: Vector2 = pts[pts.size() - 1]
		var prev: Vector2 = pts[pts.size() - 2]
		var dir: Vector2 = (tip - prev).normalized()
		var sz := 16.0
		if dir.length_squared() >= 0.0001:
			pts[pts.size() - 1] = tip - dir * sz  # stop line at arrowhead base
		ci.draw_polyline(pts, color, width, true)
		# Arrowhead
		if dir.length_squared() >= 0.0001:
			var perp := Vector2(-dir.y, dir.x)
			ci.draw_colored_polygon(
				PackedVector2Array([tip, tip - dir*sz + perp*sz*0.5, tip - dir*sz - perp*sz*0.5]),
				color)


func _paint_grid(ci: CanvasItem) -> void:
	# Use the draw layer's own size (set by _sync_layer_sizes) so this works
	# even if _canvas_clip hasn't been queried yet.
	var sz: Vector2 = (ci as Control).size
	if sz.length_squared() < 1.0:
		sz = _canvas_clip.size
	if sz.length_squared() < 1.0:
		return
	var base := 50.0
	var gs := base
	while gs * _cam_zoom < 15.0:
		gs *= 2.0
	if gs * _cam_zoom < 5.0:
		return
	var gs_s := gs * _cam_zoom  # grid step in screen pixels
	var gc := Color(0.55, 0.70, 1.00, 0.07)  # blue-tinted grid lines for blueprint look
	# fposmod ensures positive offset even when _cam_off is negative
	var off_x := fposmod(_cam_off.x, gs_s)
	var off_y := fposmod(_cam_off.y, gs_s)
	var x := off_x
	while x <= sz.x:
		ci.draw_line(Vector2(x, 0), Vector2(x, sz.y), gc, 1.0)
		x += gs_s
	var y := off_y
	while y <= sz.y:
		ci.draw_line(Vector2(0, y), Vector2(sz.x, y), gc, 1.0)
		y += gs_s


func _paint_overlay(ci: CanvasItem) -> void:
	for id in _ctx.nodes:
		var d: Dictionary = _ctx.nodes[id]
		var p: Vector2 = d["position"]
		var nh: float = _node_h(id)

		# Blue handle dot (bottom-center) — for purchased/maxed arrows
		var hc := _w2s(Vector2(p.x + NODE_W * 0.5, p.y + nh))
		var hr := HANDLE_RADIUS * _cam_zoom
		ci.draw_circle(hc, hr, Color(0.40, 0.62, 1.00, 0.85))
		ci.draw_circle(hc, maxf(hr - 2.0 * _cam_zoom, 1.0), Color(0.28, 0.48, 0.88, 0.50))

		# Red handle dot (left-center) — for rank-up arrows only
		var rc := _w2s(Vector2(p.x + 2.0, p.y + nh * 0.5))
		ci.draw_circle(rc, hr, Color(1.00, 0.30, 0.30, 0.85))
		ci.draw_circle(rc, maxf(hr - 2.0 * _cam_zoom, 1.0), Color(0.85, 0.18, 0.18, 0.50))

		# Delete button (top-right corner, delete mode only)
		if _ctx.current_mode == _ctx.Mode.DELETE:
			var bc := _w2s(Vector2(p.x + NODE_W - 2.0, p.y + 2.0))
			var dr := DELETE_BTN_R * _cam_zoom
			ci.draw_circle(bc, dr, Color(0.88, 0.18, 0.18, 0.92))
			var xs := 4.0 * _cam_zoom
			ci.draw_line(bc + Vector2(-xs, -xs), bc + Vector2(xs, xs), Color.WHITE, 2.0, true)
			ci.draw_line(bc + Vector2(xs, -xs), bc + Vector2(-xs, xs), Color.WHITE, 2.0, true)

	if _drag_hover:
		var sz: Vector2 = _canvas_clip.size
		ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 0.8, 0.3, 0.18), true)
		ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 0.9, 0.3, 0.9), false, 3.0)


func _redraw_arrows() -> void:
	if is_instance_valid(_arrow_layer):
		_arrow_layer.queue_redraw()

func _redraw_overlay() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.queue_redraw()


# ── Drag-and-drop ────────────────────────────────────────────────────────

func can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") == "files"):
		return false
	for f in data.get("files", []):
		if (f as String).ends_with(".json"):
			_drag_hover = true
			_redraw_overlay()
			return true
	return false


func drop_data(_at_position: Vector2, data: Variant) -> void:
	_drag_hover = false
	_redraw_overlay()
	var path: String = ""
	for f in data.get("files", []):
		if (f as String).ends_with(".json"):
			path = f
			break
	if path == "":
		return
	if _ctx.nodes.size() > 0:
		var cd := ConfirmationDialog.new()
		cd.dialog_text = "Replace current tree with:\n%s" % path
		cd.confirmed.connect(func():
			_ctx.load_from_file(path)
			_update_title()
			cd.queue_free())
		cd.visibility_changed.connect(func():
			if not cd.visible:
				cd.queue_free())
		add_child(cd)
		cd.popup_centered()
	else:
		_ctx.load_from_file(path)
		_update_title()


# ── Input handling ───────────────────────────────────────────────────────

func _input(ev: InputEvent) -> void:
	## Intercept Ctrl shortcuts here (before the editor's own Ctrl+S "Save Scene"
	## handler consumes them — _unhandled_key_input fires too late for Ctrl events).
	if not visible:
		return
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var k := ev as InputEventKey
	if not k.ctrl_pressed:
		return
	match k.keycode:
		KEY_S:
			if k.shift_pressed:
				_on_save_as()
			else:
				_on_save()
			get_viewport().set_input_as_handled()
		KEY_O:
			if not k.shift_pressed:
				_on_open()
				get_viewport().set_input_as_handled()


func _unhandled_key_input(ev: InputEvent) -> void:
	## Backtick has no editor conflict so _unhandled_key_input is fine for it.
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_QUOTELEFT:
			_toggle_mode()
			get_viewport().set_input_as_handled()


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		_on_mbtn(ev as InputEventMouseButton)
	elif ev is InputEventMouseMotion:
		_on_mmove(ev as InputEventMouseMotion)


func _on_mbtn(ev: InputEventMouseButton) -> void:
	var sp := ev.position
	var wp := _s2w(sp)

	# ── Middle mouse: pan ──
	if ev.button_index == MOUSE_BUTTON_MIDDLE:
		if ev.pressed:
			_panning = true
			_pan_start_mouse = sp
			_pan_start_off = _cam_off
		else:
			_panning = false
		_canvas_clip.accept_event()
		return

	# ── Scroll: zoom ──
	if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(sp, ZOOM_STEP)
		_canvas_clip.accept_event()
		return
	if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(sp, -ZOOM_STEP)
		_canvas_clip.accept_event()
		return

	# ── Left click ──
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_lpress(sp, wp, ev.double_click)
		else:
			_lrelease(sp, wp)
		_canvas_clip.accept_event()
		return

	# ── Right click ── (gold/maxed arrows + toggle)
	if ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.pressed:
			_rpress(sp, wp)
		else:
			_rrelease(sp, wp)
		_canvas_clip.accept_event()


func _lpress(_sp: Vector2, wp: Vector2, is_double: bool = false) -> void:
	var m: int = _ctx.current_mode

	# ── DELETE mode ──
	if m == _ctx.Mode.DELETE:
		var del_id := _hit_delete_btn(wp)
		if del_id != "":
			_ctx.remove_node(del_id)
			return
		var ci := _hit_connection(wp)
		if ci >= 0:
			_ctx.remove_connection_at(ci)
			return
		_ctx.selected_skill_id = ""
		_ctx.selected_connection_index = -1
		_rebuild_cards()
		return

	# ── CREATE mode ──

	# Red rank-up handle → start rank-up connection drag
	var rid := _hit_rank_handle(wp)
	if rid != "":
		_conn_from = rid
		_conn_end = wp
		_conn_is_rankup = true
		return

	# Blue handle → start green (purchased) connection drag
	var hid := _hit_handle(wp)
	if hid != "":
		_conn_from = hid
		_conn_end = wp
		_conn_is_rankup = false
		_ctx.current_arrow_type = _ctx.ArrowType.PURCHASED
		return

	# Connection → left-click toggles gold→green
	var ci := _hit_connection(wp)
	if ci >= 0:
		var conn: Dictionary = _ctx.connections[ci]
		if conn["type"] == "maxed":
			_ctx.assign_connection_type_at(ci, "purchased")
			_redraw_arrows()
			return
		_ctx.selected_connection_index = ci
		_ctx.selected_skill_id = ""
		_rebuild_cards()
		_redraw_arrows()
		return

	# Node → select + drag
	var nid := _hit_node(wp)
	if nid != "":
		_ctx.selected_skill_id = nid
		_ctx.selected_connection_index = -1
		_rebuild_cards()
		_drag_id = nid
		_drag_off = _ctx.nodes[nid]["position"] - wp
		return

	# Empty space
	_ctx.selected_skill_id = ""
	_ctx.selected_connection_index = -1
	_rebuild_cards()
	_redraw_arrows()

	if is_double:
		var id = _ctx.generate_id()
		_ctx.add_node(id, _blank(wp - Vector2(NODE_W * 0.5, NODE_H * 0.5)))
		_ctx.selected_skill_id = id
		_rebuild_cards()


func _lrelease(_sp: Vector2, wp: Vector2) -> void:
	if _drag_id != "":
		_drag_id = ""

	if _conn_from != "":
		var target := _hit_node(wp)
		if _conn_is_rankup:
			if target != "":
				_shake_card(target)
			elif _has_rank_up_child(_conn_from):
				_shake_card(_conn_from)
			else:
				var id = _ctx.generate_id()
				_ctx.add_node(id, _rank_up_child_template(_conn_from, wp))
				_ctx.add_connection(_conn_from, id, "rank_up")
				_ctx.selected_skill_id = id
		else:
			if target != "" and target != _conn_from:
				_ctx.add_connection(_conn_from, target, _ctx.get_arrow_type_string())
			elif target == "" and _ctx.current_mode == _ctx.Mode.CREATE:
				var id = _ctx.generate_id()
				_ctx.add_node(id, _blank(wp - Vector2(NODE_W * 0.5, 0)))
				_ctx.add_connection(_conn_from, id, _ctx.get_arrow_type_string())
				_ctx.selected_skill_id = id
		_conn_from = ""
		_conn_is_rankup = false
		_redraw_arrows()
		_rebuild_cards()


func _rpress(_sp: Vector2, wp: Vector2) -> void:
	if _ctx.current_mode == _ctx.Mode.DELETE:
		return

	# Blue handle → start gold (maxed) connection drag
	var hid := _hit_handle(wp)
	if hid != "":
		_conn_from = hid
		_conn_end = wp
		_conn_is_rankup = false
		_ctx.current_arrow_type = _ctx.ArrowType.MAXED
		return

	# Connection → right-click toggles green→gold
	var ci := _hit_connection(wp)
	if ci >= 0:
		var conn: Dictionary = _ctx.connections[ci]
		if conn["type"] == "purchased":
			_ctx.assign_connection_type_at(ci, "maxed")
			_redraw_arrows()
		return


func _rrelease(_sp: Vector2, wp: Vector2) -> void:
	if _conn_from != "" and not _conn_is_rankup:
		var target := _hit_node(wp)
		if target != "" and target != _conn_from:
			_ctx.add_connection(_conn_from, target, _ctx.get_arrow_type_string())
		elif target == "" and _ctx.current_mode == _ctx.Mode.CREATE:
			var id = _ctx.generate_id()
			_ctx.add_node(id, _blank(wp - Vector2(NODE_W * 0.5, 0)))
			_ctx.add_connection(_conn_from, id, _ctx.get_arrow_type_string())
			_ctx.selected_skill_id = id
		_conn_from = ""
		_redraw_arrows()
		_rebuild_cards()


func _on_mmove(ev: InputEventMouseMotion) -> void:
	if _panning:
		_cam_off += ev.relative
		_apply_transform()
		return

	var wp := _s2w(ev.position)

	if _drag_id != "":
		_ctx.nodes[_drag_id]["position"] = wp + _drag_off
		if _cards.has(_drag_id) and is_instance_valid(_cards[_drag_id]["panel"]):
			_cards[_drag_id]["panel"].position = _w2s(_ctx.nodes[_drag_id]["position"])
		_redraw_arrows()
		_redraw_overlay()
		return

	if _conn_from != "":
		_conn_end = wp
		_redraw_arrows()


# ── Hit testing (world space) ─────────────────────────────────────────────

func _node_h(id: String) -> float:
	if _cards.has(id) and is_instance_valid(_cards[id]["panel"]):
		var h: float = _cards[id]["panel"].size.y
		if h > 1.0:
			return h  # panel is at scale=1 internally; size.y is already world-space
	return NODE_H

func _hit_node(wp: Vector2) -> String:
	# Iterate in reverse so top-most card wins
	var ids = _ctx.nodes.keys()
	for i in range(ids.size() - 1, -1, -1):
		var id: String = ids[i]
		var r := Rect2(_ctx.nodes[id]["position"], Vector2(NODE_W, _node_h(id)))
		if r.has_point(wp):
			return id
	return ""

func _hit_handle(wp: Vector2) -> String:
	for id in _ctx.nodes:
		var p: Vector2 = _ctx.nodes[id]["position"]
		var hc := Vector2(p.x + NODE_W * 0.5, p.y + _node_h(id))
		if wp.distance_to(hc) <= HANDLE_RADIUS + 5.0:
			return id
	return ""

func _hit_rank_handle(wp: Vector2) -> String:
	for id in _ctx.nodes:
		var p: Vector2 = _ctx.nodes[id]["position"]
		var rc := Vector2(p.x + 2.0, p.y + _node_h(id) * 0.5)
		if wp.distance_to(rc) <= HANDLE_RADIUS + 5.0:
			return id
	return ""

func _hit_delete_btn(wp: Vector2) -> String:
	for id in _ctx.nodes:
		var p: Vector2 = _ctx.nodes[id]["position"]
		var bc := Vector2(p.x + NODE_W - 2.0, p.y + 2.0)
		if wp.distance_to(bc) <= DELETE_BTN_R + 3.0:
			return id
	return ""

func _hit_connection(wp: Vector2) -> int:
	for i in range(_ctx.connections.size()):
		var c: Dictionary = _ctx.connections[i]
		if not _ctx.nodes.has(c["from"]) or not _ctx.nodes.has(c["to"]):
			continue
		var cf: Vector2 = _node_center(c["from"])
		var ct: Vector2 = _node_center(c["to"])
		var a: Vector2 = _node_edge_point(c["from"], ct)
		var b: Vector2 = _node_edge_point(c["to"], cf)
		if _near_seg(wp, a, b, ARROW_HIT_DIST):
			return i
	return -1

func _near_seg(p: Vector2, a: Vector2, b: Vector2, thr: float) -> bool:
	var ab := b - a
	var lsq := ab.length_squared()
	if lsq < 0.001:
		return p.distance_to(a) <= thr
	var t := clampf((p - a).dot(ab) / lsq, 0.0, 1.0)
	return p.distance_to(a + ab * t) <= thr


# ── Toolbar callbacks ────────────────────────────────────────────────────

func _toggle_mode() -> void:
	if _ctx.current_mode == _ctx.Mode.CREATE:
		_ctx.current_mode = _ctx.Mode.DELETE
	else:
		_ctx.current_mode = _ctx.Mode.CREATE


func _update_mode_toggle_icon() -> void:
	if not is_instance_valid(_mode_toggle):
		return
	if _ctx.current_mode == _ctx.Mode.CREATE:
		_mode_toggle.icon = load(_ICONS + "icon_create_mode.svg")
		_mode_toggle.tooltip_text = "Create mode (click to switch to Delete)"
		_mode_toggle.self_modulate = Color.WHITE
	else:
		_mode_toggle.icon = load(_ICONS + "icon_delete_mode.svg")
		_mode_toggle.tooltip_text = "Delete mode (click to switch to Create)"
		_mode_toggle.self_modulate = Color(0.95, 0.35, 0.35)


# ── File operations ──────────────────────────────────────────────────────

func _on_save() -> void:
	if _ctx.current_file_path == "":
		_on_save_as()
		return
	var err = _ctx.save_to_file(_ctx.current_file_path)
	if err != OK:
		push_warning("SkillTreeEditor: save failed (%d)" % err)
	_update_title()

func _on_save_as() -> void:
	_ensure_dlg()
	_file_dlg_mode = "save"
	_file_dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dlg.current_path = "res://skill_tree_config.json"
	_file_dlg.popup_centered(Vector2(700, 500))

func _on_open() -> void:
	_ensure_dlg()
	_file_dlg_mode = "open"
	_file_dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dlg.popup_centered(Vector2(700, 500))

func _on_load_game_tree() -> void:
	var path: String = ProjectSettings.get_setting("skill_tree_editor/skill_config_path", "")
	if path == "":
		push_warning("SkillTreeEditor: No skill config path set. Use Tools > Set Skill Config... first.")
		return
	if _ctx.nodes.size() > 0:
		var cd := ConfirmationDialog.new()
		cd.dialog_text = "Replace current tree with the saved skill config?\n%s" % path
		cd.confirmed.connect(func():
			_do_load_game_tree(path)
			cd.queue_free())
		cd.visibility_changed.connect(func():
			if not cd.visible:
				cd.queue_free())
		add_child(cd)
		cd.popup_centered()
	else:
		_do_load_game_tree(path)

func _do_load_game_tree(path: String) -> void:
	var err = _ctx.load_from_file(path)
	if err != OK:
		push_warning("SkillTreeEditor: Failed to load config from %s (error %d)" % [path, err])
	_update_title()

func _auto_load_game_tree() -> void:
	var path: String = ProjectSettings.get_setting("skill_tree_editor/skill_config_path", "")
	if path != "" and _ctx.nodes.size() == 0:
		_do_load_game_tree(path)

func _ensure_dlg() -> void:
	if _file_dlg:
		return
	_file_dlg = EditorFileDialog.new()
	_file_dlg.add_filter("*.json", "JSON files")
	_file_dlg.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dlg.file_selected.connect(_on_file_sel)
	add_child(_file_dlg)

func _on_file_sel(path: String) -> void:
	match _file_dlg_mode:
		"save":
			var err = _ctx.save_to_file(path)
			if err != OK:
				push_warning("SkillTreeEditor: save failed (%d)" % err)
		"open":
			var err = _ctx.load_from_file(path)
			if err != OK:
				push_warning("SkillTreeEditor: load failed (%d)" % err)
	_update_title()


# ── Helpers ──────────────────────────────────────────────────────────────

func _on_purchase_spinbox_changed(new_value: float, id: String) -> void:
	if not _ctx or not _ctx.nodes.has(id):
		return
	_ctx.set_purchased(id, int(new_value))


func _cost_text(d: Dictionary) -> String:
	var base: int  = d.get("cost", 0)
	var inc: int   = d.get("cost_increase", 0)
	var expo: bool = d.get("exponential", false)
	if inc == 0:
		return "$%d" % base
	if expo:
		return "$%d%s" % [base, _to_superscript(inc)]
	return "$%d +%d" % [base, inc]


func _to_superscript(n: int) -> String:
	const SUP := ["\u2070","\u00b9","\u00b2","\u00b3","\u2074","\u2075","\u2076","\u2077","\u2078","\u2079"]
	var s := str(abs(n))
	var result := "\u207b" if n < 0 else ""
	for ch in s:
		result += SUP[int(ch)]
	return result


func _update_title() -> void:
	if _title_lbl:
		_title_lbl.text = _ctx.current_file_path if _ctx.current_file_path != "" else "(unsaved)"

func _show_empty() -> void:
	_empty_lbl = Label.new()
	_empty_lbl.text = "Double-click to create a node, or use Open\u2026 to load a saved tree.\nUse Tools > Set Skill Config... then Load Config to auto-load."
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.set_anchors_preset(PRESET_FULL_RECT)
	_empty_lbl.add_theme_color_override("font_color", Color(0.48, 0.48, 0.48))
	_empty_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_canvas_clip.add_child(_empty_lbl)

func _blank(pos: Vector2) -> Dictionary:
	return {
		"name": "New Skill", "cost": 100, "cost_increase": 0,
		"exponential": false, "max": 1, "description": "",
		"effect": "NONE", "value": 0.0, "position": pos,
		"emoticon": "", "image": "",
		"unlocks_on_purchase": 0, "unlocks_on_max": 0, "has_rank_up_child": false,
		"group": "", "purchased": 0, "secondary_unlock": "",
	}


func _rank_up_child_template(parent_id: String, wp: Vector2) -> Dictionary:
	var p: Dictionary = _ctx.nodes[parent_id]
	return {
		"name": p.get("name", "New Skill") + " I",
		"cost": p.get("cost", 100),
		"cost_increase": p.get("cost_increase", 0),
		"exponential": p.get("exponential", false),
		"max": p.get("max", 1),
		"description": p.get("description", ""),
		"effect": p.get("effect", "NONE"),
		"value": p.get("value", 0.0),
		"position": wp - Vector2(NODE_W * 0.5, 0),
		"emoticon": p.get("emoticon", ""),
		"image": "",
		"unlocks_on_purchase": 0, "unlocks_on_max": 0, "has_rank_up_child": false,
		"group": p.get("group", ""),
		"purchased": 0, "secondary_unlock": "",
	}


func _has_rank_up_child(id: String) -> bool:
	for c in _ctx.connections:
		if c["from"] == id and c["type"] == "rank_up":
			return true
	return false


func _shake_card(id: String) -> void:
	if not _cards.has(id):
		return
	var panel: PanelContainer = _cards[id]["panel"]
	if not is_instance_valid(panel):
		return
	var origin: Vector2 = panel.position
	var tw := create_tween()
	for i in 8:
		var x := pow(-1, i) * randf_range(3.0, 6.0) * _cam_zoom
		var y := randf_range(-2.0, 2.0) * _cam_zoom
		tw.tween_property(panel, "position", origin + Vector2(x, y), 0.03)
	tw.tween_property(panel, "position", origin, 0.04)
