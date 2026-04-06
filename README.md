# Skill Tree Editor

A visual skill tree editor plugin for Godot 4.x. Design skill definitions, prerequisites, costs, and unlock order in a dedicated canvas view — then export to JSON for your game to consume at runtime.

## Features

- **Main-screen editor** — appears as a tab alongside 2D, 3D, and Script
- **Zoomable, pannable canvas** with a blueprint-style grid
- **Drag-to-connect** dependency arrows between skill nodes
- **Three arrow types**: Unlock (first purchase), Maxed (requires all purchases), Rank-Up (creates a linked upgrade chain)
- **Two interaction modes**: Create/Edit and Delete
- **Properties dock** for editing skill name, cost, max purchases, effect, group, description, and more
- **Configurable effects, groups, and secondary unlocks** — define your own types; stored in the JSON config so each project can customize freely
- **JSON import/export** — all data saved to a single `.json` file your game reads at runtime
- **Purchase simulation** — test unlock cascades directly in the editor with per-node purchase spinners

---

## Getting Started

### Installation

**From the Godot Asset Library:**

1. Open the **AssetLib** tab in the Godot editor
2. Search for **"Skill Tree Editor"**
3. Click **Download**, then **Install**
4. Go to **Project > Project Settings > Plugins** and enable **Skill Tree Editor**

**Manual Installation:**

1. Download or clone this repository
2. Copy the `addons/skill_tree_editor/` folder into your project's `addons/` directory
3. Go to **Project > Project Settings > Plugins** and enable **Skill Tree Editor**

### First Launch

1. With the plugin enabled, click the **Skill Editor** tab in the main editor toolbar (next to 2D, 3D, Script)
2. The canvas opens with an empty blueprint-style grid
3. Use **Tools > Set Skill Config...** to point the editor at an existing `.json` file, or create a new tree from scratch and save it

---

## The Interface

<!-- Screenshot: Full editor layout with canvas and dock labeled -->

The editor has two main areas:

- **Canvas** (center) — the main drawing area where you place and connect skill nodes
- **Skill Properties dock** (right panel) — shows editable fields for the selected node

### Toolbar

The toolbar at the top of the canvas provides:

| Button | Action |
|---|---|
| Save icon | Save the current tree to its file |
| Save As icon | Save to a new file |
| Open icon | Open an existing `.json` skill tree |
| Load Game's Config | Reload the file set via **Tools > Set Skill Config...** |

The current filename is shown on the right side of the toolbar.

### Mode Toggle

A button in the top-right corner of the canvas switches between two modes:

- **Create/Edit mode** — place nodes, move them, draw connections, select and edit
- **Delete mode** — click a node or arrow to remove it

