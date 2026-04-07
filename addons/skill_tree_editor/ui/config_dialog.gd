## Tabbed dialog for configuring effects and groups.
##
## Effects tab: flat list with rapid keyboard add/rename/remove.
## Groups tab: list with label column + effect assignment sub-panel.
## Every keyboard shortcut has an on-screen button equivalent.
@tool
extends AcceptDialog

var _ctx: RefCounted  # SkillEditorContext
var _tabs: TabBar
var _pages: Array[Control] = []

# ── Effects tab refs ────────────────────────────────────────────────────
var _eff_list: ItemList
var _eff_field: LineEdit
var _eff_add_btn: Button
var _eff_rename_btn: Button
var _eff_remove_btn: Button

# ── Secondary Unlocks tab refs ──────────────────────────────────────────
var _sec_list: ItemList
var _sec_field: LineEdit
var _sec_add_btn: Button
var _sec_rename_btn: Button
var _sec_remove_btn: Button

# ── Groups tab refs ─────────────────────────────────────────────────────
var _grp_scroll: ScrollContainer
var _grp_list_vbox: VBoxContainer
var _grp_selected_label: String = ""
var _grp_row_btns: Dictionary = {}
var _grp_color_pickers: Dictionary = {}
var _grp_label_field: LineEdit
var _grp_add_btn: Button
var _grp_rename_btn: Button
var _grp_remove_btn: Button

var _grp_effects_panel: VBoxContainer
var _grp_effects_title: Label
var _grp_effects_list: ItemList
var _grp_effects_opt: OptionButton
var _grp_assign_btn: Button
var _grp_unassign_btn: Button


func setup(ctx: RefCounted) -> void:
	_ctx = ctx


func _ready() -> void:
	title = "Configure Effects & Groups"
	min_size = Vector2i(560, 520)
	_build_ui()
	get_ok_button().hide()
	about_to_popup.connect(_on_about_to_popup)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_tabs = TabBar.new()
	_tabs.add_tab("Effects")
	_tabs.add_tab("Groups")
	_tabs.add_tab("Secondary Unlocks")
	_tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(_tabs)

	var eff_page := _build_effects_page()
	root.add_child(eff_page)
	_pages.append(eff_page)

	var grp_page := _build_groups_page()
	grp_page.visible = false
	root.add_child(grp_page)
	_pages.append(grp_page)

	var sec_page := _build_secondary_page()
	sec_page.visible = false
	root.add_child(sec_page)
	_pages.append(sec_page)

	add_child(root)


func _on_tab_changed(idx: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = (i == idx)
	if idx == 0:
		_refresh_effects()
		_eff_field.call_deferred("grab_focus")
	elif idx == 1:
		_refresh_groups()
		_grp_label_field.call_deferred("grab_focus")
	elif idx == 2:
		_refresh_secondary()
		_sec_field.call_deferred("grab_focus")


var _start_tab: int = 0

func open_to_tab(tab: int = 0) -> void:
	_start_tab = tab
	popup_centered(Vector2i(560, 520))

func _on_about_to_popup() -> void:
	_tabs.current_tab = _start_tab
	_on_tab_changed(_start_tab)
	_start_tab = 0


# ── Button style helpers ─────────────────────────────────────────────────

func _make_stylebox(color: Color, pad: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


func _make_plus_icon() -> ImageTexture:
	var sz := 34 / 2
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := sz / 2
	# Draw antialiased-ish thick cross: 3px arms
	for i in range(1, sz - 1):
		img.set_pixel(i, cx - 1, Color.WHITE)
		img.set_pixel(i, cx,     Color.WHITE)
		img.set_pixel(i, cx + 1, Color.WHITE)
		img.set_pixel(cx - 1, i, Color.WHITE)
		img.set_pixel(cx,     i, Color.WHITE)
		img.set_pixel(cx + 1, i, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _style_add_btn(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",   _make_stylebox(Color(0.18, 0.50, 0.18), 8))
	btn.add_theme_stylebox_override("hover",    _make_stylebox(Color(0.24, 0.62, 0.24), 8))
	btn.add_theme_stylebox_override("pressed",  _make_stylebox(Color(0.12, 0.36, 0.12), 8))
	btn.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.12, 0.28, 0.12), 8))
	btn.add_theme_color_override("font_color",          Color.WHITE)
	btn.add_theme_color_override("font_hover_color",    Color.WHITE)
	btn.add_theme_color_override("font_pressed_color",  Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))


