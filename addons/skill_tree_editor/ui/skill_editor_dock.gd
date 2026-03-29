## Dockable properties panel for the Skill Editor.
##
## Shows editable fields for the currently selected skill node.
## Reacts to SkillEditorContext signals; never references the main canvas.
@tool
extends VBoxContainer

const ConfigDialog = preload("res://addons/skill_tree_editor/ui/config_dialog.gd")

var _ctx: RefCounted  # SkillEditorContext
var _updating := false  # prevents feedback loops when populating fields

var _config_dlg: AcceptDialog

# ── Field refs ───────────────────────────────────────────────────────────
var _name_edit: LineEdit
var _cost_spin: SpinBox
var _cost_inc_spin: SpinBox
var _exp_check: CheckButton
var _max_spin: SpinBox
var _value_spin: SpinBox
var _effect_opt: OptionButton
var _emote_edit: LineEdit
var _letter_edit: LineEdit
var _desc_edit: TextEdit
var _restore_btn: Button

var _placeholder: Label
var _scroll: ScrollContainer
var _fields: VBoxContainer


func setup(ctx: RefCounted) -> void:
	_ctx = ctx


func _ready() -> void:
	custom_minimum_size = Vector2(240, 0)
	size_flags_vertical = SIZE_EXPAND_FILL
	_build_ui()
	_wire()
	_show_placeholder()


# ── UI construction ──────────────────────────────────────────────────────

func _build_ui() -> void:
	# Title
	var title := Label.new()
	title.text = "Skill Properties"
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)
	add_child(HSeparator.new())

	# Placeholder
	_placeholder = Label.new()
	_placeholder.text = "Select a node to edit\nits properties here."
	_placeholder.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_placeholder)

	# Scrollable fields
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	add_child(_scroll)

	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", 3)
	_scroll.add_child(_fields)

	# --- Fields ---
	_name_edit = _le("Name")
	_name_edit.text_changed.connect(func(t: String): _set_prop("name", t))

	_cost_spin = _sb("Cost", 0, 99999, 1)
	_cost_spin.value_changed.connect(func(v: float): _set_prop("cost", int(v)))

	_cost_inc_spin = _sb("Cost Increase", 0, 99999, 1)
	_cost_inc_spin.value_changed.connect(func(v: float): _set_prop("cost_increase", int(v)))

	_exp_check = CheckButton.new()
	_exp_check.text = "Exponential Cost"
	_exp_check.toggled.connect(func(v: bool): _set_prop("exponential", v))
	_fields.add_child(_exp_check)

	_max_spin = _sb("Max Purchases", 1, 99, 1)
	_max_spin.value_changed.connect(func(v: float): _set_prop("max", int(v)))

	_value_spin = _sb("Effect Value", -9999, 9999, 0.01)
	_value_spin.value_changed.connect(func(v: float): _set_prop("value", v))

	# Effect: label + dropdown + gear all on one line
	var eff_row := HBoxContainer.new()
	eff_row.add_theme_constant_override("separation", 4)
	var eff_lbl := Label.new()
	eff_lbl.text = "Effect"
	eff_lbl.add_theme_font_size_override("font_size", 11)
	eff_row.add_child(eff_lbl)
	_effect_opt = OptionButton.new()
	_effect_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	eff_row.add_child(_effect_opt)
	var gear := Button.new()
	gear.text = "\u2699"
	gear.tooltip_text = "Configure effects & groups"
	gear.custom_minimum_size = Vector2(22, 22)
	gear.pressed.connect(_open_config)
	eff_row.add_child(gear)
	_fields.add_child(eff_row)

	_populate_effect_dropdown()
	_effect_opt.item_selected.connect(func(idx: int):
		_set_prop("effect", _effect_opt.get_item_text(idx)))

	_emote_edit = _le("Emoticon")
	_emote_edit.placeholder_text = "emoji or symbol"
	_emote_edit.text_changed.connect(func(t: String): _set_prop("emoticon", t))

	_letter_edit = _le("Unlocks Letter")
	_letter_edit.placeholder_text = "single character"
	_letter_edit.max_length = 1
	_letter_edit.text_changed.connect(func(t: String): _set_prop("unlocks_letter", t))

	_fields.add_child(HSeparator.new())
	var desc_title := Label.new()
	desc_title.text = "Description"
	desc_title.add_theme_font_size_override("font_size", 11)
	_fields.add_child(desc_title)

	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 64)
	_desc_edit.placeholder_text = "Describe this skill\u2026"
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc_edit.text_changed.connect(func(): _set_prop("description", _desc_edit.text))
	_fields.add_child(_desc_edit)

	_fields.add_child(HSeparator.new())

	_restore_btn = Button.new()
	_restore_btn.text = "Restore Defaults"
	_restore_btn.tooltip_text = "Reset all properties to the last saved values"
	_restore_btn.pressed.connect(_on_restore)
	_fields.add_child(_restore_btn)


# ── Helpers for building fields ──────────────────────────────────────────

