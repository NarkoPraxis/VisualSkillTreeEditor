## In-game skill card widget.
##
## Displays one skill from the tree: icon, name, cost, purchase count, and a
## Buy button.  Visual style mirrors the Skill Tree Editor canvas exactly
## (same group colours, border states, fonts).  All logic lives in SkillTree —
## this node only renders state passed via setup() / refresh_state().
##
## Signals emitted upward:
##   buy_pressed(node_id)    → user clicked Buy
##   node_hovered(node_id)   → mouse entered card (for tooltip)
##   node_unhovered(node_id) → mouse left card
@tool
extends Control
class_name SkillNode

# ── Colours (labels match what SkillTreeData stores in nodes["group"]) ───

const GRP_BG: Dictionary = {
	"ECONOMY":    Color(0.27, 0.24, 0.14),
	"COMBAT":     Color(0.27, 0.15, 0.15),
	"PRODUCTION": Color(0.14, 0.27, 0.17),
	"PROGRESSION":Color(0.13, 0.20, 0.35),
	"DROP":       Color(0.22, 0.15, 0.30),
	"CUSTOM":     Color(0.19, 0.21, 0.26),
}
const GRP_BORDER: Dictionary = {
	"ECONOMY":    Color(0.92, 0.78, 0.32, 0.70),
	"COMBAT":     Color(0.92, 0.42, 0.42, 0.70),
	"PRODUCTION": Color(0.38, 0.82, 0.48, 0.70),
	"PROGRESSION":Color(0.40, 0.60, 0.92, 0.70),
	"DROP":       Color(0.72, 0.48, 0.92, 0.70),
	"CUSTOM":     Color(0.62, 0.62, 0.62, 0.70),
}
const DEFAULT_BG     := Color(0.21, 0.21, 0.25)
const DEFAULT_BORDER := Color(0.48, 0.48, 0.48, 0.70)
const PURCHASED_BORDER := Color(1.00, 1.00, 1.00, 0.90)
const MAXED_BORDER     := Color(1.00, 0.80, 0.15, 1.00)
const RANKUP_BORDER    := Color(1.00, 0.20, 0.20, 1.00)
const COST_COLOR       := Color(0.92, 0.88, 0.35)

const NODE_W := 180.0
const NODE_H := 82.0
const _IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "svg", "webp"]

# ── Signals ───────────────────────────────────────────────────────────────

signal buy_pressed(node_id: String)
signal node_hovered(node_id: String)
signal node_unhovered(node_id: String)

# ── State ─────────────────────────────────────────────────────────────────

## Saved by Generate Tree — do not edit manually.
@export var _node_id: String = ""
## Saved by Generate Tree — do not edit manually.
@export var _node_data: Dictionary = {}

# UI refs — populated by _build_ui()
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _badge_sty: StyleBoxFlat
var _badge_panel: PanelContainer
var _badge_lbl: Label
var _emote_lbl: Label
var _icon_tex: TextureRect
var _name_lbl: Label
var _cost_lbl: Label
var _count_lbl: Label
var _buy_btn: Button


# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(NODE_W, NODE_H)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(func(): node_hovered.emit(_node_id))
	mouse_exited.connect(func(): node_unhovered.emit(_node_id))
	# Self-initialize from exported data saved by Generate Tree.
	# Runs at both editor-reload and runtime — no setup() call needed.
	if not _node_id.is_empty() and not _node_data.is_empty():
		_build_ui()
		refresh_state(_node_data.get("purchased", 0), false, false)


func setup(id: String, data: Dictionary) -> void:
	## Call this once after adding the node to the scene tree.
	## Rebuilds the card UI from the provided skill data dictionary.
	_node_id = id
	_node_data = data.duplicate()
	# Clear any UI built by a prior setup() call
	for child in get_children():
		child.free()
	_panel = null
	_build_ui()
	refresh_state(
		data.get("purchased", 0),
		false,   # maxed — SkillTree will call refresh_state() with real values
		false    # rank_up_maxed
	)


func get_node_id() -> String:
	return _node_id


# ── Visual refresh ────────────────────────────────────────────────────────