func _setup_plus_btn(btn: Button) -> void:
	btn.text = ""
	btn.icon = _make_plus_icon()
	btn.expand_icon = false
	btn.custom_minimum_size = Vector2(34,34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_stylebox_override("normal",   _make_stylebox(Color(0.18, 0.50, 0.18), 0))
	btn.add_theme_stylebox_override("hover",    _make_stylebox(Color(0.24, 0.62, 0.24), 0))
	btn.add_theme_stylebox_override("pressed",  _make_stylebox(Color(0.12, 0.36, 0.12), 0))
	btn.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.12, 0.28, 0.12), 0))
	btn.add_theme_color_override("font_color",          Color.WHITE)
	btn.add_theme_color_override("font_hover_color",    Color.WHITE)
	btn.add_theme_color_override("font_pressed_color",  Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))


func _make_x_icon() -> ImageTexture:
	var sz := 34 / 2
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Draw two diagonal lines, 3px thick
	for i in range(1, sz - 1):
		var o := i - sz / 2
		for t in [-1, 0, 1]:
			var px := i
			var py = sz / 2 + o + t
			if px >= 0 and px < sz and py >= 0 and py < sz:
				img.set_pixel(px, py, Color.WHITE)
			px = i
			py = sz / 2 - o + t
			if px >= 0 and px < sz and py >= 0 and py < sz:
				img.set_pixel(px, py, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _spacer_v(height: int = 4) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _setup_remove_btn(btn: Button) -> void:
	btn.text = ""
	btn.icon = _make_x_icon()
	btn.expand_icon = false
	btn.custom_minimum_size = Vector2(34, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_stylebox_override("normal",   _make_stylebox(Color(0.55, 0.10, 0.10), 0))
	btn.add_theme_stylebox_override("hover",    _make_stylebox(Color(0.70, 0.15, 0.15), 0))
	btn.add_theme_stylebox_override("pressed",  _make_stylebox(Color(0.40, 0.08, 0.08), 0))
	btn.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.30, 0.08, 0.08), 0))
	btn.add_theme_color_override("font_color",          Color.WHITE)
	btn.add_theme_color_override("font_hover_color",    Color.WHITE)
	btn.add_theme_color_override("font_pressed_color",  Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))


# ═══════════════════════════════════════════════════════════════════════
# EFFECTS TAB
# ═══════════════════════════════════════════════════════════════════════

func _build_effects_page() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	_eff_list = ItemList.new()
	_eff_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_eff_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eff_list.select_mode = ItemList.SELECT_SINGLE
	_eff_list.allow_reselect = true
	_eff_list.custom_minimum_size = Vector2(0, 200)
	_eff_list.item_selected.connect(_on_eff_item_selected)
	_eff_list.gui_input.connect(_on_eff_list_input)
	vbox.add_child(_eff_list)
	vbox.add_child(_spacer_v(4))

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	_eff_add_btn = Button.new()
	_eff_add_btn.tooltip_text = "Add new effect (Enter)"
	_eff_add_btn.pressed.connect(func(): _do_eff_add(_eff_field.text))
	_setup_plus_btn(_eff_add_btn)
	add_row.add_child(_eff_add_btn)
	_eff_field = LineEdit.new()
	_eff_field.placeholder_text = "Type effect name, press Enter"
	_eff_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eff_field.gui_input.connect(_on_eff_field_input)
	add_row.add_child(_eff_field)
	_eff_rename_btn = Button.new()
	_eff_rename_btn.text = "Replace"
	_eff_rename_btn.tooltip_text = "Replace selected effect with the text in the field (F2)"
	_eff_rename_btn.pressed.connect(_do_eff_rename)
	_eff_rename_btn.disabled = true
	add_row.add_child(_eff_rename_btn)
	_eff_remove_btn = Button.new()

	_eff_remove_btn.tooltip_text = "Remove selected effect (Del)"
	_eff_remove_btn.pressed.connect(_do_eff_remove)
	_eff_remove_btn.disabled = true
	_setup_remove_btn(_eff_remove_btn)
	add_row.add_child(_eff_remove_btn)
	vbox.add_child(add_row)

	return vbox


