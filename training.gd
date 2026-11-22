extends Node2D


func _on_hazard_body_entered(body: Node2D) -> void:
	if body == $Player:
		var knockback := -1.0 if body.global_position.x <= $Hazard.global_position.x else 1.0
		$Player.take_hit(knockback)