func refresh_state(purchased: int, maxed: bool, rank_up_maxed: bool) -> void:
	## Update border colour, buy button, and count label.
	## Called by SkillTree whenever purchase state changes.
	## Visibility (locked/unlocked) is controlled by SkillTree directly.
	if not is_instance_valid(_panel_style):
		return

	var grp: String = _node_data.get("group", "")
	var max_val: int = _node_data.get("max", 1)

	# Border colour mirrors the editor's _refresh_card logic
	var border_col: Color
	var border_w: int
	if rank_up_maxed:
		border_col = RANKUP_BORDER
		border_w = 3
	elif maxed:
		border_col = MAXED_BORDER
		border_w = 3
	elif purchased >= 1:
		border_col = PURCHASED_BORDER
		border_w = 2
	else:
		border_col = GRP_BORDER.get(grp, DEFAULT_BORDER)
		border_w = 2
	_panel_style.border_color = border_col
	_panel_style.set_border_width_all(border_w)
	if is_instance_valid(_badge_sty):
		_badge_sty.border_color = border_col
		_badge_lbl.add_theme_color_override("font_color", border_col)

	# Count label
	if is_instance_valid(_count_lbl):
		_count_lbl.text = "%d / %d" % [purchased, max_val]

	# Buy button state
	if is_instance_valid(_buy_btn):
		if maxed:
			_buy_btn.text = "Maxed"
			_buy_btn.disabled = true
			_buy_btn.modulate = Color(MAXED_BORDER, 0.85)
		else:
			_buy_btn.text = "Buy"
			_buy_btn.disabled = false
			_buy_btn.modulate = Color(1, 1, 1, 1)


# ── UI construction ───────────────────────────────────────────────────────

