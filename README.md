# Energy Grid Control

**Concept:**

Energy Grid Control is a local multiplayer game where players collaborate (or compete) to manage a volatile power grid. The Godot application serves as the main display and game server, while players use *external physical controllers* (like ESP32 devices) sending UDP commands over the local network to interact with the game.

**Gameplay:**

*   **The Grid:** The central element is the energy bar, representing the power grid's charge level. It naturally decays over time.
*   **Zones:** The bar has defined zones:
    *   **Danger Low:** Energy is critically low. Risk of grid shutdown.
    *   **Warning Low:** Energy is low.
    *   **Safe Zone:** The ideal operating range.
    *   **Warning High:** Energy is high.
    *   **Danger High:** Energy is critically high. Risk of meltdown.
*   **Goal:**
    *   **Cooperative Win:** Keep the energy level within the Safe Zone for a cumulative target duration (e.g., 60 seconds).
    *   **Individual Win:** Accumulate a target amount of personal "stashed" energy by using the "Divert Power" action.
*   **Loss Conditions:**
    *   **Shutdown:** Spending too long in the Danger Low zone.
    *   **Meltdown:** Spending too long in the Danger High zone.
*   **Player Actions (via UDP):**
    *   `generate`: Increases the grid energy level.
    *   `stabilize`: Temporarily slows energy decay and reduces energy gain (global effect). Has a cooldown.
    *   `emergencyAdjust`: Provides a large energy boost if in Danger Low, or a large energy reduction if in Danger High. Penalizes energy if used outside danger zones. Has a cooldown.
    *   `stealGrid` (Divert Power): Drains a small amount of energy from the grid and adds it to the player's personal stash. Required for the individual win condition. Has a cooldown.
*   **Random Events:** Periodically, events like "Demand Surge" (increased decay) or "Efficiency Drive" (increased gain) can occur, temporarily altering game parameters.

**How it Works (Technical):**

1.  **Godot Application (Server/Display):** The Godot project runs the `Display.tscn` scene. The `GameManager` node within it handles all game logic, state, and win/loss conditions.
2.  **UDP Listener:** The `UdpManager` (autoload singleton) listens for incoming UDP packets on a specific port (default: 4210).
3.  **External Controllers:** Players use separate devices (e.g., ESP32s with buttons) programmed to send UDP packets to the IP address of the computer running the Godot application, on the correct port.
4.  **Command Format:** Controllers must send commands as strings in the format `P<player_id>:<action_name>`.
    *   Examples: `P1:generate`, `P3:stabilize`, `P4:stealGrid`
    *   Player IDs typically range from 1 to 4 (configurable in `Config.gd`).
5.  **Game Updates:** The `GameManager` processes valid commands, updates the game state, and emits signals that the `Display.gd` script uses to update the on-screen visuals (energy bar, player indicators, status messages). Player indicators show individual stash and cooldown status.

**Setup:**

1.  Run the Godot project (`MainMenu.tscn` is the entry point).
2.  The Main Menu will display the local IP address of the machine running Godot and the listening UDP port.
3.  Configure your external controllers (ESP32s, etc.) to send their UDP command packets to that specific IP address and port.
4.  Ensure the controllers send commands in the correct `P<id>:<action>` format.
5.  Click "Start Local Game" on the Godot application's main menu.
6.  The game display will appear, showing indicators for each player and the main energy grid.

**Controls (External Device Commands):**

*   `generate`
*   `stabilize`
*   `emergencyAdjust`
*   `stealGrid`

**Status:**

This is a functional prototype demonstrating the core mechanics with UDP-based external controller input.