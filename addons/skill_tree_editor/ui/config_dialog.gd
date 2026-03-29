## Tabbed dialog for configuring effects and groups.
##
## Effects tab: flat list with rapid keyboard add/rename/remove.
## Groups tab: tree with flag/label columns + effect assignment sub-panel.
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

# ── Groups tab refs ─────────────────────────────────────────────────────
var _grp_tree: Tree
var _grp_flag_field: LineEdit
var _grp_label_field: LineEdit
var _grp_add_btn: Button
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
	about_to_popup.connect(_on_about_to_popup)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Tab bar
	_tabs = TabBar.new()
	_tabs.add_tab("Effects")
	_tabs.add_tab("Groups")
	_tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(_tabs)

	# Pages
	var eff_page := _build_effects_page()
	root.add_child(eff_page)
	_pages.append(eff_page)

	var grp_page := _build_groups_page()
	grp_page.visible = false
	root.add_child(grp_page)
	_pages.append(grp_page)

	add_child(root)


func _on_tab_changed(idx: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = (i == idx)
	if idx == 0:
		_refresh_effects()
		_eff_field.call_deferred("grab_focus")
	elif idx == 1:
		_refresh_groups()
		_grp_flag_field.call_deferred("grab_focus")


func _on_about_to_popup() -> void:
	_tabs.current_tab = 0
	_on_tab_changed(0)


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

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	_eff_field = LineEdit.new()
	_eff_field.placeholder_text = "Type effect name, press Enter"
	_eff_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eff_field.text_submitted.connect(_on_eff_add_submitted)
	_eff_field.gui_input.connect(_on_eff_field_input)
	add_row.add_child(_eff_field)
	_eff_add_btn = Button.new()
	_eff_add_btn.text = "Add"
	_eff_add_btn.pressed.connect(func(): _do_eff_add(_eff_field.text))
	add_row.add_child(_eff_add_btn)
	vbox.add_child(add_row)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	_eff_rename_btn = Button.new()
	_eff_rename_btn.text = "Rename (F2)"
	_eff_rename_btn.tooltip_text = "Rename selected effect to the text in the field above"
	_eff_rename_btn.pressed.connect(_do_eff_rename)
	_eff_rename_btn.disabled = true
	action_row.add_child(_eff_rename_btn)
	_eff_remove_btn = Button.new()
	_eff_remove_btn.text = "Remove (Del)"
	_eff_remove_btn.tooltip_text = "Remove selected effect (nodes using it reset to NONE)"
	_eff_remove_btn.pressed.connect(_do_eff_remove)
	_eff_remove_btn.disabled = true
	action_row.add_child(_eff_remove_btn)
	vbox.add_child(action_row)

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


func _on_eff_add_submitted(text: String) -> void:
	_do_eff_add(text)


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
	_eff_field.grab_focus()


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
	_eff_field.grab_focus()


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
		if event.keycode == KEY_F2:
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

	var top_label := Label.new()
	top_label.text = "Groups"
	top_label.add_theme_font_size_override("font_size", 13)
	top.add_child(top_label)

	_grp_tree = Tree.new()
	_grp_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grp_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_tree.custom_minimum_size = Vector2(0, 120)
	_grp_tree.columns = 2
	_grp_tree.set_column_title(0, "Flag")
	_grp_tree.set_column_title(1, "Label")
	_grp_tree.column_titles_visible = true
	_grp_tree.set_column_expand(0, false)
	_grp_tree.set_column_custom_minimum_width(0, 70)
	_grp_tree.set_column_expand(1, true)
	_grp_tree.hide_root = true
	_grp_tree.item_selected.connect(_on_grp_selected)
	_grp_tree.item_edited.connect(_on_grp_tree_edited)
	_grp_tree.gui_input.connect(_on_grp_tree_input)
	top.add_child(_grp_tree)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	_grp_flag_field = LineEdit.new()
	_grp_flag_field.placeholder_text = "-x"
	_grp_flag_field.custom_minimum_size = Vector2(60, 0)
	_grp_flag_field.max_length = 4
	_grp_flag_field.tooltip_text = "Short flag prefix (e.g. -e, -c)"
	add_row.add_child(_grp_flag_field)
	_grp_label_field = LineEdit.new()
	_grp_label_field.placeholder_text = "GROUP_NAME"
	_grp_label_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_label_field.tooltip_text = "Group display name"
	_grp_label_field.text_submitted.connect(func(_t): _do_grp_add())
	add_row.add_child(_grp_label_field)
	_grp_add_btn = Button.new()
	_grp_add_btn.text = "Add"
	_grp_add_btn.pressed.connect(_do_grp_add)
	add_row.add_child(_grp_add_btn)
	_grp_remove_btn = Button.new()
	_grp_remove_btn.text = "Remove (Del)"
	_grp_remove_btn.tooltip_text = "Remove selected group"
	_grp_remove_btn.pressed.connect(_do_grp_remove)
	_grp_remove_btn.disabled = true
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

	var eff_row := HBoxContainer.new()
	eff_row.add_theme_constant_override("separation", 4)
	_grp_effects_opt = OptionButton.new()
	_grp_effects_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grp_effects_opt.tooltip_text = "Select an effect to assign"
	eff_row.add_child(_grp_effects_opt)
	_grp_assign_btn = Button.new()
	_grp_assign_btn.text = "Assign"
	_grp_assign_btn.tooltip_text = "Add selected effect to this group"
	_grp_assign_btn.pressed.connect(_do_grp_assign)
	eff_row.add_child(_grp_assign_btn)
	_grp_unassign_btn = Button.new()
	_grp_unassign_btn.text = "Unassign (Del)"
	_grp_unassign_btn.tooltip_text = "Remove selected effect from this group"
	_grp_unassign_btn.pressed.connect(_do_grp_unassign)
	_grp_unassign_btn.disabled = true
	eff_row.add_child(_grp_unassign_btn)
	_grp_effects_panel.add_child(eff_row)

	split.add_child(_grp_effects_panel)
	vbox.add_child(split)
	return vbox


func _refresh_groups() -> void:
	var prev_flag := _get_grp_selected_flag()
	_grp_tree.clear()
	var root := _grp_tree.create_item()
	for g in _ctx.custom_groups:
		var item := _grp_tree.create_item(root)
		item.set_text(0, g["flag"])
		item.set_text(1, g["label"])
		item.set_editable(0, true)
		item.set_editable(1, true)
		item.set_metadata(0, g["flag"])
	if prev_flag != "":
		_select_grp_by_flag(prev_flag)
	_grp_remove_btn.disabled = (_grp_tree.get_selected() == null)


func _get_grp_selected_flag() -> String:
	var sel := _grp_tree.get_selected()
	if sel:
		return sel.get_metadata(0)
	return ""


func _select_grp_by_flag(flag: String) -> void:
	var root := _grp_tree.get_root()
	if not root:
		return
	var child := root.get_first_child()
	while child:
		if child.get_metadata(0) == flag:
			child.select(0)
			_on_grp_selected()
			return
		child = child.get_next()


func _on_grp_selected() -> void:
	_grp_remove_btn.disabled = false
	var flag := _get_grp_selected_flag()
	if flag == "":
		_grp_effects_panel.visible = false
		return
	_grp_effects_panel.visible = true
	for g in _ctx.custom_groups:
		if g["flag"] == flag:
			_grp_effects_title.text = "Effects in %s" % g["label"]
			break
	_refresh_grp_effects(flag)


func _refresh_grp_effects(flag: String) -> void:
	_grp_effects_list.clear()
	for g in _ctx.custom_groups:
		if g["flag"] == flag:
			for ename in g.get("effects", PackedStringArray()):
				_grp_effects_list.add_item(ename)
			break
	_grp_effects_opt.clear()
	var assigned := PackedStringArray()
	for g in _ctx.custom_groups:
		if g["flag"] == flag:
			assigned = g.get("effects", PackedStringArray())
			break
	for ename in _ctx.custom_effects:
		if not assigned.has(ename):
			_grp_effects_opt.add_item(ename)
	_grp_unassign_btn.disabled = true


func _on_grp_tree_edited() -> void:
	var item := _grp_tree.get_edited()
	if not item:
		return
	var col := _grp_tree.get_edited_column()
	var old_flag: String = item.get_metadata(0)
	if col == 0:
		var new_flag := item.get_text(0).strip_edges()
		if not new_flag.begins_with("-") and new_flag != "":
			new_flag = "-" + new_flag
		if new_flag != old_flag and new_flag != "":
			_ctx.update_group_flag(old_flag, new_flag)
			item.set_metadata(0, new_flag)
		else:
			item.set_text(0, old_flag)
	elif col == 1:
		var new_label := item.get_text(1).strip_edges().to_upper().replace(" ", "_")
		_ctx.update_group(_get_grp_selected_flag(), new_label)
		item.set_text(1, new_label)
		if _grp_effects_panel.visible:
			_grp_effects_title.text = "Effects in %s" % new_label


func _do_grp_add() -> void:
	var flag := _grp_flag_field.text.strip_edges()
	var label := _grp_label_field.text.strip_edges().to_upper().replace(" ", "_")
	if flag == "" or label == "":
		return
	if not flag.begins_with("-"):
		flag = "-" + flag
	_ctx.add_group(flag, label)
	_grp_flag_field.clear()
	_grp_label_field.clear()
	_refresh_groups()
	_select_grp_by_flag(flag)
	_grp_flag_field.grab_focus()


func _do_grp_remove() -> void:
	var flag := _get_grp_selected_flag()
	if flag == "":
		return
	_ctx.remove_group(flag)
	_grp_effects_panel.visible = false
	_refresh_groups()


func _do_grp_assign() -> void:
	var flag := _get_grp_selected_flag()
	if flag == "" or _grp_effects_opt.item_count == 0:
		return
	var ename: String = _grp_effects_opt.get_item_text(_grp_effects_opt.selected)
	_ctx.add_effect_to_group(flag, ename)
	_refresh_grp_effects(flag)


func _do_grp_unassign() -> void:
	var flag := _get_grp_selected_flag()
	if flag == "":
		return
	var sel := _grp_effects_list.get_selected_items()
	if sel.size() == 0:
		return
	var ename: String = _grp_effects_list.get_item_text(sel[0])
	_ctx.remove_effect_from_group(flag, ename)
	_refresh_grp_effects(flag)


func _on_grp_tree_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			_do_grp_remove()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			var sel := _grp_tree.get_selected()
			if sel:
				_grp_tree.edit_selected(true)
			get_viewport().set_input_as_handled()


func _on_grp_effects_list_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			_do_grp_unassign()
			get_viewport().set_input_as_handled()
