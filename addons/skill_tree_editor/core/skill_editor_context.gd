## Shared context for the Skill Tree Editor plugin.
##
## Owns all skill-tree data (nodes + connections), selection state, editor mode,
## and serialisation.  Both the canvas and the dock depend on this object —
## neither holds a direct reference to the other.
##
## Effects and groups are fully configurable. They are stored in the JSON config
## file alongside nodes and connections, so each project can define its own
## effect types and group categories. A default set of incremental-game effects
## is provided when creating a new tree.
@tool
extends RefCounted

# ── Signals ──────────────────────────────────────────────────────────────

signal skill_selected(skill_id: String)
signal skill_deselected()
signal data_changed()
signal mode_changed(new_mode: int)
signal arrow_type_changed(new_type: int)
signal rank_up_mode_changed(active: bool)
signal connection_rejected(node_id: String)

# ── Enums ────────────────────────────────────────────────────────────────

enum Mode { CREATE, DELETE }
enum ArrowType { MAXED, PURCHASED, RANK_UP }

# ── Selection & mode state ───────────────────────────────────────────────

var selected_skill_id: String = "":
	set(value):
		if selected_skill_id == value:
			return
		selected_skill_id = value
		if value == "":
			skill_deselected.emit()
		else:
			skill_selected.emit(value)

var selected_connection_index: int = -1

var current_mode: int = Mode.CREATE:
	set(value):
		current_mode = value
		mode_changed.emit(value)

var current_arrow_type: int = ArrowType.PURCHASED:
	set(value):
		current_arrow_type = value
		arrow_type_changed.emit(value)

var rank_up_mode: bool = false:
	set(value):
		rank_up_mode = value
		rank_up_mode_changed.emit(value)

# ── Persistence ──────────────────────────────────────────────────────────

var current_file_path: String = ""
var last_saved_data: Dictionary = {}

# ── Tree data ────────────────────────────────────────────────────────────

## id → { name, cost, cost_increase, exponential, max, description, effect,
##         value, position:Vector2, emoticon, image,
##         unlocks_on_purchase, unlocks_on_max, has_rank_up_child,
##         group, purchased, secondary_unlock }
var nodes: Dictionary = {}

## Array of { from:String, to:String, type:String("maxed"|"purchased"|"rank_up") }
var connections: Array = []

var _next_id: int = 0

# ── User-configurable effects and groups ─────────────────────────────────

## Array of effect name strings, e.g. ["NONE", "DAMAGE", "HEALTH", ...]
var custom_effects: PackedStringArray = []

## Array of { flag:String, label:String, effects:PackedStringArray }
var custom_groups: Array = []

## Array of secondary unlock name strings, e.g. ["NONE", "A", "B", ...]
var custom_secondary_unlocks: PackedStringArray = []


func _init() -> void:
	_load_defaults()


func _load_defaults() -> void:
	custom_effects = PackedStringArray([
		"NONE",
		"MONEY_GAIN", "MONEY_MULTIPLIER", "CLICK_POWER", "CLICK_MULTIPLIER",
		"AUTO_CLICK", "OBJECT_SIZE", "OBJECT_SPEED",
		"CRIT_RATE", "CRIT_DAMAGE", "CHAIN_LIGHTNING", "COMBO_BONUS",
		"AREA_OF_EFFECT", "PROJECTILE_COUNT", "PROJECTILE_SPEED",
		"PRESTIGE_BONUS", "PRESTIGE_MULTIPLIER",
		"OFFLINE_EARNINGS", "IDLE_SPEED",
		"SPAWN_RATE", "SPAWN_AMOUNT", "MERGE_SPEED", "MERGE_VALUE",
		"DROP_RATE", "DROP_QUALITY",
		"EXPERIENCE_GAIN", "LEVEL_SPEED", "COOLDOWN_REDUCTION",
		"DURATION_BONUS", "UPGRADE_DISCOUNT", "UNLOCK_SPEED",
		"CUSTOM_1", "CUSTOM_2", "CUSTOM_3", "CUSTOM_4", "CUSTOM_5",
	])
	custom_groups = [
		{"flag": "-e", "label": "ECONOMY", "effects": PackedStringArray([
			"MONEY_GAIN", "MONEY_MULTIPLIER", "CLICK_POWER", "CLICK_MULTIPLIER",
			"PRESTIGE_BONUS", "PRESTIGE_MULTIPLIER"])},
		{"flag": "-c", "label": "COMBAT", "effects": PackedStringArray([
			"CRIT_RATE", "CRIT_DAMAGE", "CHAIN_LIGHTNING", "COMBO_BONUS",
			"AREA_OF_EFFECT", "PROJECTILE_COUNT", "PROJECTILE_SPEED"])},
		{"flag": "-p", "label": "PRODUCTION", "effects": PackedStringArray([
			"AUTO_CLICK", "IDLE_SPEED", "SPAWN_RATE", "SPAWN_AMOUNT",
			"MERGE_SPEED", "MERGE_VALUE"])},
		{"flag": "-r", "label": "PROGRESSION", "effects": PackedStringArray([
			"EXPERIENCE_GAIN", "LEVEL_SPEED", "UNLOCK_SPEED",
			"UPGRADE_DISCOUNT", "COOLDOWN_REDUCTION", "DURATION_BONUS"])},
		{"flag": "-d", "label": "DROP", "effects": PackedStringArray([
			"DROP_RATE", "DROP_QUALITY", "OFFLINE_EARNINGS"])},
		{"flag": "-x", "label": "CUSTOM", "effects": PackedStringArray([
			"CUSTOM_1", "CUSTOM_2", "CUSTOM_3", "CUSTOM_4", "CUSTOM_5"])},
	]
	custom_secondary_unlocks = PackedStringArray(["NONE"])


