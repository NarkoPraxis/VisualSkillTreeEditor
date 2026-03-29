# Skill Tree Editor

A visual skill tree editor plugin for Godot 4.x. Design skill definitions, prerequisites, costs, and unlock order in a dedicated canvas view — then export to JSON for your game to consume at runtime.

## Features

- **Main-screen editor** — appears as a tab alongside 2D, 3D, and Script
- **Zoomable, pannable canvas** with a blueprint-style grid
- **Drag-to-connect** dependency arrows between skill nodes
- **Three arrow types**: Unlock (first purchase), Maxed (requires all purchases), Rank-Up (creates a linked upgrade chain)
- **Three interaction modes**: Create, Edit, Delete
- **Properties dock** for editing skill name, cost, max purchases, effect, group, description, and more
- **Configurable effects and groups** — define your own effect types and group categories; stored in the JSON config so each project can customize freely
- **JSON import/export** — all data saved to a single `.json` file your game reads at runtime
- **Purchase simulation** — test unlock cascades directly in the editor with per-node purchase spinners

## Installation

### From the Godot Asset Library

1. Open the **AssetLib** tab in the Godot editor
2. Search for **"Skill Tree Editor"**
3. Click **Download**, then **Install**
4. Go to **Project > Project Settings > Plugins** and enable **Skill Tree Editor**

### Manual Installation

1. Download or clone this repository
2. Copy the `addons/skill_tree_editor/` folder into your project's `addons/` directory
3. Go to **Project > Project Settings > Plugins** and enable **Skill Tree Editor**

## Usage

1. **Enable the plugin** in Project Settings > Plugins
2. Click the **Skill Editor** tab that appears in the main editor toolbar (next to 2D, 3D, Script)
3. **Double-click** the canvas to create skill nodes
4. **Drag from the blue dot** (bottom of a node) to another node to create a dependency arrow
5. **Drag from the red dot** (left of a node) to empty space to create a rank-up variant
6. Use the **Properties** dock on the right to edit the selected node's details
7. **Save** your tree as a `.json` file

### Configuring Effects and Groups

Effects and groups are stored in the JSON config file alongside your skill tree data. The plugin ships with a default set of generic RPG effects (Damage, Health, Mana, etc.) and groups (Offense, Defense, Magic, Utility, Passive, Summons, Custom).

To customize for your project:
1. Save a tree (creates the JSON file)
2. Edit the `"effects"` array in the JSON to add/remove/rename effect types
3. Edit the `"groups"` array to define your own group categories with flags, labels, and associated effects
4. Re-open the file in the editor — your custom effects and groups will appear in the dropdowns

### Loading a Default Config

Use **Tools > Set Skill Config...** to point the editor at your project's main skill tree JSON file. The editor will auto-load it on startup.

## JSON Format

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
      "group": "-o",
      "purchased": 0,
      "unlocks_letter": ""
    }
  },
  "connections": [
    { "from": "node_1", "to": "node_2", "type": "purchased" }
  ],
  "next_id": 3,
  "effects": ["NONE", "DAMAGE", "HEALTH", "MANA", "..."],
  "groups": [
    { "flag": "-o", "label": "OFFENSE", "effects": ["DAMAGE", "ATTACK_SPEED"] }
  ]
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
