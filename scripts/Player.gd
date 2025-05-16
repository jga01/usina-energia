# scripts/Player.gd
class_name PlayerState
extends RefCounted

var id: int = 0
var personal_stash: float = 0.0
var total_energy_generated: float = 0.0 # <-- NEW VARIABLE
var is_eliminated: bool = false
var last_action_status: String = ""

func _init(p_id: int):
	id = p_id
	reset()

func reset():
	personal_stash = 0.0
	total_energy_generated = 0.0 # <-- RESET
	is_eliminated = false
	last_action_status = ""

func get_state_data() -> Dictionary:
	return {
		"id": id,
		"personal_stash": personal_stash,
		"total_energy_generated": total_energy_generated, # <-- INCLUDE IN STATE
		"is_eliminated": is_eliminated,
		"last_action_status": last_action_status
	}

func add_generated_energy(amount: float): # <-- NEW HELPER FUNCTION
	if not is_eliminated and amount > 0:
		total_energy_generated += amount

func set_temp_status(status: String):
	last_action_status = status

func clear_temp_status():
	last_action_status = ""

func eliminate_player():
	is_eliminated = true
	# personal_stash = 0.0 # Optional
	print("Player %d has been eliminated!" % id)
	set_temp_status(TextDB.STATUS_ELECTROCUTED)