# ── Node helpers ─────────────────────────────────────────────────────────

func generate_id() -> String:
	_next_id += 1
	return "node_%d" % _next_id


func add_node(id: String, data: Dictionary) -> void:
	nodes[id] = data
	data_changed.emit()


func remove_node(id: String) -> void:
	nodes.erase(id)
	connections = connections.filter(func(c): return c["from"] != id and c["to"] != id)
	if selected_skill_id == id:
		selected_skill_id = ""
	if selected_connection_index >= 0:
		selected_connection_index = -1
	data_changed.emit()


func update_node(id: String, key: String, value: Variant) -> void:
	if not nodes.has(id):
		return
	# Guard: skill names must be unique across all nodes
	if key == "name" and value is String and value != "":
		for other_id in nodes:
			if other_id != id and nodes[other_id].get("name", "") == value:
				return  # reject duplicate name silently
	nodes[id][key] = value
	# Auto-derive group from effect assignment
	if key == "effect" and value is String:
		nodes[id]["group"] = get_group_for_effect(value)
	data_changed.emit()


func set_purchased(id: String, count: int) -> void:
	## Set the purchased count for a node, clamped to [0, max].
	## Going up: propagates ancestors to meet their dependency minimums.
	## Going down: zeros children whose unlock condition is no longer met.
	if not nodes.has(id):
		return
	var max_val: int = nodes[id].get("max", 1)
	var old_count: int = nodes[id].get("purchased", 0)
	var new_count: int = clampi(count, 0, max_val)
	nodes[id]["purchased"] = new_count
	if new_count >= 1:
		_ensure_ancestors_purchased(id)
	if new_count < old_count:
		# If no longer maxed, zero children that require the parent to be maxed.
		if old_count >= max_val and new_count < max_val:
			for c in connections:
				if c["from"] == id and (c["type"] == "maxed" or c["type"] == "rank_up"):
					_zero_subtree(c["to"], {})
		# If no longer purchased at all, zero children that require any purchase.
		if old_count >= 1 and new_count == 0:
			for c in connections:
				if c["from"] == id and c["type"] == "purchased":
					_zero_subtree(c["to"], {})
	data_changed.emit()


func _ensure_ancestors_purchased(id: String) -> void:
	## Walks upward through connections and ensures each ancestor meets the
	## minimum purchase requirement imposed by the dependency type.
	for c in connections:
		if c["to"] != id:
			continue
		var parent_id: String = c["from"]
		if not nodes.has(parent_id):
			continue
		var parent_max: int = nodes[parent_id].get("max", 1)
		var needed: int = parent_max if (c["type"] == "maxed" or c["type"] == "rank_up") else 1
		var current: int = nodes[parent_id].get("purchased", 0)
		if current < needed:
			nodes[parent_id]["purchased"] = needed
			_ensure_ancestors_purchased(parent_id)

# ── Connection helpers ───────────────────────────────────────────────────

func add_connection(from_id: String, to_id: String, type: String) -> bool:
	if from_id == to_id:
		return false
	for c in connections:
		if c["from"] == from_id and c["to"] == to_id:
			return false
	if type == "rank_up":
		for c in connections:
			if c["from"] == from_id and c["type"] == "rank_up":
				connection_rejected.emit(from_id)
				return false
	connections.append({"from": from_id, "to": to_id, "type": type})
	_update_unlock_counts()
	data_changed.emit()
	return true


