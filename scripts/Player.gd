class_name PlayerState
extends RefCounted

var id: int = 0
var stabilize_cooldown_end_ms: int = 0
var steal_grid_cooldown_end_ms: int = 0
var personal_stash: float = 0.0
var emergency_adjust_cooldown_end_ms: int = 0
var last_action_status: String = "" # New field for feedback

func _init(p_id: int):
	id = p_id
	reset()

func reset():
	stabilize_cooldown_end_ms = 0
	steal_grid_cooldown_end_ms = 0
	personal_stash = 0.0
	emergency_adjust_cooldown_end_ms = 0
	last_action_status = ""

# Helper to easily get state as dictionary
func get_state_data() -> Dictionary:
	return {
		"id": id,
		"stabilize_cooldown_end_ms": stabilize_cooldown_end_ms,
		"steal_grid_cooldown_end_ms": steal_grid_cooldown_end_ms,
		"personal_stash": personal_stash,
		"emergency_adjust_cooldown_end_ms": emergency_adjust_cooldown_end_ms,
		"last_action_status": last_action_status
	}

# Helper to set a temporary status (cleared on next get_state_data call)
func set_temp_status(status: String):
	last_action_status = status

# Helper to clear the temporary status after it's been read
func clear_temp_status():
	last_action_status = ""