func _build_ui() -> void:
	var grp: String = _node_data.get("group", "")

	# ── Background panel ──────────────────────────────────────────────────
	_panel_style = StyleBoxFlat.new()
	_panel_style.set_corner_radius_all(8)
	_panel_style.bg_color = GRP_BG.get(grp, DEFAULT_BG)
	_panel_style.border_color = GRP_BORDER.get(grp, DEFAULT_BORDER)
	_panel_style.set_border_width_all(2)
	_panel_style.set_content_margin_all(8)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
	_panel.size = _panel.custom_minimum_size
	_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _panel_style)
	add_child(_panel)

	# ── Main HBox ─────────────────────────────────────────────────────────
	var main_hb := HBoxContainer.new()
	main_hb.mouse_filter = MOUSE_FILTER_IGNORE
	main_hb.add_theme_constant_override("separation", 6)
	_panel.add_child(main_hb)

	# ── Icon column ───────────────────────────────────────────────────────
	var icon_size: float = NODE_H - 16.0  # content margins 8px each side

	_icon_tex = TextureRect.new()
	_icon_tex.custom_minimum_size = Vector2(icon_size, icon_size)
	_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_tex.mouse_filter = MOUSE_FILTER_IGNORE
	_icon_tex.size_flags_vertical = SIZE_SHRINK_CENTER
	_icon_tex.visible = false
	main_hb.add_child(_icon_tex)

	_emote_lbl = Label.new()
	_emote_lbl.text = ""
	_emote_lbl.visible = false
	_emote_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_emote_lbl.add_theme_font_size_override("font_size", 44)
	_emote_lbl.size_flags_vertical = SIZE_SHRINK_CENTER
	main_hb.add_child(_emote_lbl)

	_apply_icon(_node_data.get("emoticon", ""))

	# ── Right column: name + cost + buy ───────────────────────────────────
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = SIZE_EXPAND_FILL
	main_hb.add_child(vb)

	# Row 1 — name + optional badge
	var top_hb := HBoxContainer.new()
	top_hb.mouse_filter = MOUSE_FILTER_IGNORE
	top_hb.add_theme_constant_override("separation", 4)
	vb.add_child(top_hb)

	_name_lbl = Label.new()
	_name_lbl.text = _node_data.get("name", "")
	_name_lbl.add_theme_font_size_override("font_size", 15)
	_name_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_name_lbl.clip_text = true
	_name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	top_hb.add_child(_name_lbl)

	# Secondary unlock badge (first 3 chars)
	var sec: String = _node_data.get("secondary_unlock", "")
	var badge_text: String = sec.left(3) if (sec != "" and sec != "NONE") else ""
	_badge_sty = StyleBoxFlat.new()
	_badge_sty.set_corner_radius_all(3)
	_badge_sty.bg_color = Color(0, 0, 0, 0)
	_badge_sty.border_color = _panel_style.border_color
	_badge_sty.set_border_width_all(1)
	_badge_sty.set_content_margin_all(1)
	_badge_panel = PanelContainer.new()
	_badge_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_badge_panel.visible = badge_text != ""
	_badge_panel.add_theme_stylebox_override("panel", _badge_sty)
	_badge_lbl = Label.new()
	_badge_lbl.text = badge_text
	_badge_lbl.add_theme_font_size_override("font_size", 16)
	_badge_lbl.add_theme_color_override("font_color", _panel_style.border_color)
	_badge_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_badge_panel.add_child(_badge_lbl)
	top_hb.add_child(_badge_panel)

	# Row 2 — cost label + count
	var stats_hb := HBoxContainer.new()
	stats_hb.mouse_filter = MOUSE_FILTER_IGNORE
	stats_hb.add_theme_constant_override("separation", 4)
	vb.add_child(stats_hb)

	_cost_lbl = Label.new()
	_cost_lbl.text = _cost_text()
	_cost_lbl.add_theme_font_size_override("font_size", 11)
	_cost_lbl.add_theme_color_override("font_color", COST_COLOR)
	_cost_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_cost_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	stats_hb.add_child(_cost_lbl)

	_count_lbl = Label.new()
	var max_val: int = _node_data.get("max", 1)
	_count_lbl.text = "0 / %d" % max_val
	_count_lbl.add_theme_font_size_override("font_size", 11)
	_count_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	stats_hb.add_child(_count_lbl)

	# Row 3 — Buy button
	var btn_hb := HBoxContainer.new()
	btn_hb.mouse_filter = MOUSE_FILTER_IGNORE
	btn_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_hb)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.set_corner_radius_all(4)
	btn_normal.bg_color = Color(0.22, 0.35, 0.22)
	btn_normal.border_color = Color(0.38, 0.82, 0.48, 0.80)
	btn_normal.set_border_width_all(1)
	btn_normal.set_content_margin_all(4)
	btn_normal.content_margin_left = 10
	btn_normal.content_margin_right = 10

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.28, 0.45, 0.28)

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.16, 0.26, 0.16)

	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.set_corner_radius_all(4)
	btn_disabled.bg_color = Color(0.18, 0.18, 0.20)
	btn_disabled.border_color = Color(0.35, 0.35, 0.35, 0.50)
	btn_disabled.set_border_width_all(1)
	btn_disabled.set_content_margin_all(4)
	btn_disabled.content_margin_left = 10
	btn_disabled.content_margin_right = 10

	_buy_btn = Button.new()
	_buy_btn.text = "Buy"
	_buy_btn.add_theme_font_size_override("font_size", 11)
	_buy_btn.add_theme_stylebox_override("normal",   btn_normal)
	_buy_btn.add_theme_stylebox_override("hover",    btn_hover)
	_buy_btn.add_theme_stylebox_override("pressed",  btn_pressed)
	_buy_btn.add_theme_stylebox_override("disabled", btn_disabled)
	_buy_btn.pressed.connect(func(): buy_pressed.emit(_node_id))
	btn_hb.add_child(_buy_btn)



# ── Icon helpers ──────────────────────────────────────────────────────────

func _apply_icon(icon_value: String) -> void:
	if icon_value.is_empty():
		_emote_lbl.visible = false
		_icon_tex.visible = false
		return
	var ext := icon_value.get_extension().to_lower()
	if ext in _IMAGE_EXTENSIONS:
		_emote_lbl.visible = false
		var tex: Texture2D = null
		if icon_value.begins_with("res://") and ResourceLoader.exists(icon_value):
			tex = load(icon_value)
		elif FileAccess.file_exists(icon_value):
			var img := Image.new()
			if img.load(icon_value) == OK:
				tex = ImageTexture.create_from_image(img)
		_icon_tex.texture = tex
		_icon_tex.visible = tex != null
	else:
		_icon_tex.visible = false
		_emote_lbl.text = icon_value
		_emote_lbl.visible = true


func _cost_text() -> String:
	var base: int = _node_data.get("cost", 0)
	var inc: int = _node_data.get("cost_increase", 0)
	if inc == 0:
		return "$%d" % base
	if _node_data.get("exponential", false):
		return "$%d \u00d7%d%%" % [base, inc]  # e.g. "$100 ×50%"
	return "$%d +%d" % [base, inc]             # e.g. "$100 +50"
