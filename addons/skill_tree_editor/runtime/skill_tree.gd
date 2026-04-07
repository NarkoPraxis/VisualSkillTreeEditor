## In-game Skill Tree — plug-and-play runtime canvas.
##
## Drop skill_tree.tscn into your scene, point skill_config at the JSON
## exported by the Skill Tree Editor, and click [Generate Tree] in the
## Inspector.  Child SkillNode instances are created and saved into the
## scene file so the layout persists.  At runtime the tree loads the same
## JSON, wires up the pre-placed nodes, and handles zoom / pan / purchase.
##
## Developer integration:
##   • Connect skill_purchased(id, data) to deduct currency / apply effects.
##   • Call save_state() / load_state() for session persistence.
##   • Call reset_all() to zero every purchased count.
##
## Canvas architecture:
##   SkillTree (Control, full-rect anchor)
##     SkillNode children  (unlocked nodes only, visible when available)
##     _tooltip  (PanelContainer, z=10)  ← hover description
@tool
extends Control
class_name SkillTree

const SkillNodeScript       = preload("res://addons/skill_tree_editor/runtime/skill_node.gd")
const SkillTreeDataScript   = preload("res://addons/skill_tree_editor/runtime/skill_tree_data.gd")

# ── Constants ─────────────────────────────────────────────────────────────

const NODE_W := 180.0
const NODE_H := 82.0
const ZOOM_MIN  := 0.12
const ZOOM_MAX  := 4.0
const ZOOM_STEP := 0.10

const CANVAS_BG := Color(0.06, 0.09, 0.16)

# ── Exports ───────────────────────────────────────────────────────────────

## Path to the JSON file exported by the Skill Tree Editor.
@export_file("*.json") var skill_config: String = ""

## Click in the Inspector to create SkillNode children from skill_config.
@export_tool_button("Generate Tree") var _gen_btn: Callable = _generate

## Initial camera offset saved by Generate — do not edit manually.
@export var _initial_cam_off: Vector2 = Vector2.ZERO
## Initial camera zoom saved by Generate — do not edit manually.
@export var _initial_cam_zoom: float = 1.0

# ── Signal ────────────────────────────────────────────────────────────────

## Emitted after a skill is successfully purchased.
## skill_data is a snapshot of the node dictionary at the moment of purchase.
signal skill_purchased(skill_id: String, skill_data: Dictionary)

# ── Camera state ──────────────────────────────────────────────────────────

var _cam_off: Vector2  = Vector2.ZERO
var _cam_zoom: float   = 1.0

# ── Internal ──────────────────────────────────────────────────────────────

var _data: RefCounted          # SkillTreeData
var _cards: Dictionary = {}    # id → SkillNode
var _world_positions: Dictionary = {}  # id → Vector2 world pos (source of truth for transforms)
var _tooltip: PanelContainer
var _tooltip_name: Label
var _tooltip_body: Label

var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_off: Vector2 = Vector2.ZERO
var _hovered_id: String = ""


# ── Lifecycle ─────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), CANVAS_BG, true)


func _ready() -> void:
	clip_contents = true
	_build_canvas()
	_build_tooltip()

	if Engine.is_editor_hint():
		_cam_off  = _initial_cam_off
		_cam_zoom = _initial_cam_zoom
		if not skill_config.is_empty():
			var data: RefCounted = SkillTreeDataScript.new()
			if (data as SkillTreeData).load_from_file(skill_config) == OK:
				_data = data
		for child in get_children():
			if child.has_meta("skill_node_id"):
				var id: String = str(child.get_meta("skill_node_id"))
				_cards[id] = child
		_update_all_card_transforms()
	else:
		if skill_config.is_empty():
			_show_placeholder("Set 'skill_config' in the Inspector, then click Generate Tree.")
		else:
			_load_and_wire()


