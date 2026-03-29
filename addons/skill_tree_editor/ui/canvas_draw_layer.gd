## Lightweight drawing proxy for the skill editor canvas.
##
## During _draw(), delegates to draw_target._draw_layer(self, layer_id).
## The main script can then call ci.draw_line(), ci.draw_circle(), etc.
## because the call happens within this node's _draw() context.
@tool
extends Control

var draw_target: Object = null
var layer_id: String = ""


func _draw() -> void:
	if draw_target != null and draw_target.has_method("_draw_layer"):
		draw_target._draw_layer(self, layer_id)