func remove_connection_at(index: int) -> void:
	if index >= 0 and index < connections.size():
		connections.remove_at(index)
		selected_connection_index = -1
		_update_unlock_counts()
		data_changed.emit()


func assign_connection_type_at(index: int, type: String) -> void:
	## Assigns the connection type directly (no toggle).
	## If changing to "maxed" and the parent isn't fully purchased,
	## zeroes the child subtree since it would now be locked out.
	## Rank_up connections cannot be converted to or from other types.
	if index < 0 or index >= connections.size():
		return
	var c: Dictionary = connections[index]
	if c["type"] == "rank_up" or type == "rank_up":
		return
	var old_type: String = c["type"]
	c["type"] = type
	if type == "maxed" and old_type != "maxed":
		var parent_id: String = c["from"]
		if nodes.has(parent_id):
			var parent_max: int = nodes[parent_id].get("max", 1)
			var parent_purchased: int = nodes[parent_id].get("purchased", 0)
			if parent_purchased < parent_max:
				_zero_subtree(c["to"], {})
	_update_unlock_counts()
	data_changed.emit()


func _zero_subtree(id: String, visited: Dictionary) -> void:
	if visited.has(id) or not nodes.has(id):
		return
	visited[id] = true
	nodes[id]["purchased"] = 0
	for c in connections:
		if c["from"] == id:
			_zero_subtree(c["to"], visited)


func _update_unlock_counts() -> void:
	## Recomputes unlocks_on_purchase / unlocks_on_max / has_rank_up_child
	## for every node from the current connections array.
	## Called after any connection mutation.
	for id in nodes:
		nodes[id]["unlocks_on_purchase"] = 0
		nodes[id]["unlocks_on_max"] = 0
		nodes[id]["has_rank_up_child"] = false
	for c in connections:
		var fid: String = c["from"]
		if nodes.has(fid):
			if c["type"] == "purchased":
				nodes[fid]["unlocks_on_purchase"] += 1
			elif c["type"] == "rank_up":
				nodes[fid]["has_rank_up_child"] = true
			else:
				nodes[fid]["unlocks_on_max"] += 1


func get_arrow_type_string() -> String:
	if rank_up_mode:
		return "rank_up"
	return "purchased" if current_arrow_type == ArrowType.PURCHASED else "maxed"

# ── Rank-up helpers ──────────────────────────────────────────────────────

func is_rank_up_child(id: String) -> bool:
	for c in connections:
		if c["to"] == id and c["type"] == "rank_up":
			return true
	return false


func get_rank_up_parent(id: String) -> String:
	for c in connections:
		if c["to"] == id and c["type"] == "rank_up":
			return c["from"]
	return ""


# ── Effect & group accessors (user-configurable) ────────────────────────

func get_effect_names() -> PackedStringArray:
	if custom_effects.size() > 0:
		return custom_effects
	return PackedStringArray(["NONE"])


func get_group_options() -> Array:
	## Returns [{ "flag": String, "label": String }] for dropdown population.
	var out: Array = [{"flag": "", "label": "(none)"}]
	for g in custom_groups:
		out.append({"flag": g["flag"], "label": g["label"]})
	return out


func get_group_for_effect(effect_name: String) -> String:
	## Returns the group flag that contains the given effect, or "" if none.
	for g in custom_groups:
		var effs: PackedStringArray = g.get("effects", PackedStringArray())
		if effs.has(effect_name):
			return g["flag"]
	return ""


func add_effect(effect_name: String) -> void:
	if effect_name != "" and not custom_effects.has(effect_name):
		custom_effects.append(effect_name)
		data_changed.emit()


func remove_effect(effect_name: String) -> void:
	var idx := -1
	for i in range(custom_effects.size()):
		if custom_effects[i] == effect_name:
			idx = i
			break
	if idx < 0:
		return
	custom_effects.remove_at(idx)
	# Cascade: reset any nodes using this effect to "NONE"
	for nid in nodes:
		if nodes[nid].get("effect", "") == effect_name:
			nodes[nid]["effect"] = "NONE"
	# Cascade: remove from all group effect lists
	for g in custom_groups:
		var effs: PackedStringArray = g.get("effects", PackedStringArray())
		var ei := -1
		for i in range(effs.size()):
			if effs[i] == effect_name:
				ei = i
				break
		if ei >= 0:
			effs.remove_at(ei)
			g["effects"] = effs
	data_changed.emit()