func _refresh_effects() -> void:
	var prev_sel := -1
	if _eff_list.get_selected_items().size() > 0:
		prev_sel = _eff_list.get_selected_items()[0]
	_eff_list.clear()
	for ename in _ctx.custom_effects:
		_eff_list.add_item(ename)
	if prev_sel >= 0 and prev_sel < _eff_list.item_count:
		_eff_list.select(prev_sel)
		_update_eff_buttons(true)
	else:
		_update_eff_buttons(false)


func _update_eff_buttons(has_sel: bool) -> void:
	_eff_rename_btn.disabled = not has_sel
	_eff_remove_btn.disabled = not has_sel


func _on_eff_item_selected(_index: int) -> void:
	_update_eff_buttons(true)


func _sanitize(text: String) -> String:
	return text.strip_edges().to_upper().replace(" ", "_")


func _do_eff_add(text: String) -> void:
	var clean := _sanitize(text)
	if clean == "":
		return
	if _ctx.custom_effects.has(clean):
		_eff_field.clear()
		return
	_ctx.add_effect(clean)
	_eff_field.clear()
	_refresh_effects()
	for i in range(_eff_list.item_count):
		if _eff_list.get_item_text(i) == clean:
			_eff_list.select(i)
			_eff_list.ensure_current_is_visible()
			_update_eff_buttons(true)
			break
	_eff_field.call_deferred("grab_focus")


func _do_eff_rename() -> void:
	var sel := _eff_list.get_selected_items()
	if sel.size() == 0:
		return
	var old_name: String = _eff_list.get_item_text(sel[0])
	var new_name := _sanitize(_eff_field.text)
	if new_name == "" or new_name == old_name:
		return
	_ctx.rename_effect(old_name, new_name)
	_eff_field.clear()
	_refresh_effects()
	for i in range(_eff_list.item_count):
		if _eff_list.get_item_text(i) == new_name:
			_eff_list.select(i)
			_eff_list.ensure_current_is_visible()
			break
	_eff_field.call_deferred("grab_focus")


func _do_eff_remove() -> void:
	var sel := _eff_list.get_selected_items()
	if sel.size() == 0:
		return
	var ename: String = _eff_list.get_item_text(sel[0])
	_ctx.remove_effect(ename)
	_refresh_effects()


func _on_eff_list_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			_do_eff_remove()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			var sel := _eff_list.get_selected_items()
			if sel.size() > 0:
				_eff_field.text = _eff_list.get_item_text(sel[0])
				_eff_field.grab_focus()
				_eff_field.select_all()
			get_viewport().set_input_as_handled()


