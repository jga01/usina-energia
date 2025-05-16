# scripts/config.gd
extends Node

# Core Game Params
const MAX_ENERGY: float = 100.0
const MIN_ENERGY: float = 0.0
const BASE_ENERGY_DECAY_RATE: float = 1.4
const BASE_ENERGY_GAIN_PER_MASH: float = 0.25

# --- NEW: Exponential Inactivity Penalty ---
const INACTIVITY_THRESHOLD_SECONDS: float = 2.0  # Time (seconds) of no player input before penalty starts
const INACTIVITY_EXP_BASE_MULTIPLIER: float = 1.4 # Base for exponential decay multiplier. e.g., 1.1 means decay increases by 10% of current penalty each second after threshold.
const INACTIVITY_MAX_PENALTY_MULTIPLIER: float = 20.0 # Cap the penalty multiplier to prevent insane decay.
# --- End of Inactivity Penalty ---

# Zones & Win/Loss Timings
const SAFE_ZONE_MIN: float = 40.0
const SAFE_ZONE_MAX: float = 70.0
const COOP_WIN_DURATION_SECONDS: float = 60.0
const DANGER_LOW_THRESHOLD: float = 20.0
const DANGER_HIGH_THRESHOLD: float = 85.0
const DANGER_TIME_LIMIT_SECONDS: float = 10.0

# UNSTABLE GRID Event
const UNSTABLE_GRID_DRAIN_PER_MASH: float = 0.5
const UNSTABLE_GRID_ELECTROCUTION_CHANCE_PERCENT: float = 15.0
const STASH_WIN_TARGET: float = 20.0

# Random Events
const EVENT_CHECK_INTERVAL_MS: float = 10000.0
const EVENT_CHANCE_PERCENT: float = 60.0
const EVENT_DURATION_MS: float = 8000.0

# Event Multipliers/Effects
const EVENT_EFFICIENCY_GAIN_MULTIPLIER: float = 3.0
const EVENT_SURGE_DECAY_MULTIPLIER: float = 2.5
const EVENT_SURGE_GAIN_REDUCTION_FACTOR: float = 0.5

# Event Types Enum
enum EventType { NONE, SURGE, EFFICIENCY, UNSTABLE_GRID }
const EVENT_TYPES: Array[EventType] = [EventType.SURGE, EventType.EFFICIENCY, EventType.UNSTABLE_GRID]

# --- Network Settings ---
const DEFAULT_UDP_PORT: int = 4210
const NUM_PLAYERS: int = 4