Press the **backtick key (`)** to toggle modes from the keyboard.

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `` ` `` (backtick) | Toggle between Create/Edit and Delete mode |
| `Ctrl+S` | Save |
| `Ctrl+Shift+S` | Save As |
| `Ctrl+O` | Open |
| `Scroll wheel` | Zoom in / out |
| `Middle mouse drag` | Pan the canvas |

---

## Working with Nodes

### Adding a Node

1. Make sure you are in **Create/Edit mode** (backtick to toggle; mode button is in the top-right corner of the canvas)
2. **Double-click** anywhere on the canvas to create a new skill node
3. The node appears with default values; select it to edit its properties in the dock

<!-- Screenshot: Double-clicking the canvas to create a new node -->

### Selecting and Moving Nodes

- **Left-click** a node card to select it — its properties appear in the dock
- **Click and drag** a node card to reposition it on the canvas

### Editing Node Properties

With a node selected, the **Skill Properties** dock on the right shows all editable fields:

| Field | Description |
|---|---|
| **Name** | Unique display name for the skill |
| **Cost** | Base resource cost for the first purchase |
| **Increase** | Amount added to cost with each subsequent purchase |
| **Exponential** | If enabled, cost multiplies instead of adding linearly |
| **Max** | Maximum number of times the skill can be purchased |
| **Value** | Numeric value associated with the skill's effect |
| **Effect** | Which effect type this skill applies (from your configured list) |
| **Icon** | An emoji/symbol or file path to an image shown on the node card |
| **Secondary Unlock** | Optional secondary dependency category (badge shows first 3 characters) |
| **Description** | Free-text description of what the skill does |

<!-- Screenshot: Properties dock with a node selected -->

### Deleting a Node

Switch to **Delete mode** (backtick) and click the node. This also removes all connections to and from that node.

---

## Working with Dependencies (Arrows)

Arrows define the prerequisites between skills. A child skill is locked until its parent's unlock condition is met.

### Arrow Types

| Type | Color | Condition to unlock child |
|---|---|---|
| **Unlock** | Green | Parent purchased at least once |
| **Maxed** | Gold | Parent purchased to its maximum |
| **Rank-Up** | Red | Special chain — the child is a direct upgrade of the parent |

### Drawing an Unlock Arrow (Green)

1. In **Create/Edit mode**, hover over the **bottom edge** of a parent node — a green handle circle appears
2. **Left-click and drag** from that handle to the child node
3. Release over the child node to create the connection

<!-- Screenshot: Dragging from the bottom handle to draw a green unlock arrow -->

### Drawing a Maxed Arrow (Gold)

1. In **Create/Edit mode**, hover over the **bottom edge** of a parent node
2. **Right-click and drag** from that handle to the child node
3. Release over the child node to create a gold "maxed" connection

### Creating a Rank-Up Chain (Red)

1. In **Create/Edit mode**, hover over the **left edge** of a node — a red handle appears
2. **Left-click and drag** from that handle to an empty space on the canvas
3. A new node is created and automatically linked as a rank-up child

Rank-up children inherit their parent's effect type and the effect dropdown is disabled.

### Toggling Arrow Type

Click an existing arrow with the **opposite** mouse button to toggle it between Unlock (green) and Maxed (gold).

### Deleting an Arrow

Switch to **Delete mode** and click on the arrow line to remove it.

<!-- Screenshot: Canvas showing all three arrow types between nodes -->

---

## Configuring Effects, Groups, and Secondary Unlocks

Effects, groups, and secondary unlocks are stored in your JSON file alongside node data. Open the configuration dialog via the toolbar or menu.

<!-- Screenshot: Config dialog open showing the Effects tab -->

### Effects Tab

Effects represent what a skill actually does in your game (e.g., `DAMAGE`, `HEALTH`, `MANA`).

**To add a new effect:**
1. Open **Tools > Configure Effects/Groups** (or via the dock button)
2. Go to the **Effects** tab
3. Type the new effect name and click **Add**
4. Effect names are automatically converted to `UPPER_SNAKE_CASE`

**To remove an effect:**
- Select it in the list and click **Remove**
- Any nodes using that effect will retain their stored value but the dropdown will reset on next open

### Groups Tab

Groups are categories that visually color-code your nodes on the canvas. Each group has:

- **Flag** — a short prefix string like `-e` (auto-prepended if you omit the dash)
- **Label** — display name shown in the UI
- **Effects** — which effects belong to this group (assigning an effect to a node auto-sets its group)

<!-- Screenshot: Config dialog Groups tab -->

**To add a new group:**
1. Go to the **Groups** tab in the config dialog
2. Enter a flag (e.g., `-m`), a label (e.g., `Magic`), and select associated effects
3. Click **Add**

**Default group colors** are mapped from flag strings to canvas background and border colors. Custom flags beyond the built-in set will use a neutral gray.

### Secondary Unlocks Tab

Secondary unlocks are an optional dependency category displayed as a badge on node cards (first 3 characters shown).

**To add a secondary unlock type:**
1. Go to the **Secondary Unlocks** tab in the config dialog
2. Enter the name and click **Add**

Assign a secondary unlock to a node via the **Secondary Unlock** dropdown in the Skill Properties dock.

---

## Purchase Simulation

The editor includes a built-in purchase simulator so you can test your unlock logic without running the game.

- Each node card has a **purchase spinner** showing how many times it has been purchased
- Increasing purchases on a child node **automatically purchases ancestors** to meet dependency minimums
- Decreasing purchases on a parent **zeros out locked-out child subtrees**

This lets you verify that your dependency graph behaves as expected before exporting.

---

## Setting a Default Config File

Use **Tools > Set Skill Config...** to set a project-level path. The editor auto-loads this file on startup so you don't need to open it manually each session.

The path is stored in the project setting `skill_tree_editor/skill_config_path`.

---

## JSON Format

All data is saved to a single `.json` file:

```json
{
  "nodes": {
    "node_1": {
      "name": "Power Strike",
      "cost": 100,
      "cost_increase": 25,
      "exponential": false,
      "max": 5,
      "description": "+10% damage per level",
      "effect": "DAMAGE",
      "value": 10.0,
      "position": [280.0, 40.0],
      "emoticon": "",
      "image": "",
      "unlocks_on_purchase": 1,
      "unlocks_on_max": 0,
      "group": "-c",
      "purchased": 0,
      "unlocks_letter": ""
    }
  },
  "connections": [
    { "from": "node_1", "to": "node_2", "type": "purchased" }
  ],
  "next_id": 3,
  "effects": ["NONE", "DAMAGE", "HEALTH", "MANA"],
  "groups": [
    { "flag": "-c", "label": "Combat", "effects": ["DAMAGE", "ATTACK_SPEED"] }
  ],
  "secondary_unlocks": ["Passive", "Active"]
}
```

Connection `type` values: `"purchased"`, `"maxed"`, `"rank_up"`.

---

## Common Use Cases

### Building a Linear Upgrade Path

1. Create a root node (double-click the canvas)
2. Draw an unlock arrow (left-drag from its bottom handle) to a second node
3. Repeat to extend the chain
4. Use **Rank-Up** (left-drag from the left handle) if each step is a direct upgrade of the same skill rather than a separate skill

### Building a Branching Skill Tree

1. Create a root node
2. Draw unlock or maxed arrows to multiple children — one parent can connect to many children
3. Arrange nodes spatially to make the branching clear; position does not affect logic

### Requiring Multiple Parents

Draw arrows from several parent nodes to the same child. The child unlocks when **all** of its parents meet their respective conditions.

### Grouping Skills by Theme

1. Open the config dialog and define your groups (e.g., Combat `-c`, Economy `-e`, Passive `-p`)
2. Assign each group's associated effects
3. When you set a node's **Effect** in the dock, its group (and therefore its card color on the canvas) updates automatically

### Exporting for Runtime

Save the tree with **Ctrl+S**. Your game code reads the JSON file at runtime — the `nodes` and `connections` keys contain everything needed to reconstruct the tree and evaluate unlock state.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
