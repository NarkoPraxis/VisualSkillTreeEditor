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
var _costs_vbox: VBoxContainer
var _costs_add_opt: OptionButton
var _costs_add_btn: Button
var _cost_spinboxes: Dictionary = {}  # currency_name → {cost_spin, inc_spin, exp_check}
var _max_spin: SpinBox
var _value_spin: SpinBox
var _effect_opt: OptionButton
var _emote_edit: LineEdit
var _icon_error: Label
var _icon_file_dlg: FileDialog
var _secondary_opt: OptionButton
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
	_fields.add_theme_constant_override("separation", 6)
	_scroll.add_child(_fields)

	# --- Fields ---
	_name_edit = _le("Name")
	_name_edit.text_changed.connect(func(t: String): _set_prop("name", t))

	# Costs section header
	var costs_hdr := HBoxContainer.new()
	costs_hdr.add_theme_constant_override("separation", 4)
	var costs_lbl := Label.new()
	costs_lbl.text = "Costs"
	costs_lbl.add_theme_font_size_override("font_size", 11)
	costs_lbl.custom_minimum_size = Vector2(LABEL_W, 0)
	costs_hdr.add_child(costs_lbl)
	_fields.add_child(costs_hdr)

	# Per-currency cost rows (rebuilt on selection)
	_costs_vbox = VBoxContainer.new()
	_costs_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_costs_vbox.add_theme_constant_override("separation", 4)
	_fields.add_child(_costs_vbox)

	# Add currency row
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	_costs_add_opt = OptionButton.new()
	_costs_add_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_costs_add_opt.tooltip_text = "Select a currency to add"
	add_row.add_child(_costs_add_opt)
	_costs_add_btn = Button.new()
	_costs_add_btn.text = "+ Add"
	_costs_add_btn.tooltip_text = "Add this currency cost to the skill"
	_costs_add_btn.pressed.connect(_do_add_currency_cost)
	add_row.add_child(_costs_add_btn)
	_fields.add_child(add_row)

	_max_spin = _sb("Max Purchases", 1, 99, 1)
	_max_spin.value_changed.connect(func(v: float): _set_prop("max", int(v)))

	# Effect: label + dropdown + gear all on one line
	var eff_row := HBoxContainer.new()
	eff_row.add_theme_constant_override("separation", 4)
	eff_row.add_child(_inline_lbl("Effect"))
	_effect_opt = OptionButton.new()
	_effect_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	eff_row.add_child(_effect_opt)
	var gear := Button.new()
	gear.text = "\u2699"
	gear.tooltip_text = "Configure effects & groups"
	gear.custom_minimum_size = Vector2(GUTTER_W, 0)
	gear.pressed.connect(_open_config)
	eff_row.add_child(gear)
	_fields.add_child(eff_row)

	_populate_effect_dropdown()
	_effect_opt.item_selected.connect(func(idx: int):
		_set_prop("effect", _effect_opt.get_item_text(idx)))

	_value_spin = _sb("Effect Value", -9999, 9999, 0.01)
	_value_spin.value_changed.connect(func(v: float): _set_prop("value", v))

	# Icon: label + line edit + choose file button (all inline)
	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 4)
	icon_row.add_child(_inline_lbl("Icon"))
	_emote_edit = LineEdit.new()
	_emote_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_emote_edit.placeholder_text = "emoji, symbol, or image path"
	_emote_edit.text_changed.connect(func(t: String):
		_set_prop("emoticon", t)
		_validate_icon_path(t))
	icon_row.add_child(_emote_edit)
	var file_btn := Button.new()
	file_btn.text = "\ud83d\udcc2"
	file_btn.tooltip_text = "Choose image file"
	file_btn.custom_minimum_size = Vector2(GUTTER_W, 0)
	file_btn.pressed.connect(_open_icon_file_dialog)
	icon_row.add_child(file_btn)
	_fields.add_child(icon_row)

	_icon_error = Label.new()
	_icon_error.add_theme_font_size_override("font_size", 10)
	_icon_error.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_icon_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_icon_error.visible = false
	_fields.add_child(_icon_error)

	# Secondary Unlock: label + dropdown + gear all on one line
	var sec_row := HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 4)
	sec_row.add_child(_inline_lbl("Sec. Unlock"))
	_secondary_opt = OptionButton.new()
	_secondary_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	sec_row.add_child(_secondary_opt)
	var sec_gear := Button.new()
	sec_gear.text = "\u2699"
	sec_gear.tooltip_text = "Configure secondary unlocks"
	sec_gear.custom_minimum_size = Vector2(GUTTER_W, 0)
	sec_gear.pressed.connect(_open_config_secondary)
	sec_row.add_child(sec_gear)
	_fields.add_child(sec_row)

	_populate_secondary_dropdown()
	_secondary_opt.item_selected.connect(func(idx: int):
		_set_prop("secondary_unlock", _secondary_opt.get_item_text(idx)))

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