func _on_eff_field_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_do_eff_add(_eff_field.text)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			_do_eff_rename()
			get_viewport().set_input_as_handled()
		elif _eff_field.text.strip_edges() == "":
			if event.keycode == KEY_UP:
				_move_eff_selection(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_move_eff_selection(1)
				get_viewport().set_input_as_handled()


func _move_eff_selection(delta: int) -> void:
	if _eff_list.item_count == 0:
		return
	var sel := _eff_list.get_selected_items()
	var idx := 0
	if sel.size() > 0:
		idx = clampi(sel[0] + delta, 0, _eff_list.item_count - 1)
	_eff_list.select(idx)
	_eff_list.ensure_current_is_visible()
	_update_eff_buttons(true)


# ═══════════════════════════════════════════════════════════════════════
# GROUPS TAB
# ═══════════════════════════════════════════════════════════════════════

func _build_groups_page() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Top: group list ─────────────────────────────────────────────────
	var top := VBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 4)

	_grp_scroll = ScrollContainer.new()
	_grp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grp_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_scroll.custom_minimum_size = Vector2(0, 120)
	_grp_list_vbox = VBoxContainer.new()
	_grp_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_list_vbox.add_theme_constant_override("separation", 2)
	_grp_scroll.add_child(_grp_list_vbox)
	top.add_child(_grp_scroll)
	top.add_child(_spacer_v(4))

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	_grp_add_btn = Button.new()
	_grp_add_btn.tooltip_text = "Add new group (Enter)"
	_grp_add_btn.pressed.connect(_do_grp_add)
	_setup_plus_btn(_grp_add_btn)
	add_row.add_child(_grp_add_btn)
	_grp_label_field = LineEdit.new()
	_grp_label_field.placeholder_text = "GROUP_NAME"
	_grp_label_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_label_field.tooltip_text = "Group name"
	_grp_label_field.gui_input.connect(_on_grp_field_input)
	add_row.add_child(_grp_label_field)
	_grp_rename_btn = Button.new()
	_grp_rename_btn.text = "Replace"
	_grp_rename_btn.tooltip_text = "Replace selected group name with the text in the field (F2)"
	_grp_rename_btn.pressed.connect(_do_grp_rename)
	_grp_rename_btn.disabled = true
	add_row.add_child(_grp_rename_btn)
	_grp_remove_btn = Button.new()

	_grp_remove_btn.tooltip_text = "Remove selected group (Del)"
	_grp_remove_btn.pressed.connect(_do_grp_remove)
	_grp_remove_btn.disabled = true
	_setup_remove_btn(_grp_remove_btn)
	add_row.add_child(_grp_remove_btn)
	top.add_child(add_row)
	split.add_child(top)

	# ── Bottom: group effects ───────────────────────────────────────────
	_grp_effects_panel = VBoxContainer.new()
	_grp_effects_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grp_effects_panel.add_theme_constant_override("separation", 4)
	_grp_effects_panel.visible = false

	_grp_effects_title = Label.new()
	_grp_effects_title.text = "Effects in group"
	_grp_effects_title.add_theme_font_size_override("font_size", 13)
	_grp_effects_panel.add_child(_grp_effects_title)

	_grp_effects_list = ItemList.new()
	_grp_effects_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grp_effects_list.custom_minimum_size = Vector2(0, 80)
	_grp_effects_list.select_mode = ItemList.SELECT_SINGLE
	_grp_effects_list.item_selected.connect(func(_i): _grp_unassign_btn.disabled = false)
	_grp_effects_list.gui_input.connect(_on_grp_effects_list_input)
	_grp_effects_panel.add_child(_grp_effects_list)
	_grp_effects_panel.add_child(_spacer_v(4))

	var eff_row := HBoxContainer.new()
	eff_row.add_theme_constant_override("separation", 4)
	_grp_assign_btn = Button.new()
	_grp_assign_btn.text = "Assign"
	_grp_assign_btn.tooltip_text = "Add selected effect to this group"
	_grp_assign_btn.pressed.connect(_do_grp_assign)
	_style_add_btn(_grp_assign_btn)
	eff_row.add_child(_grp_assign_btn)
	_grp_effects_opt = OptionButton.new()
	_grp_effects_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_effects_opt.tooltip_text = "Select an effect to assign"
	eff_row.add_child(_grp_effects_opt)
	_grp_unassign_btn = Button.new()

	_grp_unassign_btn.tooltip_text = "Remove selected effect from this group (Del)"
	_grp_unassign_btn.pressed.connect(_do_grp_unassign)
	_grp_unassign_btn.disabled = true
	_setup_remove_btn(_grp_unassign_btn)
	eff_row.add_child(_grp_unassign_btn)
	_grp_effects_panel.add_child(eff_row)

	split.add_child(_grp_effects_panel)
	vbox.add_child(split)
	return vbox