func _load_and_wire() -> void:
	## Runtime startup: loads JSON data, wires pre-generated scene children, and
	## applies the saved camera state.  Never spawns new nodes at runtime —
	## layout always comes from the editor-generated scene file.
	var data: RefCounted = SkillTreeDataScript.new()
	var err: Error = (data as SkillTreeData).load_from_file(skill_config)
	if err != OK:
		push_error("SkillTree: failed to load '%s' (error %d)" % [skill_config, err])
		_show_placeholder("Failed to load skill tree JSON. Check the skill_config path.")
		return
	_data = data
	(data as SkillTreeData).state_changed.connect(_on_data_state_changed)

	# Restore the camera state saved when Generate Tree was last run.
	# We need this before back-calculating world positions below.
	_cam_off  = _initial_cam_off
	_cam_zoom = _initial_cam_zoom

	# Find pre-generated children (placed by _generate() in editor) and wire them up.
	# World positions are back-calculated from the scene-saved screen positions so that
	# any manual repositioning done in the editor is respected at runtime.
	for child in get_children():
		if not child.has_meta("skill_node_id"):
			continue
		var id: String = str(child.get_meta("skill_node_id"))
		if not (data as SkillTreeData).nodes.has(id):
			continue
		var sn: SkillNode = child as SkillNode
		if sn == null:
			continue
		# Derive world pos from the scene position + initial camera (not from JSON).
		_world_positions[id] = _s2w(sn.position)
		# UI was already built by SkillNode._ready() from exported data —
		# only wire signals here, never call setup() at runtime.
		sn.buy_pressed.connect(_on_buy_pressed)
		sn.node_hovered.connect(_on_node_hovered)
		sn.node_unhovered.connect(_on_node_unhovered)
		_cards[id] = sn

	if _cards.is_empty():
		push_warning("SkillTree: no pre-generated nodes found. Open the scene in the editor and click 'Generate Tree' in the Inspector.")

	_update_all_card_transforms()
	_refresh_all_nodes()


func _generate() -> void:
	## Inspector button handler.  Clears and recreates all child SkillNodes from
	## the JSON, then deferred-fits the view and saves camera state.
	if not Engine.is_editor_hint():
		return
	if skill_config.is_empty():
		push_error("SkillTree: skill_config is not set.")
		return

	# Clear previously generated children
	for child in get_children():
		if child.has_meta("skill_node_id"):
			child.free()
	_cards.clear()

	# Load fresh data
	var data: RefCounted = SkillTreeDataScript.new()
	var err: Error = (data as SkillTreeData).load_from_file(skill_config)
	if err != OK:
		push_error("SkillTree: failed to load '%s' (error %d)" % [skill_config, err])
		return
	_data = data

	_spawn_nodes()
	call_deferred("_fit_and_save_cam")
	print("SkillTree: generated %d nodes from '%s'." % [(data as SkillTreeData).nodes.size(), skill_config])


func _spawn_nodes() -> void:
	## Creates one SkillNode child per entry in _data.nodes (editor only).
	## Nodes are assigned to the scene root so they are saved with the scene.
	var root: Node = null
	if is_inside_tree():
		root = get_tree().edited_scene_root
	for id in (_data as SkillTreeData).nodes:
		var node_data: Dictionary = (_data as SkillTreeData).nodes[id]
		var sn: SkillNode = SkillNodeScript.new() as SkillNode
		sn.name = id
		sn.set_meta("skill_node_id", id)
		sn.position = node_data["position"] as Vector2
		add_child(sn)
		if root != null:
			sn.owner = root
		sn.setup(id, node_data)
		_world_positions[id] = node_data["position"] as Vector2
		_cards[id] = sn


# ── Canvas construction ───────────────────────────────────────────────────

func _build_canvas() -> void:
	resized.connect(queue_redraw)


func _build_tooltip() -> void:
	var sty := StyleBoxFlat.new()
	sty.set_corner_radius_all(6)
	sty.bg_color = Color(0.08, 0.10, 0.18, 0.96)
	sty.border_color = Color(0.40, 0.55, 0.80, 0.70)
	sty.set_border_width_all(1)
	sty.set_content_margin_all(10)

	_tooltip = PanelContainer.new()
	_tooltip.add_theme_stylebox_override("panel", sty)
	_tooltip.custom_minimum_size = Vector2(200, 0)
	_tooltip.visible = false
	_tooltip.mouse_filter = MOUSE_FILTER_IGNORE
	_tooltip.z_index = 10

	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	_tooltip.add_child(vb)

	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 14)
	_tooltip_name.mouse_filter = MOUSE_FILTER_IGNORE
	_tooltip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_tooltip_name)

	_tooltip_body = Label.new()
	_tooltip_body.add_theme_font_size_override("font_size", 11)
	_tooltip_body.add_theme_color_override("font_color", Color(0.80, 0.82, 0.90))
	_tooltip_body.mouse_filter = MOUSE_FILTER_IGNORE
	_tooltip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_tooltip_body)

	add_child(_tooltip)


