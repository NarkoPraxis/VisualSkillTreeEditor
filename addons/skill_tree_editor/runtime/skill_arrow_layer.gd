## Lightweight drawing proxy for the runtime skill tree canvas.
##
## During _draw(), delegates to draw_target._draw_layer(self, layer_id) so
## drawing commands execute within this node's own CanvasItem context.
## Mirrors the pattern used by canvas_draw_layer.gd in the editor.
@tool
extends Control
class_name SkillArrowLayer

var draw_target: Object = null
var layer_id: String = ""


func _draw() -> void:
	if draw_target != null and draw_target.has_method("_draw_layer"):
		draw_target._draw_layer(self, layer_id)
