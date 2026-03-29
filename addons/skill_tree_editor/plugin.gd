## Entry point for the Skill Tree Editor plugin.
##
## Registers a main-screen panel (next to 2D / 3D / Script) and a dockable
## side panel. Both panels receive the same SkillEditorContext so they can
## communicate through it without holding direct references to each other.
@tool
extends EditorPlugin

const SkillEditorContext = preload("res://addons/skill_tree_editor/core/skill_editor_context.gd")
const SkillEditorMain   = preload("res://addons/skill_tree_editor/ui/skill_editor_main.gd")
const SkillEditorDock   = preload("res://addons/skill_tree_editor/ui/skill_editor_dock.gd")

var _context: RefCounted  # SkillEditorContext
var _main_panel: Control
var _dock: Control
var _file_dlg: EditorFileDialog


func _enter_tree() -> void:
	_context = SkillEditorContext.new()

	_main_panel = SkillEditorMain.new()
	_main_panel.name = "SkillEditorMain"
	_main_panel.setup(_context)
	EditorInterface.get_editor_main_screen().add_child(_main_panel)
	_make_visible(false)

	_dock = SkillEditorDock.new()
	_dock.name = "Skill Properties"
	_dock.setup(_context)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)

	# Register project setting for skill config JSON path
	if not ProjectSettings.has_setting("skill_tree_editor/skill_config_path"):
		ProjectSettings.set_setting("skill_tree_editor/skill_config_path", "")
	ProjectSettings.set_initial_value("skill_tree_editor/skill_config_path", "")
	ProjectSettings.add_property_info({
		"name": "skill_tree_editor/skill_config_path",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.json",
	})

	add_tool_menu_item("Set Skill Config...", _on_set_skill_config)


func _exit_tree() -> void:
	remove_tool_menu_item("Set Skill Config...")
	if _file_dlg:
		_file_dlg.queue_free()
		_file_dlg = null
	if _main_panel:
		_main_panel.queue_free()
		_main_panel = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	_context = null


# ── Skill Config Menu ────────────────────────────────────────────────────────

func _on_set_skill_config() -> void:
	if not _file_dlg:
		_file_dlg = EditorFileDialog.new()
		_file_dlg.add_filter("*.json", "JSON Skill Config")
		_file_dlg.access = EditorFileDialog.ACCESS_RESOURCES
		_file_dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dlg.file_selected.connect(_on_skill_config_selected)
		EditorInterface.get_base_control().add_child(_file_dlg)
	_file_dlg.current_path = ProjectSettings.get_setting("skill_tree_editor/skill_config_path", "res://")
	_file_dlg.popup_centered(Vector2(700, 500))


func _on_skill_config_selected(path: String) -> void:
	ProjectSettings.set_setting("skill_tree_editor/skill_config_path", path)
	ProjectSettings.save()
	print("[SkillTreeEditor] Skill config set to: %s" % path)


# ── Main-screen overrides ─────────────────────────────────────────────────────

func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _main_panel:
		_main_panel.visible = visible


func _get_plugin_name() -> String:
	return "Skill Editor"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", "EditorIcons")