const LABEL_W := 100  # wide enough for "Max Purchases" / "Effect Value"
const GUTTER_W := 28  # matches gear button / file-picker width

func _inline_lbl(label_text: String) -> Label:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.custom_minimum_size = Vector2(LABEL_W, 0)
	return lbl


func _gutter() -> Control:
	## Invisible spacer that keeps inputs aligned with rows that have a
	## trailing button (gear, file-picker).
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 0)
	return c


func _le(label_text: String, pad_right: bool = true) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_inline_lbl(label_text))
	var le := LineEdit.new()
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(le)
	if pad_right:
		row.add_child(_gutter())
	_fields.add_child(row)
	return le


func _sb(label_text: String, mn: float, mx: float, step: float, pad_right: bool = true) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_inline_lbl(label_text))
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(s)
	if pad_right:
		row.add_child(_gutter())
	_fields.add_child(row)
	return s


func _populate_effect_dropdown() -> void:
	_effect_opt.clear()
	for ename in _ctx.get_effect_names():
		_effect_opt.add_item(ename)


func _populate_secondary_dropdown() -> void:
	_secondary_opt.clear()
	for sname in _ctx.get_secondary_unlock_names():
		_secondary_opt.add_item(sname)


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
	_populate_secondary_dropdown()
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

	_refresh_costs_ui(id, d)

	var max_val := int(d.get("max", 1))
	if int(_max_spin.value) != max_val:
		_max_spin.value = max_val

	var value_val: float = d.get("value", 0.0)
	if _value_spin.value != value_val:
		_value_spin.value = value_val

	var emote_val: String = d.get("emoticon", "")
	if _emote_edit.text != emote_val:
		_emote_edit.text = emote_val
	_validate_icon_path(emote_val)

	# Secondary Unlock dropdown
	var sec: String = d.get("secondary_unlock", "NONE")
	var sec_names: PackedStringArray = _ctx.get_secondary_unlock_names()
	var sidx := 0
	for i in range(sec_names.size()):
		if sec_names[i] == sec:
			sidx = i
			break
	if _secondary_opt.selected != sidx:
		_secondary_opt.selected = sidx

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


# ── Icon file picker ─────────────────────────────────────────────────────

const _ICON_EXTENSIONS := ["png", "jpg", "jpeg", "svg"]


func _is_image_path(text: String) -> bool:
	var ext := text.get_extension().to_lower()
	return ext in _ICON_EXTENSIONS


func _validate_icon_path(text: String) -> void:
	if text == "" or not _is_image_path(text):
		_icon_error.visible = false
		_emote_edit.remove_theme_color_override("font_color")
		return
	if text.begins_with("res://"):
		_icon_error.visible = false
		_emote_edit.remove_theme_color_override("font_color")
	else:
		_icon_error.text = "Image must be inside the Godot project (res://)"
		_icon_error.visible = true
		_emote_edit.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _open_icon_file_dialog() -> void:
	if not _icon_file_dlg:
		_icon_file_dlg = FileDialog.new()
		_icon_file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_icon_file_dlg.access = FileDialog.ACCESS_RESOURCES
		_icon_file_dlg.filters = PackedStringArray(["*.png ; PNG", "*.jpg, *.jpeg ; JPEG", "*.svg ; SVG"])
		_icon_file_dlg.file_selected.connect(_on_icon_file_selected)
		add_child(_icon_file_dlg)
	_icon_file_dlg.popup_centered(Vector2i(640, 480))