func _refresh_groups() -> void:
	var prev_label: String = _grp_selected_label
	_grp_selected_label = ""
	_grp_row_btns.clear()
	_grp_color_pickers.clear()
	while _grp_list_vbox.get_child_count() > 0:
		var child := _grp_list_vbox.get_child(0)
		_grp_list_vbox.remove_child(child)
		child.queue_free()

	for g in _ctx.custom_groups:
		var lbl: String = g["label"]
		var clr: Color = _ctx.get_group_color(lbl)
		var row := _build_grp_row(lbl, clr)
		_grp_list_vbox.add_child(row)

	if prev_label != "" and _grp_row_btns.has(prev_label):
		_select_grp_by_label(prev_label)
	else:
		_grp_effects_panel.visible = false

	var has_sel := _grp_selected_label != ""
	_grp_rename_btn.disabled = not has_sel
	_grp_remove_btn.disabled = not has_sel


func _build_grp_row(label: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func(): _select_grp_by_label(label))
	btn.gui_input.connect(func(ev: InputEvent): _on_grp_row_input(ev, label))
	_style_grp_btn(btn, false)
	row.add_child(btn)
	_grp_row_btns[label] = btn

	var cpb := ColorPickerButton.new()
	cpb.color = color
	cpb.custom_minimum_size = Vector2(64, 28)
	cpb.tooltip_text = "Group color (used for node background and border)"
	cpb.color_changed.connect(func(c: Color): _on_grp_color_changed(label, c))
	row.add_child(cpb)
	_grp_color_pickers[label] = cpb

	return row


func _style_grp_btn(btn: Button, selected: bool) -> void:
	if selected:
		btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.18, 0.36, 0.60), 4))
		btn.add_theme_stylebox_override("hover",  _make_stylebox(Color(0.22, 0.42, 0.68), 4))
	else:
		btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.13, 0.13, 0.16), 4))
		btn.add_theme_stylebox_override("hover",  _make_stylebox(Color(0.20, 0.20, 0.26), 4))


func _get_grp_selected_label() -> String:
	return _grp_selected_label


func _select_grp_by_label(label: String) -> void:
	# Deselect previous
	if _grp_selected_label != "" and _grp_row_btns.has(_grp_selected_label):
		_style_grp_btn(_grp_row_btns[_grp_selected_label] as Button, false)
	_grp_selected_label = label
	# Highlight new selection
	if label != "" and _grp_row_btns.has(label):
		_style_grp_btn(_grp_row_btns[label] as Button, true)
	_on_grp_selected()


func _on_grp_selected() -> void:
	_grp_rename_btn.disabled = false
	_grp_remove_btn.disabled = false
	var label := _get_grp_selected_label()
	if label == "":
		_grp_effects_panel.visible = false
		return
	_grp_effects_panel.visible = true
	_grp_effects_title.text = "Effects in %s" % label
	_refresh_grp_effects(label)


func _refresh_grp_effects(label: String) -> void:
	_grp_effects_list.clear()
	for g in _ctx.custom_groups:
		if g["label"] == label:
			for ename in g.get("effects", PackedStringArray()):
				_grp_effects_list.add_item(ename)
			break
	_grp_effects_opt.clear()
	var assigned := PackedStringArray()
	for g in _ctx.custom_groups:
		if g["label"] == label:
			assigned = g.get("effects", PackedStringArray())
			break
	for ename in _ctx.custom_effects:
		if not assigned.has(ename):
			_grp_effects_opt.add_item(ename)
	_grp_unassign_btn.disabled = true


