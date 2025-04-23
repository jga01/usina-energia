extends Node

# Core Game Params
const MAX_ENERGY: float = 100.0
const MIN_ENERGY: float = 0.0
const BASE_ENERGY_DECAY_RATE: float = 0.5 # Energy points lost per second
const BASE_ENERGY_GAIN_PER_CLICK: float = 1.0 # Energy points gained per click

# Zones & Win/Loss Timings
const SAFE_ZONE_MIN: float = 40.0
const SAFE_ZONE_MAX: float = 70.0
const COOP_WIN_DURATION_SECONDS: float = 60.0 # e.g., 1 minute total in safe zone to win
const DANGER_LOW_THRESHOLD: float = 20.0
const DANGER_HIGH_THRESHOLD: float = 85.0
const DANGER_TIME_LIMIT_SECONDS: float = 10.0 # Max continuous seconds allowed in danger zone

# Game Loop
const GAME_LOOP_INTERVAL_MS: float = 500.0 # How often the game *logic* might check things (use delta instead for physics)
# Note: In Godot, _process(delta) runs every frame. Decay/timers use delta.

# Stabilize Action
const STABILIZE_DURATION_MS: float = 5000.0
const STABILIZE_COOLDOWN_MS: float = 15000.0
const STABILIZE_DECAY_MULTIPLIER: float = 0.2
const STABILIZE_GAIN_MULTIPLIER: float = 0.5

# Steal Action
const STEAL_GRID_COST: float = 5.0
const STEAL_STASH_GAIN: float = 2.0
const STEAL_COOLDOWN_MS: float = 10000.0
const STASH_WIN_TARGET: float = 25.0

# Emergency Adjustment Action
const EMERGENCY_ADJUST_COOLDOWN_MS: float = 20000.0
const EMERGENCY_BOOST_AMOUNT: float = 15.0
const EMERGENCY_COOLANT_AMOUNT: float = 20.0
const EMERGENCY_PENALTY_WRONG_ZONE: float = 5.0

# Random Events
const EVENT_CHECK_INTERVAL_MS: float = 15000.0 # Use Timer node wait_time
const EVENT_CHANCE_PERCENT: float = 50.0 # Chance (0-100)
const EVENT_DURATION_MS: float = 10000.0
const EVENT_SURGE_DECAY_MULTIPLIER: float = 2.5
const EVENT_EFFICIENCY_GAIN_MULTIPLIER: float = 2.0
# Use Enums or StringNames for event types in Godot
enum EventType { NONE, SURGE, EFFICIENCY }
const EVENT_TYPES: Array[EventType] = [EventType.SURGE, EventType.EFFICIENCY]

# --- Network Settings ---
const DEFAULT_UDP_PORT: int = 4210 # Example port, choose one not commonly used
const NUM_PLAYERS: int = 4
