@tool
class_name RcKey extends RcBaseEffect

var animation_name = "default"

func _ready() -> void:
	super.do_animation($AnimationPlayer)
	super.start_effect_timer(0.5)

func create_key(r:Vector2,g:Vector2,b:Vector2,a:Vector2,last_key:String = "") -> void:
	var key_label:Label = $Label
	var rand = randf_range(0.5, 1.0)
	scale = Vector2(rand, rand)
	key_label.text = last_key
	key_label.modulate = Color(randf_range(r.x,r.y),randf_range(g.x,g.y),randf_range(b.x,b.y), randf_range(b.x,b.y))