func _do_grp_add() -> void:
	var label := _sanitize(_grp_label_field.text)
	if label == "":
		return
	_ctx.add_group(label)
	_grp_label_field.clear()
	_refresh_groups()
	_select_grp_by_label(label)
	_grp_label_field.grab_focus()


func _do_grp_rename() -> void:
	if _grp_selected_label == "":
		return
	var old_label: String = _grp_selected_label
	var new_label := _sanitize(_grp_label_field.text)
	if new_label == "" or new_label == old_label:
		return
	_ctx.rename_group(old_label, new_label)
	_grp_label_field.clear()
	_refresh_groups()
	_select_grp_by_label(new_label)
	_grp_label_field.grab_focus()


func _do_grp_remove() -> void:
	var label := _get_grp_selected_label()
	if label == "":
		return
	_ctx.remove_group(label)
	_grp_effects_panel.visible = false
	_refresh_groups()


func _do_grp_assign() -> void:
	var label := _get_grp_selected_label()
	if label == "" or _grp_effects_opt.item_count == 0:
		return
	var ename: String = _grp_effects_opt.get_item_text(_grp_effects_opt.selected)
	_ctx.add_effect_to_group(label, ename)
	_refresh_grp_effects(label)


func _do_grp_unassign() -> void:
	var label := _get_grp_selected_label()
	if label == "":
		return
	var sel := _grp_effects_list.get_selected_items()
	if sel.size() == 0:
		return
	var ename: String = _grp_effects_list.get_item_text(sel[0])
	_ctx.remove_effect_from_group(label, ename)
	_refresh_grp_effects(label)


func _on_grp_field_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_do_grp_add()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			_do_grp_rename()
			get_viewport().set_input_as_handled()


func _on_grp_row_input(event: InputEvent, label: String) -> void:
	if event is InputEventKey and event.pressed:
		if _grp_selected_label != label:
			return
		if event.keycode == KEY_DELETE:
			_do_grp_remove()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			_grp_label_field.text = label
			_grp_label_field.grab_focus()
			_grp_label_field.select_all()
			get_viewport().set_input_as_handled()


func _on_grp_color_changed(label: String, color: Color) -> void:
	_ctx.set_group_color(label, color)


func _on_grp_effects_list_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			_do_grp_unassign()
			get_viewport().set_input_as_handled()


# ═══════════════════════════════════════════════════════════════════════
# SECONDARY UNLOCKS TAB
# ═══════════════════════════════════════════════════════════════════════

func _build_secondary_page() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	_sec_list = ItemList.new()
	_sec_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sec_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sec_list.select_mode = ItemList.SELECT_SINGLE
	_sec_list.allow_reselect = true
	_sec_list.custom_minimum_size = Vector2(0, 200)
	_sec_list.item_selected.connect(_on_sec_item_selected)
	_sec_list.gui_input.connect(_on_sec_list_input)
	vbox.add_child(_sec_list)
	vbox.add_child(_spacer_v(4))

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	_sec_add_btn = Button.new()
	_sec_add_btn.tooltip_text = "Add new unlock (Enter)"
	_sec_add_btn.pressed.connect(func(): _do_sec_add(_sec_field.text))
	_setup_plus_btn(_sec_add_btn)
	add_row.add_child(_sec_add_btn)
	_sec_field = LineEdit.new()
	_sec_field.placeholder_text = "Type unlock name, press Enter"
	_sec_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sec_field.gui_input.connect(_on_sec_field_input)
	add_row.add_child(_sec_field)
	_sec_rename_btn = Button.new()
	_sec_rename_btn.text = "Replace"
	_sec_rename_btn.tooltip_text = "Replace selected unlock with the text in the field (F2)"
	_sec_rename_btn.pressed.connect(_do_sec_rename)
	_sec_rename_btn.disabled = true
	add_row.add_child(_sec_rename_btn)
	_sec_remove_btn = Button.new()

	_sec_remove_btn.tooltip_text = "Remove selected unlock (Del)"
	_sec_remove_btn.pressed.connect(_do_sec_remove)
	_sec_remove_btn.disabled = true
	_setup_remove_btn(_sec_remove_btn)
	add_row.add_child(_sec_remove_btn)
	vbox.add_child(add_row)

	return vbox


