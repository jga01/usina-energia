# scripts/config.gd
extends Node

# Core Game Params
const MAX_ENERGY: float = 100.0
const MIN_ENERGY: float = 0.0
const BASE_ENERGY_DECAY_RATE: float = 0.7 # Adjusted, tune as needed
const BASE_ENERGY_GAIN_PER_MASH: float = 0.25 # Energy per single button press

# Zones & Win/Loss Timings
const SAFE_ZONE_MIN: float = 40.0
const SAFE_ZONE_MAX: float = 70.0
const COOP_WIN_DURATION_SECONDS: float = 60.0
const DANGER_LOW_THRESHOLD: float = 20.0
const DANGER_HIGH_THRESHOLD: float = 85.0
const DANGER_TIME_LIMIT_SECONDS: float = 10.0

# UNSTABLE GRID Event (Replaces old Steal Action)
const UNSTABLE_GRID_DRAIN_PER_MASH: float = 0.5 # Energy taken from grid & added to stash
const UNSTABLE_GRID_ELECTROCUTION_CHANCE_PERCENT: float = 15.0 # Chance per mash during this event
const STASH_WIN_TARGET: float = 20.0 # Target stash for individual win

# Random Events
const EVENT_CHECK_INTERVAL_MS: float = 10000.0 # Check for new event every 10s
const EVENT_CHANCE_PERCENT: float = 60.0 # Chance for an event to trigger
const EVENT_DURATION_MS: float = 8000.0 # Events last 8s

# Event Multipliers/Effects
const EVENT_EFFICIENCY_GAIN_MULTIPLIER: float = 3.0 # Mashing is 3x more effective
const EVENT_SURGE_DECAY_MULTIPLIER: float = 2.5 # Decay is 2.5x faster (applied to BASE_ENERGY_DECAY_RATE)
const EVENT_SURGE_GAIN_REDUCTION_FACTOR: float = 0.5 # Mashing is 50% less effective during surge

# Event Types Enum
enum EventType { NONE, SURGE, EFFICIENCY, UNSTABLE_GRID }
const EVENT_TYPES: Array[EventType] = [EventType.SURGE, EventType.EFFICIENCY, EventType.UNSTABLE_GRID]

# --- Network Settings ---
const DEFAULT_UDP_PORT: int = 4210 # Port Godot listens on
const NUM_PLAYERS: int = 4
