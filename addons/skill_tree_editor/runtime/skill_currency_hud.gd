## Currency HUD — shows available gold in the top-left corner of the skill tree canvas.
##
## Instantiated by SkillTree._generate() and saved into the scene alongside SkillNodes.
## Hidden by default; SkillTree.set_available_currency() shows/hides and updates it.
@tool
extends PanelContainer
class_name SkillCurrencyHud

var _label: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 10
	position = Vector2(8, 8)

	var sty := StyleBoxFlat.new()
	sty.set_corner_radius_all(5)
	sty.bg_color = Color(0.06, 0.09, 0.16, 0.88)
	sty.border_color = Color(0.40, 0.55, 0.80, 0.55)
	sty.set_border_width_all(1)
	sty.set_content_margin_all(6)
	sty.content_margin_left = 10
	sty.content_margin_right = 10
	add_theme_stylebox_override("panel", sty)

	_label = get_node_or_null("GoldLabel")
	if _label == null:
		_label = Label.new()
		_label.name = "GoldLabel"
		add_child(_label)
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.35))


func set_gold(amount: int) -> void:
	if is_instance_valid(_label):
		_label.text = "Gold: %d" % amount