func _show_placeholder(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80, 0.75))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.set_anchors_preset(PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(300, 0)
	add_child(lbl)


# ── Coordinate transforms ─────────────────────────────────────────────────

func _w2s(wp: Vector2) -> Vector2:
	return wp * _cam_zoom + _cam_off


func _s2w(sp: Vector2) -> Vector2:
	return (sp - _cam_off) / _cam_zoom


# ── Camera ────────────────────────────────────────────────────────────────

func _zoom_at(screen_pt: Vector2, delta: float) -> void:
	var old := _cam_zoom
	_cam_zoom = clampf(_cam_zoom + delta, ZOOM_MIN, ZOOM_MAX)
	var r := _cam_zoom / old
	_cam_off = screen_pt - (screen_pt - _cam_off) * r
	_apply_transform()


func _apply_transform() -> void:
	_update_all_card_transforms()


func _update_all_card_transforms() -> void:
	for id in _cards:
		var sn: Node = _cards[id]
		if not is_instance_valid(sn):
			continue
		var world_pos: Vector2
		if _world_positions.has(id):
			# Runtime: use positions derived from the scene file (respects manual moves).
			world_pos = _world_positions[id]
		elif _data != null and (_data as SkillTreeData).nodes.has(id):
			# Editor fallback: use JSON positions.
			world_pos = (_data as SkillTreeData).nodes[id]["position"] as Vector2
		else:
			continue
		sn.position = _w2s(world_pos)
		sn.scale = Vector2(_cam_zoom, _cam_zoom)


func _fit_view() -> void:
	## Adjusts camera so the entire tree is visible with a small margin.
	if _data == null or (_data as SkillTreeData).nodes.is_empty():
		return
	var canvas_sz: Vector2 = size if size.x > 10.0 else Vector2(800.0, 600.0)
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for id in (_data as SkillTreeData).nodes:
		var pos: Vector2 = (_data as SkillTreeData).nodes[id]["position"] as Vector2
		bmin = Vector2(minf(bmin.x, pos.x), minf(bmin.y, pos.y))
		bmax = Vector2(maxf(bmax.x, pos.x + NODE_W), maxf(bmax.y, pos.y + NODE_H))
	var margin := 64.0
	var content: Vector2 = bmax - bmin
	var scale_x: float = (canvas_sz.x - margin * 2.0) / maxf(content.x, 1.0)
	var scale_y: float = (canvas_sz.y - margin * 2.0) / maxf(content.y, 1.0)
	_cam_zoom = clampf(minf(scale_x, scale_y), ZOOM_MIN, ZOOM_MAX)
	var center: Vector2 = (bmin + bmax) * 0.5
	_cam_off = canvas_sz * 0.5 - center * _cam_zoom
	_apply_transform()


func _fit_and_save_cam() -> void:
	## Fit view and persist camera state into @export vars so the scene saves it.
	_fit_view()
	_initial_cam_off  = _cam_off
	_initial_cam_zoom = _cam_zoom
	_update_all_card_transforms()


# ── Input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not get_global_rect().has_point(get_global_mouse_position()):
		if not _panning:
			return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)


