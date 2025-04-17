# scripts/PlayerState.gd
# Option 1: As a Resource (can be saved/loaded easier if needed later)
# @tool # Add if you want to edit properties in the inspector
# extends Resource
# class_name PlayerState
# @export var id: int = 0
# @export var stabilize_cooldown_end_ms: int = 0
# @export var steal_grid_cooldown_end_ms: int = 0
# @export var personal_stash: float = 0.0
# @export var emergency_adjust_cooldown_end_ms: int = 0

# Option 2: Simple Class (often sufficient)
class_name PlayerState
extends RefCounted # Or just Object if no ref counting needed

var id: int = 0
var stabilize_cooldown_end_ms: int = 0
var steal_grid_cooldown_end_ms: int = 0
var personal_stash: float = 0.0
var emergency_adjust_cooldown_end_ms: int = 0

func _init(p_id: int):
	id = p_id
	# Initialize other vars to 0 or default values
	reset()

func reset():
	stabilize_cooldown_end_ms = 0
	steal_grid_cooldown_end_ms = 0
	personal_stash = 0.0
	emergency_adjust_cooldown_end_ms = 0
