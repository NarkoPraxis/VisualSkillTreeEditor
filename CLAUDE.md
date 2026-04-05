# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Godot 4.6 editor plugin ("Skill Tree Editor") that provides a visual, main-screen canvas for designing skill trees. Users create skill nodes, connect them with dependency arrows, edit properties in a dock panel, and export everything to a single JSON file for runtime consumption.

## Architecture

The plugin lives entirely under `addons/skill_tree_editor/`. Entry point is `plugin.gd`, which registers a main-screen panel and a dock panel, both wired through a shared context object.

**Core pattern:** The canvas (`skill_editor_main.gd`) and dock (`skill_editor_dock.gd`) never reference each other. All communication flows through `SkillEditorContext` (`core/skill_editor_context.gd`), a `RefCounted` that owns all data, selection state, editor mode, and serialisation. Both UI components connect to its signals (`skill_selected`, `data_changed`, `mode_changed`, etc.).

### Key files

- **`plugin.gd`** — `EditorPlugin` subclass. Creates context, main panel, dock, and the "Set Skill Config..." tool menu item.
- **`core/skill_editor_context.gd`** — Central data model. Holds `nodes` dict (id → skill data), `connections` array, effects/groups config, selection state, and all mutation + serialisation logic. JSON import/export happens here (`save_to_file` / `load_from_file`).
- **`ui/skill_editor_main.gd`** — Main-screen canvas with zoom/pan, node cards, drag-to-connect arrows, and mode toolbar (Create / Delete). Left-click from a handle draws green (unlock) arrows; right-click draws gold (maxed) arrows. Clicking an existing arrow with the opposite button toggles its type. Uses world→screen coordinate transform (`_w2s` / `_s2w`). Canvas rendering uses `CanvasDrawLayer` proxies for layered drawing (arrow layer at z=0, overlay layer at z=1).
- **`ui/skill_editor_dock.gd`** — Right-side properties panel. Populates fields from context on selection; writes back via `_ctx.update_node()`. Has a `_updating` guard to prevent feedback loops during field population.
- **`ui/canvas_draw_layer.gd`** — Tiny draw proxy: delegates `_draw()` to `draw_target._draw_layer(self, layer_id)`.
- **`ui/config_dialog.gd`** — Tabbed dialog (Effects + Groups) for managing custom effect types and group categories.

### Data model

Skill nodes are stored as `Dictionary` entries keyed by string IDs (`"node_1"`, `"node_2"`, ...). Each node has: name, cost, cost_increase, exponential, max, description, effect, value, position (Vector2), emoticon (renamed "Icon" in UI — accepts emoji/symbol or image file path), image, group (flag string like `"-e"`), purchased count, secondary_unlock (configurable list, badge shows first 3 chars).

Connections are `Array[Dictionary]` with `{from, to, type}` where type is `"purchased"`, `"maxed"`, or `"rank_up"`. Unlock counts (`unlocks_on_purchase`, `unlocks_on_max`, `has_rank_up_child`) are derived — recomputed by `_update_unlock_counts()` after any connection mutation.

Effects, groups, and secondary unlocks are user-configurable and stored in the JSON alongside nodes/connections. Groups use short flag prefixes (e.g., `"-e"` for Economy, `"-c"` for Combat) and map to visual color themes in the canvas (`GRP_BG` / `GRP_BORDER` dicts). Secondary unlocks are managed via a third tab in the config dialog.

## Development

This is a Godot editor plugin — there is no build step or test suite. To develop:

1. Open the project in Godot 4.6+
2. Enable the plugin in Project > Project Settings > Plugins
3. The "Skill Editor" tab appears in the main editor toolbar

All scripts use `@tool` annotation to run in the editor. Changes to `.gd` files take effect after Godot reloads the plugin (toggle it off/on, or reopen the project).

The project setting `skill_tree_editor/skill_config_path` controls which JSON file auto-loads on startup. Set via Tools > Set Skill Config...

## GDScript Type Inference Rules

**Never use `:=` when the right-hand side involves a `Dictionary` field access, a `Variant`, or arithmetic that mixes typed and untyped values.** GDScript cannot infer the type in these cases and will error. Use an explicit type annotation instead.

```gdscript
# WRONG — entry is a Dictionary, entry.pos is Variant, result is Variant:
var sc := size / 2.0 + (entry.pos - _camera_pos) * _zoom_level

# CORRECT — cast the Dictionary field, then annotate the variable:
var sc: Vector2 = size / 2.0 + (entry.pos as Vector2 - _camera_pos) * _zoom_level
```

The same rule applies any time the result type is ambiguous: arithmetic on `Variant`, ternary expressions returning different types, or return values from functions typed as `Variant`. When in doubt, use `var name: ExplicitType = ...` rather than `:=`.

## Conventions

- All UI is built programmatically in GDScript (no `.tscn` scene files) — constructing controls in `_build_ui()` / `_ready()` methods.
- Skill names must be unique across all nodes (enforced in `update_node()`).
- Effect names are auto-sanitized to `UPPER_SNAKE_CASE` (see `_sanitize()` in config_dialog).
- Group flags must start with `-` (auto-prepended if missing).
- Assigning an effect to a node auto-derives its group via `get_group_for_effect()`.
- Rank-up children inherit their parent's effect (dropdown is disabled).
- Purchase simulation propagates: purchasing a child auto-purchases ancestors to meet dependency minimums; reducing purchases zeros locked-out subtrees.