func _on_mouse_button(ev: InputEventMouseButton) -> void:
	var sp: Vector2 = ev.global_position - global_position
	if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(sp, ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(sp, -ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	# Middle mouse or right mouse drag for panning
	if ev.button_index == MOUSE_BUTTON_MIDDLE or ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.pressed and get_global_rect().has_point(ev.global_position):
			_panning = true
			_pan_start_mouse = ev.global_position
			_pan_start_off = _cam_off
			get_viewport().set_input_as_handled()
		elif not ev.pressed:
			_panning = false


func _on_mouse_motion(ev: InputEventMouseMotion) -> void:
	if _panning:
		_cam_off = _pan_start_off + (ev.global_position - _pan_start_mouse)
		_apply_transform()
		get_viewport().set_input_as_handled()


# ── Purchase handling ─────────────────────────────────────────────────────

func _on_buy_pressed(id: String) -> void:
	if _data == null:
		return
	if not (_data as SkillTreeData).can_purchase(id):
		return
	var current: int = (_data as SkillTreeData).nodes[id].get("purchased", 0)
	(_data as SkillTreeData).set_purchased(id, current + 1)
	skill_purchased.emit(id, (_data as SkillTreeData).nodes[id].duplicate())


func _on_data_state_changed() -> void:
	_refresh_all_nodes()


func _refresh_all_nodes() -> void:
	if _data == null:
		return
	for id in _cards:
		var sn = _cards[id]
		if not is_instance_valid(sn):
			continue
		var node: Dictionary = (_data as SkillTreeData).nodes.get(id, {})
		if node.is_empty():
			continue
		var purchased: int = node.get("purchased", 0)
		var locked: bool   = (_data as SkillTreeData).is_locked(id)
		var maxed: bool    = (_data as SkillTreeData).is_maxed(id)
		var rk_maxed: bool = maxed and (_data as SkillTreeData).is_rank_up_child(id)
		sn.visible = not locked
		(sn as SkillNode).refresh_state(purchased, maxed, rk_maxed)


# ── Tooltip ───────────────────────────────────────────────────────────────

func _on_node_hovered(id: String) -> void:
	_hovered_id = id
	if _data == null or not (_data as SkillTreeData).nodes.has(id):
		return
	var node: Dictionary = (_data as SkillTreeData).nodes[id]
	_tooltip_name.text = node.get("name", "")

	var lines: PackedStringArray = []
	var desc: String = node.get("description", "")
	if desc != "":
		lines.append(desc)

	var cost: int = (_data as SkillTreeData).get_current_cost(id)
	var inc: int  = node.get("cost_increase", 0)
	var base: int = node.get("cost", 0)
	if inc == 0:
		lines.append("Cost: $%d" % cost)
	elif node.get("exponential", false):
		lines.append("Cost: $%d (×%d%% per rank)" % [cost, inc])
	else:
		lines.append("Cost: $%d (+$%d per rank)" % [cost, inc])

	var effect: String = node.get("effect", "NONE")
	if effect != "NONE" and effect != "":
		var val: float = node.get("value", 0.0)
		lines.append("Effect: %s  +%.4g" % [effect, val])

	var up: int = node.get("unlocks_on_purchase", 0)
	var um: int = node.get("unlocks_on_max", 0)
	var rk: bool = node.get("has_rank_up_child", false)
	if up > 0:
		lines.append("Unlocks %d skill(s) on purchase" % up)
	if um > 0:
		lines.append("Unlocks %d skill(s) when maxed" % um)
	if rk:
		lines.append("Rank-up chain")

	var sec: String = node.get("secondary_unlock", "")
	if sec != "" and sec != "NONE":
		lines.append("Unlock: %s" % sec)

	_tooltip_body.text = "\n".join(lines)

	# Position tooltip near the card, flipped if it would go off-screen
	var sn: Node = _cards.get(id)
	if not is_instance_valid(sn):
		return
	_tooltip.visible = true
	_tooltip.reset_size()
	await get_tree().process_frame  # wait one frame for tooltip to measure itself

	# Guard: hide if mouse moved away during the await
	if _hovered_id != id or not is_instance_valid(sn) or not is_instance_valid(_tooltip):
		return

	var card_pos: Vector2 = sn.position
	var card_h: float = NODE_H * _cam_zoom
	var card_w: float = NODE_W * _cam_zoom
	var tip_sz: Vector2 = _tooltip.size
	var canvas_sz: Vector2 = size

	var tx: float = card_pos.x
	var ty: float = card_pos.y + card_h + 6.0

	# Flip above if below would clip bottom
	if ty + tip_sz.y > canvas_sz.y - 4.0:
		ty = card_pos.y - tip_sz.y - 6.0

	# Clamp horizontally
	tx = clampf(tx, 4.0, canvas_sz.x - tip_sz.x - 4.0)
	# Clamp vertically
	ty = clampf(ty, 4.0, canvas_sz.y - tip_sz.y - 4.0)

	# If tooltip is wider than card, center it horizontally on the card
	if tip_sz.x > card_w:
		tx = clampf(card_pos.x + card_w * 0.5 - tip_sz.x * 0.5, 4.0, canvas_sz.x - tip_sz.x - 4.0)

	_tooltip.position = Vector2(tx, ty)


func _on_node_unhovered(_id: String) -> void:
	_hovered_id = ""
	if is_instance_valid(_tooltip):
		_tooltip.visible = false


# ── Public API ────────────────────────────────────────────────────────────

func save_state() -> Dictionary:
	## Returns {node_id: purchased_count} for all nodes.
	## Persist this between sessions and restore with load_state().
	if _data == null:
		return {}
	return (_data as SkillTreeData).save_state()


func load_state(state: Dictionary) -> void:
	## Restores purchased counts from a previously saved dictionary.
	if _data == null:
		return
	(_data as SkillTreeData).load_state(state)


func reset_all() -> void:
	## Zeros every skill's purchased count and refreshes the UI.
	if _data == null:
		return
	for id in (_data as SkillTreeData).nodes:
		(_data as SkillTreeData).nodes[id]["purchased"] = 0
	(_data as SkillTreeData).state_changed.emit()