func rename_effect(old_name: String, new_name: String) -> void:
	if old_name == new_name or new_name == "":
		return
	if custom_effects.has(new_name):
		return  # reject duplicate
	for i in range(custom_effects.size()):
		if custom_effects[i] == old_name:
			custom_effects[i] = new_name
			break
	# Cascade to nodes
	for nid in nodes:
		if nodes[nid].get("effect", "") == old_name:
			nodes[nid]["effect"] = new_name
	# Cascade to group effect lists
	for g in custom_groups:
		var effs: PackedStringArray = g.get("effects", PackedStringArray())
		for i in range(effs.size()):
			if effs[i] == old_name:
				effs[i] = new_name
		g["effects"] = effs
	data_changed.emit()


func add_group(flag: String, label: String, effects: PackedStringArray = PackedStringArray()) -> void:
	for g in custom_groups:
		if g["flag"] == flag:
			return
	custom_groups.append({"flag": flag, "label": label, "effects": effects})
	data_changed.emit()


func remove_group(flag: String) -> void:
	for i in range(custom_groups.size()):
		if custom_groups[i]["flag"] == flag:
			custom_groups.remove_at(i)
			# Cascade: clear group from any nodes using this flag
			for nid in nodes:
				if nodes[nid].get("group", "") == flag:
					nodes[nid]["group"] = ""
			data_changed.emit()
			return


func update_group(flag: String, new_label: String) -> void:
	for g in custom_groups:
		if g["flag"] == flag:
			g["label"] = new_label
			data_changed.emit()
			return


func update_group_flag(old_flag: String, new_flag: String) -> void:
	if old_flag == new_flag or new_flag == "":
		return
	# Reject if new flag already exists
	for g in custom_groups:
		if g["flag"] == new_flag:
			return
	for g in custom_groups:
		if g["flag"] == old_flag:
			g["flag"] = new_flag
			# Cascade to nodes
			for nid in nodes:
				if nodes[nid].get("group", "") == old_flag:
					nodes[nid]["group"] = new_flag
			data_changed.emit()
			return


func add_effect_to_group(flag: String, effect_name: String) -> void:
	for g in custom_groups:
		if g["flag"] == flag:
			var effs: PackedStringArray = g.get("effects", PackedStringArray())
			if not effs.has(effect_name):
				effs.append(effect_name)
				g["effects"] = effs
				data_changed.emit()
			return


func remove_effect_from_group(flag: String, effect_name: String) -> void:
	for g in custom_groups:
		if g["flag"] == flag:
			var effs: PackedStringArray = g.get("effects", PackedStringArray())
			for i in range(effs.size()):
				if effs[i] == effect_name:
					effs.remove_at(i)
					g["effects"] = effs
					data_changed.emit()
					return
			return


# ── Secondary Unlock helpers ────────────────────────────────────────────

func get_secondary_unlock_names() -> PackedStringArray:
	if custom_secondary_unlocks.size() > 0:
		return custom_secondary_unlocks
	return PackedStringArray(["NONE"])


func add_secondary_unlock(uname: String) -> void:
	if uname != "" and not custom_secondary_unlocks.has(uname):
		custom_secondary_unlocks.append(uname)
		data_changed.emit()


func remove_secondary_unlock(uname: String) -> void:
	var idx := -1
	for i in range(custom_secondary_unlocks.size()):
		if custom_secondary_unlocks[i] == uname:
			idx = i
			break
	if idx < 0:
		return
	custom_secondary_unlocks.remove_at(idx)
	# Cascade: reset nodes using this unlock to "NONE"
	for nid in nodes:
		if nodes[nid].get("secondary_unlock", "") == uname:
			nodes[nid]["secondary_unlock"] = "NONE"
	data_changed.emit()


func rename_secondary_unlock(old_name: String, new_name: String) -> void:
	if old_name == new_name or new_name == "":
		return
	if custom_secondary_unlocks.has(new_name):
		return
	for i in range(custom_secondary_unlocks.size()):
		if custom_secondary_unlocks[i] == old_name:
			custom_secondary_unlocks[i] = new_name
			break
	for nid in nodes:
		if nodes[nid].get("secondary_unlock", "") == old_name:
			nodes[nid]["secondary_unlock"] = new_name
	data_changed.emit()