func _on_icon_file_selected(path: String) -> void:
	_emote_edit.text = path
	_set_prop("emoticon", path)
	_validate_icon_path(path)


# ── Config dialog ────────────────────────────────────────────────────────

func _open_config(start_tab: int = 0) -> void:
	if not _config_dlg:
		_config_dlg = AcceptDialog.new()
		_config_dlg.set_script(ConfigDialog)
		_config_dlg.setup(_ctx)
		add_child(_config_dlg)
	_config_dlg.open_to_tab(start_tab)


func _open_config_secondary() -> void:
	_open_config(2)


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
	var raw_saved_costs = saved.get("costs", [])
	var saved_costs: Array = []
	if raw_saved_costs is Array:
		saved_costs = (raw_saved_costs as Array).duplicate(true)
	_ctx.nodes[id] = {
		"name":                str(saved.get("name", "")),
		"costs":               saved_costs,
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
		"secondary_unlock":    str(saved.get("secondary_unlock", "")),
	}
	# Recompute unlock counts from current connections (counts are derived, not stored)
	_ctx._update_unlock_counts()
	_ctx.data_changed.emit()


# ── Multi-currency cost section ──────────────────────────────────────────

func _refresh_costs_ui(id: String, d: Dictionary) -> void:
	## Called during _populate(). Smart refresh: only rebuilds widgets when
	## the set of currencies in the node changes; otherwise updates values in-place.
	var node_cur_names: Array = []
	for entry in d.get("costs", []):
		node_cur_names.append(entry.get("currency", ""))

	var displayed_names: Array = _cost_spinboxes.keys()
	if node_cur_names != displayed_names:
		_rebuild_costs_ui(id, d)
	else:
		# Update values in-place (preserves widget focus)
		for entry in d.get("costs", []):
			var cur_name: String = entry.get("currency", "")
			if not _cost_spinboxes.has(cur_name):
				continue
			var refs: Dictionary = _cost_spinboxes[cur_name]
			var cost_val: int = int(entry.get("cost", 0))
			if int((refs["cost_spin"] as SpinBox).value) != cost_val:
				(refs["cost_spin"] as SpinBox).value = cost_val
			var inc_val: int = int(entry.get("cost_increase", 0))
			if int((refs["inc_spin"] as SpinBox).value) != inc_val:
				(refs["inc_spin"] as SpinBox).value = inc_val
			var exp_val: bool = entry.get("exponential", false)
			if (refs["exp_check"] as CheckButton).button_pressed != exp_val:
				(refs["exp_check"] as CheckButton).button_pressed = exp_val

	# Always refresh the add dropdown (currencies may have been added/removed globally)
	_refresh_costs_add_opt(d)