func _refresh_secondary() -> void:
	var prev_sel := -1
	if _sec_list.get_selected_items().size() > 0:
		prev_sel = _sec_list.get_selected_items()[0]
	_sec_list.clear()
	for sname in _ctx.custom_secondary_unlocks:
		_sec_list.add_item(sname)
	if prev_sel >= 0 and prev_sel < _sec_list.item_count:
		_sec_list.select(prev_sel)
		_update_sec_buttons(true)
	else:
		_update_sec_buttons(false)


func _update_sec_buttons(has_sel: bool) -> void:
	_sec_rename_btn.disabled = not has_sel
	_sec_remove_btn.disabled = not has_sel


func _on_sec_item_selected(_index: int) -> void:
	_update_sec_buttons(true)


func _do_sec_add(text: String) -> void:
	var clean := _sanitize(text)
	if clean == "":
		return
	if _ctx.custom_secondary_unlocks.has(clean):
		_sec_field.clear()
		return
	_ctx.add_secondary_unlock(clean)
	_sec_field.clear()
	_refresh_secondary()
	for i in range(_sec_list.item_count):
		if _sec_list.get_item_text(i) == clean:
			_sec_list.select(i)
			_sec_list.ensure_current_is_visible()
			_update_sec_buttons(true)
			break
	_sec_field.call_deferred("grab_focus")


func _do_sec_rename() -> void:
	var sel := _sec_list.get_selected_items()
	if sel.size() == 0:
		return
	var old_name: String = _sec_list.get_item_text(sel[0])
	var new_name := _sanitize(_sec_field.text)
	if new_name == "" or new_name == old_name:
		return
	_ctx.rename_secondary_unlock(old_name, new_name)
	_sec_field.clear()
	_refresh_secondary()
	for i in range(_sec_list.item_count):
		if _sec_list.get_item_text(i) == new_name:
			_sec_list.select(i)
			_sec_list.ensure_current_is_visible()
			break
	_sec_field.call_deferred("grab_focus")


func _do_sec_remove() -> void:
	var sel := _sec_list.get_selected_items()
	if sel.size() == 0:
		return
	var sname: String = _sec_list.get_item_text(sel[0])
	_ctx.remove_secondary_unlock(sname)
	_refresh_secondary()


func _on_sec_list_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			_do_sec_remove()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			var sel := _sec_list.get_selected_items()
			if sel.size() > 0:
				_sec_field.text = _sec_list.get_item_text(sel[0])
				_sec_field.grab_focus()
				_sec_field.select_all()
			get_viewport().set_input_as_handled()


func _on_sec_field_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_do_sec_add(_sec_field.text)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			_do_sec_rename()
			get_viewport().set_input_as_handled()
		elif _sec_field.text.strip_edges() == "":
			if event.keycode == KEY_UP:
				_move_sec_selection(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_move_sec_selection(1)
				get_viewport().set_input_as_handled()


func _move_sec_selection(delta: int) -> void:
	if _sec_list.item_count == 0:
		return
	var sel := _sec_list.get_selected_items()
	var idx := 0
	if sel.size() > 0:
		idx = clampi(sel[0] + delta, 0, _sec_list.item_count - 1)
	_sec_list.select(idx)
	_sec_list.ensure_current_is_visible()
	_update_sec_buttons(true)
