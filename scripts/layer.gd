extends Node2D
## Tiny draw-forwarding node: lets one script paint several z-ordered layers.
var cb: Callable

func _draw() -> void:
	if cb.is_valid():
		cb.call(self)