# ── Serialisation ────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var nd := {}
	for id in nodes:
		var n: Dictionary = nodes[id]
		var pos: Vector2 = n.get("position", Vector2.ZERO)
		nd[id] = {
			"name":                n.get("name", ""),
			"cost":                n.get("cost", 0),
			"cost_increase":       n.get("cost_increase", 0),
			"exponential":         n.get("exponential", false),
			"max":                 n.get("max", 1),
			"description":         n.get("description", ""),
			"effect":              n.get("effect", "NONE"),
			"value":               n.get("value", 0.0),
			"position":            [pos.x, pos.y],
			"emoticon":            n.get("emoticon", ""),
			"image":               n.get("image", ""),
			"unlocks_on_purchase": n.get("unlocks_on_purchase", 0),
			"unlocks_on_max":      n.get("unlocks_on_max", 0),
			"group":               n.get("group", ""),
			"purchased":           n.get("purchased", 0),
			"secondary_unlock":    n.get("secondary_unlock", ""),
		}
	var ca := []
	for c in connections:
		ca.append({"from": c["from"], "to": c["to"], "type": c["type"]})

	# Serialize effects and groups so they travel with the config
	var effects_arr := []
	for e in custom_effects:
		effects_arr.append(e)
	var groups_arr := []
	for g in custom_groups:
		var ge := []
		for e in g.get("effects", PackedStringArray()):
			ge.append(e)
		groups_arr.append({"flag": g["flag"], "label": g["label"], "effects": ge})

	var sec_arr := []
	for s in custom_secondary_unlocks:
		sec_arr.append(s)

	return {
		"nodes": nd,
		"connections": ca,
		"next_id": _next_id,
		"effects": effects_arr,
		"groups": groups_arr,
		"secondary_unlocks": sec_arr,
	}


func from_dict(data: Dictionary) -> void:
	nodes.clear()
	connections.clear()

	# Load effects and groups first (if present in config)
	if data.has("effects") and data["effects"] is Array and data["effects"].size() > 0:
		custom_effects = PackedStringArray()
		for e in data["effects"]:
			custom_effects.append(str(e))
	# else: keep current defaults

	if data.has("groups") and data["groups"] is Array and data["groups"].size() > 0:
		custom_groups = []
		for g in data["groups"]:
			var effs := PackedStringArray()
			for e in g.get("effects", []):
				effs.append(str(e))
			custom_groups.append({
				"flag": str(g.get("flag", "")),
				"label": str(g.get("label", "")),
				"effects": effs,
			})

	if data.has("secondary_unlocks") and data["secondary_unlocks"] is Array and data["secondary_unlocks"].size() > 0:
		custom_secondary_unlocks = PackedStringArray()
		for s in data["secondary_unlocks"]:
			custom_secondary_unlocks.append(str(s))

	if data.has("nodes"):
		for id in data["nodes"]:
			var n: Dictionary = data["nodes"][id]
			var pa = n.get("position", [0, 0])
			# Backward compat: old files may have "unlocks_letter" instead of "secondary_unlock"
			var sec: String = str(n.get("secondary_unlock", n.get("unlocks_letter", "")))
			nodes[id] = {
				"name":                str(n.get("name", "")),
				"cost":                int(n.get("cost", 0)),
				"cost_increase":       int(n.get("cost_increase", 0)),
				"exponential":         bool(n.get("exponential", false)),
				"max":                 int(n.get("max", 1)),
				"description":         str(n.get("description", "")),
				"effect":              str(n.get("effect", "NONE")),
				"value":               float(n.get("value", 0.0)),
				"position":            Vector2(float(pa[0]), float(pa[1])),
				"emoticon":            str(n.get("emoticon", "")),
				"image":               str(n.get("image", "")),
				"unlocks_on_purchase": int(n.get("unlocks_on_purchase", 0)),
				"unlocks_on_max":      int(n.get("unlocks_on_max", 0)),
				"has_rank_up_child":   false,
				"group":               str(n.get("group", "")),
				"purchased":           int(n.get("purchased", 0)),
				"secondary_unlock":    sec,
			}
	if data.has("connections"):
		for c in data["connections"]:
			connections.append({
				"from": str(c["from"]),
				"to":   str(c["to"]),
				"type": str(c["type"]),
			})
	_next_id = int(data.get("next_id", nodes.size()))
	selected_skill_id = ""
	selected_connection_index = -1
	_update_unlock_counts()
	data_changed.emit()

# ── File I/O ─────────────────────────────────────────────────────────────

func save_to_file(path: String) -> Error:
	var json_str := JSON.stringify(to_dict(), "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(json_str)
	file.close()
	current_file_path = path
	last_saved_data = to_dict()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return OK


func load_from_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return err
	from_dict(json.data)
	current_file_path = path
	last_saved_data = to_dict()
	return OK