func _le(label_text: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	_fields.add_child(lbl)
	var le := LineEdit.new()
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	_fields.add_child(le)
	return le


func _sb(label_text: String, mn: float, mx: float, step: float) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	_fields.add_child(lbl)
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	_fields.add_child(s)
	return s


func _populate_effect_dropdown() -> void:
	_effect_opt.clear()
	for ename in _ctx.get_effect_names():
		_effect_opt.add_item(ename)


# ── Context wiring ───────────────────────────────────────────────────────

func _wire() -> void:
	if not _ctx:
		return
	_ctx.skill_selected.connect(_on_selected)
	_ctx.skill_deselected.connect(_on_deselected)
	_ctx.data_changed.connect(_on_data)


func _show_placeholder() -> void:
	_placeholder.visible = true
	_scroll.visible = false

func _show_fields() -> void:
	_placeholder.visible = false
	_scroll.visible = true


func _on_selected(id: String) -> void:
	_show_fields()
	_populate(id)

func _on_deselected() -> void:
	_show_placeholder()

func _on_data() -> void:
	_populate_effect_dropdown()
	if _ctx.selected_skill_id != "":
		_populate(_ctx.selected_skill_id)


# ── Populate fields from node data ───────────────────────────────────────

func _populate(id: String) -> void:
	if not _ctx.nodes.has(id):
		_show_placeholder()
		return
	_updating = true
	var d: Dictionary = _ctx.nodes[id]

	# Only write to a field when its value actually differs from the current
	# display value.  This preserves cursor position and selection while the
	# user is typing — without this guard, every keystroke resets the cursor
	# to position 0 because _on_data → _populate overwrites the field text.

	var name_val: String = d.get("name", "")
	if _name_edit.text != name_val:
		_name_edit.text = name_val

	var cost_val := int(d.get("cost", 0))
	if int(_cost_spin.value) != cost_val:
		_cost_spin.value = cost_val

	var cost_inc_val := int(d.get("cost_increase", 0))
	if int(_cost_inc_spin.value) != cost_inc_val:
		_cost_inc_spin.value = cost_inc_val

	var exp_val: bool = d.get("exponential", false)
	if _exp_check.button_pressed != exp_val:
		_exp_check.button_pressed = exp_val

	var max_val := int(d.get("max", 1))
	if int(_max_spin.value) != max_val:
		_max_spin.value = max_val

	var value_val: float = d.get("value", 0.0)
	if _value_spin.value != value_val:
		_value_spin.value = value_val

	var emote_val: String = d.get("emoticon", "")
	if _emote_edit.text != emote_val:
		_emote_edit.text = emote_val

	var letter_val: String = d.get("unlocks_letter", "")
	if _letter_edit.text != letter_val:
		_letter_edit.text = letter_val

	var desc_val: String = d.get("description", "")
	if _desc_edit.text != desc_val:
		_desc_edit.text = desc_val

	# Effect dropdown
	var eff: String = d.get("effect", "NONE")
	var eff_names: PackedStringArray = _ctx.get_effect_names()
	var eidx := 0
	for i in range(eff_names.size()):
		if eff_names[i] == eff:
			eidx = i
			break
	if _effect_opt.selected != eidx:
		_effect_opt.selected = eidx

	# Lock Effect for rank_up children (inherited from parent)
	_effect_opt.disabled = _ctx.is_rank_up_child(id)

	_updating = false


func _set_prop(key: String, value: Variant) -> void:
	if _updating or _ctx.selected_skill_id == "":
		return
	_ctx.update_node(_ctx.selected_skill_id, key, value)


# ── Config dialog ────────────────────────────────────────────────────────

func _open_config() -> void:
	if not _config_dlg:
		_config_dlg = AcceptDialog.new()
		_config_dlg.set_script(ConfigDialog)
		_config_dlg.setup(_ctx)
		add_child(_config_dlg)
	_config_dlg.popup_centered(Vector2i(560, 520))


# ── Restore defaults ─────────────────────────────────────────────────────

func _on_restore() -> void:
	var id: String = _ctx.selected_skill_id
	if id == "" or _ctx.last_saved_data.is_empty():
		return
	var saved_nodes: Dictionary = _ctx.last_saved_data.get("nodes", {})
	if not saved_nodes.has(id):
		return
	var saved: Dictionary = saved_nodes[id]
	# Keep current canvas position
	var pos: Vector2 = _ctx.nodes[id].get("position", Vector2.ZERO)
	var pa = saved.get("position", [pos.x, pos.y])
	_ctx.nodes[id] = {
		"name":                str(saved.get("name", "")),
		"cost":                int(saved.get("cost", 0)),
		"cost_increase":       int(saved.get("cost_increase", 0)),
		"exponential":         bool(saved.get("exponential", false)),
		"max":                 int(saved.get("max", 1)),
		"description":         str(saved.get("description", "")),
		"effect":              str(saved.get("effect", "NONE")),
		"value":               float(saved.get("value", 0.0)),
		"position":            pos,
		"emoticon":            str(saved.get("emoticon", "")),
		"image":               str(saved.get("image", "")),
		"unlocks_on_purchase": 0,
		"unlocks_on_max":      0,
		"has_rank_up_child":   false,
		"group":               str(saved.get("group", "")),
		"purchased":           int(saved.get("purchased", 0)),
		"unlocks_letter":      str(saved.get("unlocks_letter", "")),
	}
	# Recompute unlock counts from current connections (counts are derived, not stored)
	_ctx._update_unlock_counts()
	_ctx.data_changed.emit()
