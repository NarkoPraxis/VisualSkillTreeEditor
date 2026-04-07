## Runtime data model for the in-game skill tree.
##
## Loads a JSON file exported by the Skill Tree Editor plugin, holds all node
## and connection state, and handles purchase propagation — identical logic to
## SkillEditorContext but stripped of all editor dependencies.
##
## This class has zero UI references and can be used independently of the
## SkillTree scene.
extends RefCounted
class_name SkillTreeData

signal state_changed()

## id → { name, cost, cost_increase, exponential, max, description, effect,
##         value, position:Vector2, emoticon, image, group, purchased,
##         secondary_unlock, unlocks_on_purchase, unlocks_on_max, has_rank_up_child }
var nodes: Dictionary = {}

## Array of { from:String, to:String, type:String("purchased"|"maxed"|"rank_up") }
var connections: Array = []

var effects: PackedStringArray = []
var groups: Array = []
var secondary_unlocks: PackedStringArray = []


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
	_from_dict(json.data)
	return OK


func _from_dict(data: Dictionary) -> void:
	nodes.clear()
	connections.clear()
	effects.clear()
	groups.clear()
	secondary_unlocks.clear()

	if data.has("effects") and data["effects"] is Array:
		for e in data["effects"]:
			effects.append(str(e))

	if data.has("groups") and data["groups"] is Array:
		for g in data["groups"]:
			var effs := PackedStringArray()
			for e in g.get("effects", []):
				effs.append(str(e))
			groups.append({"label": str(g.get("label", "")), "effects": effs})

	if data.has("secondary_unlocks") and data["secondary_unlocks"] is Array:
		for s in data["secondary_unlocks"]:
			secondary_unlocks.append(str(s))

	if data.has("nodes") and data["nodes"] is Dictionary:
		for id in data["nodes"]:
			var n: Dictionary = data["nodes"][id]
			var pa = n.get("position", [0.0, 0.0])
			var pos := Vector2.ZERO
			if pa is Array and pa.size() >= 2:
				pos = Vector2(float(pa[0]), float(pa[1]))
			nodes[id] = {
				"name":                str(n.get("name", "")),
				"cost":                int(n.get("cost", 0)),
				"cost_increase":       int(n.get("cost_increase", 0)),
				"exponential":         bool(n.get("exponential", false)),
				"max":                 int(n.get("max", 1)),
				"description":         str(n.get("description", "")),
				"effect":              str(n.get("effect", "NONE")),
				"value":               float(n.get("value", 0.0)),
				"position":            pos,
				"emoticon":            str(n.get("emoticon", "")),
				"image":               str(n.get("image", "")),
				"group":               str(n.get("group", "")),
				"purchased":           int(n.get("purchased", 0)),
				"secondary_unlock":    str(n.get("secondary_unlock", n.get("unlocks_letter", "NONE"))),
				"unlocks_on_purchase": 0,
				"unlocks_on_max":      0,
				"has_rank_up_child":   false,
			}

	if data.has("connections") and data["connections"] is Array:
		for c in data["connections"]:
			if c is Dictionary and c.has("from") and c.has("to") and c.has("type"):
				connections.append({
					"from": str(c["from"]),
					"to":   str(c["to"]),
					"type": str(c["type"]),
				})

	_update_unlock_counts()


# ── Query helpers ─────────────────────────────────────────────────────────

func can_purchase(id: String) -> bool:
	## Returns true if the node is unlocked (all parent requirements met) and
	## still has remaining purchases available (purchased < max).
	if not nodes.has(id):
		return false
	var node: Dictionary = nodes[id]
	if node.get("purchased", 0) >= node.get("max", 1):
		return false
	for c in connections:
		if c["to"] != id:
			continue
		var parent_id: String = c["from"]
		if not nodes.has(parent_id):
			continue
		var parent: Dictionary = nodes[parent_id]
		var pp: int = parent.get("purchased", 0)
		var pm: int = parent.get("max", 1)
		if c["type"] == "purchased":
			if pp < 1:
				return false
		else:  # "maxed" or "rank_up"
			if pp < pm:
				return false
	return true


func is_locked(id: String) -> bool:
	## Returns true if any parent requirement is unmet (skill is inaccessible).
	if not nodes.has(id):
		return true
	for c in connections:
		if c["to"] != id:
			continue
		var parent_id: String = c["from"]
		if not nodes.has(parent_id):
			continue
		var parent: Dictionary = nodes[parent_id]
		var pp: int = parent.get("purchased", 0)
		var pm: int = parent.get("max", 1)
		if c["type"] == "purchased":
			if pp < 1:
				return true
		else:  # "maxed" or "rank_up"
			if pp < pm:
				return true
	return false


func is_maxed(id: String) -> bool:
	if not nodes.has(id):
		return false
	var node: Dictionary = nodes[id]
	return node.get("purchased", 0) >= node.get("max", 1)


func is_rank_up_child(id: String) -> bool:
	for c in connections:
		if c["to"] == id and c["type"] == "rank_up":
			return true
	return false


func get_current_cost(id: String) -> int:
	## Returns the cost of the NEXT purchase for this node, accounting for
	## cost_increase (flat or exponential).
	if not nodes.has(id):
		return 0
	var node: Dictionary = nodes[id]
	var base: int = node.get("cost", 0)
	var increase: int = node.get("cost_increase", 0)
	var purchased: int = node.get("purchased", 0)
	if node.get("exponential", false) and increase > 0:
		return int(float(base) * pow(1.0 + float(increase) / 100.0, float(purchased)))
	return base + increase * purchased


# ── State mutation ────────────────────────────────────────────────────────

func set_purchased(id: String, count: int) -> void:
	## Sets the purchased count for a node, clamped to [0, max].
	## Propagates upward (ensures ancestors meet their thresholds) and
	## cascades zeroes downward when requirements are no longer met.
	if not nodes.has(id):
		return
	var max_val: int = nodes[id].get("max", 1)
	var old_count: int = nodes[id].get("purchased", 0)
	var new_count: int = clampi(count, 0, max_val)
	nodes[id]["purchased"] = new_count
	if new_count >= 1:
		_ensure_ancestors_purchased(id)
	if new_count < old_count:
		if old_count >= max_val and new_count < max_val:
			for c in connections:
				if c["from"] == id and (c["type"] == "maxed" or c["type"] == "rank_up"):
					_zero_subtree(c["to"], {})
		if old_count >= 1 and new_count == 0:
			for c in connections:
				if c["from"] == id and c["type"] == "purchased":
					_zero_subtree(c["to"], {})
	state_changed.emit()


func _ensure_ancestors_purchased(id: String) -> void:
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


func _zero_subtree(id: String, visited: Dictionary) -> void:
	if visited.has(id) or not nodes.has(id):
		return
	visited[id] = true
	nodes[id]["purchased"] = 0
	for c in connections:
		if c["from"] == id:
			_zero_subtree(c["to"], visited)


func _update_unlock_counts() -> void:
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


# ── Persistence ──────────────────────────────────────────────────────────

func save_state() -> Dictionary:
	## Returns {node_id: purchased_count} for all nodes.  Persist this between
	## play sessions and restore it with load_state().
	var state: Dictionary = {}
	for id in nodes:
		state[id] = nodes[id].get("purchased", 0)
	return state


func load_state(state: Dictionary) -> void:
	## Restores purchased counts from a previously saved state dictionary.
	for id in state:
		if nodes.has(id):
			nodes[id]["purchased"] = clampi(int(state[id]), 0, nodes[id].get("max", 1))
	state_changed.emit()