func _rebuild_costs_ui(id: String, d: Dictionary) -> void:
	## Clears and rebuilds the per-currency cost rows in _costs_vbox.
	_cost_spinboxes.clear()
	while _costs_vbox.get_child_count() > 0:
		var child := _costs_vbox.get_child(0)
		_costs_vbox.remove_child(child)
		child.queue_free()

	var costs: Array = d.get("costs", [])
	for entry in costs:
		var cur_name: String = entry.get("currency", "")
		var clr: Color = _ctx.get_currency_color(cur_name)
		var display_name: String = _ctx.snake_to_title(cur_name)

		var entry_vbox := VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 2)
		entry_vbox.size_flags_horizontal = SIZE_EXPAND_FILL

		# Row 1: currency name label + remove button
		var row1 := HBoxContainer.new()
		row1.add_theme_constant_override("separation", 4)
		var name_lbl := Label.new()
		name_lbl.text = display_name
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", clr)
		name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		row1.add_child(name_lbl)
		var remove_btn := Button.new()
		remove_btn.text = "\u00d7"
		remove_btn.tooltip_text = "Remove %s cost from this skill" % display_name
		remove_btn.custom_minimum_size = Vector2(GUTTER_W, 0)
		remove_btn.pressed.connect(_remove_cost_entry.bind(id, cur_name))
		row1.add_child(remove_btn)
		entry_vbox.add_child(row1)

		# Row 2: Cost spinbox + Increase spinbox + Exponential checkbox
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 4)

		var cost_lbl := Label.new()
		cost_lbl.text = "Cost"
		cost_lbl.add_theme_font_size_override("font_size", 10)
		row2.add_child(cost_lbl)

		var cost_spin := SpinBox.new()
		cost_spin.min_value = 0
		cost_spin.max_value = 99999
		cost_spin.step = 1
		cost_spin.size_flags_horizontal = SIZE_EXPAND_FILL
		cost_spin.value = int(entry.get("cost", 0))
		cost_spin.value_changed.connect(func(v: float):
			if _updating: return
			_update_cost_entry(id, cur_name, "cost", int(v)))
		row2.add_child(cost_spin)

		var inc_lbl := Label.new()
		inc_lbl.text = "Inc"
		inc_lbl.add_theme_font_size_override("font_size", 10)
		row2.add_child(inc_lbl)

		var inc_spin := SpinBox.new()
		inc_spin.min_value = 0
		inc_spin.max_value = 99999
		inc_spin.step = 1
		inc_spin.size_flags_horizontal = SIZE_EXPAND_FILL
		inc_spin.value = int(entry.get("cost_increase", 0))
		inc_spin.value_changed.connect(func(v: float):
			if _updating: return
			_update_cost_entry(id, cur_name, "cost_increase", int(v)))
		row2.add_child(inc_spin)

		var exp_check := CheckButton.new()
		exp_check.text = "Exp"
		exp_check.add_theme_font_size_override("font_size", 10)
		exp_check.button_pressed = bool(entry.get("exponential", false))
		exp_check.toggled.connect(func(v: bool):
			if _updating: return
			_update_cost_entry(id, cur_name, "exponential", v))
		row2.add_child(exp_check)

		entry_vbox.add_child(row2)
		_costs_vbox.add_child(entry_vbox)

		_cost_spinboxes[cur_name] = {
			"cost_spin": cost_spin,
			"inc_spin":  inc_spin,
			"exp_check": exp_check,
		}

	if costs.size() > 0:
		_costs_vbox.add_child(HSeparator.new())


func _refresh_costs_add_opt(d: Dictionary) -> void:
	var already: Array = []
	for entry in d.get("costs", []):
		already.append(entry.get("currency", ""))
	_costs_add_opt.clear()
	for cur in _ctx.custom_currencies:
		var cname: String = cur["name"]
		if not already.has(cname):
			_costs_add_opt.add_item(_ctx.snake_to_title(cname))
			_costs_add_opt.set_item_metadata(_costs_add_opt.item_count - 1, cname)
	_costs_add_btn.disabled = _costs_add_opt.item_count == 0


func _do_add_currency_cost() -> void:
	var id: String = _ctx.selected_skill_id
	if id == "" or _costs_add_opt.item_count == 0:
		return
	var cur_name: String = str(_costs_add_opt.get_item_metadata(_costs_add_opt.selected))
	var d: Dictionary = _ctx.nodes[id]
	var raw = d.get("costs", [])
	var costs: Array = []
	if raw is Array:
		costs = (raw as Array).duplicate(true)
	costs.append({"currency": cur_name, "cost": 0, "cost_increase": 0, "exponential": false})
	_ctx.update_node(id, "costs", costs)


func _update_cost_entry(id: String, cur_name: String, field: String, value: Variant) -> void:
	if id == "" or not _ctx.nodes.has(id):
		return
	var raw = _ctx.nodes[id].get("costs", [])
	var costs: Array = []
	if raw is Array:
		costs = (raw as Array).duplicate(true)
	for entry in costs:
		if entry.get("currency", "") == cur_name:
			entry[field] = value
			break
	_ctx.update_node(id, "costs", costs)


func _remove_cost_entry(id: String, cur_name: String) -> void:
	if id == "" or not _ctx.nodes.has(id):
		return
	var costs: Array = _ctx.nodes[id].get("costs", [])
	var filtered: Array = []
	for entry in costs:
		if entry.get("currency", "") != cur_name:
			filtered.append(entry)
	_ctx.update_node(id, "costs", filtered)
