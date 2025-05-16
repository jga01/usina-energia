#include <Arduino.h>
#include <WiFi.h>       // For WiFi connectivity
#include <WiFiUdp.h>    // For UDP communication

// --- WiFi Configuration ---
const char* ssid = "Jesus te Ama";         // <<-- REPLACE with your WiFi network name
const char* password = "joao316!"; // <<-- REPLACE with your WiFi password

// --- Network Configuration ---
const char* godotIpAddress = "172"; // <<-- REPLACE with Godot PC's IP
const int godotPort = 4210;

// --- UDP Object ---
WiFiUDP udp;

// --- Button Configuration ---
const unsigned long DEBOUNCE_DELAY = 50; // ms
const int NUM_PLAYERS = 4; // We have 4 players, each with one button

// Each player gets ONE button. This array maps Player Index (0-3) to their button pin.
const int PLAYER_BUTTON_PINS[NUM_PLAYERS] = {
    22, // Player 1 (index 0) Button Pin
    23, // Player 2 (index 1) Button Pin
    19, // Player 3 (index 2) Button Pin
    21  // Player 4 (index 3) Button Pin
    // !!! UPDATE THESE PINS TO YOUR ACTUAL WIRING !!!
};

const String PLAYER_ACTION_COMMAND = "mash"; // The command Godot expects

// --- Status LED Configuration (Unchanged) ---
const int STATUS_LED_PIN = 2;
const int LED_ON_STATE = HIGH;
const int LED_OFF_STATE = LOW;
const unsigned long BLINK_INTERVAL_CONNECTING = 500;
const unsigned long BLINK_INTERVAL_ERROR = 150;

// --- Simplified Button State Structure ---
// We now have an array of these, one for each player's button
struct ButtonState {
  int pin;
  int lastSteadyState;      // LOW if pressed, HIGH if not (due to PULLUP)
  int lastFlickerState;     // For debouncing
  unsigned long lastDebounceTime;
};
ButtonState playerButtons[NUM_PLAYERS]; // Array for each player's single button

// --- Global State Variables (Unchanged) ---
bool isWifiConnected = false;
unsigned long lastLedToggleTime = 0;
int currentLedState = LED_OFF_STATE;
unsigned long currentBlinkInterval = BLINK_INTERVAL_CONNECTING;

// --- Helper Function: Setup Button (Assigns pin to the button state) ---
void setupPlayerButton(ButtonState &button, int pin) {
  button.pin = pin;
  pinMode(pin, INPUT_PULLUP); // Assuming buttons connect pin to GND when pressed
  button.lastSteadyState = digitalRead(pin);
  button.lastFlickerState = button.lastSteadyState;
  button.lastDebounceTime = 0;
}

// --- Helper Function: Send Action via UDP (Action string is now fixed) ---
void sendPlayerAction(int playerId) { // PlayerId is 0-indexed here (0 for P1, 1 for P2, etc.)
  if (!isWifiConnected) {
    return;
  }

  // Player IDs are 1-based for Godot
  String command = "P" + String(playerId + 1) + ":" + PLAYER_ACTION_COMMAND;

  udp.beginPacket(godotIpAddress, godotPort);
  udp.write((uint8_t*)command.c_str(), command.length());
  udp.endPacket();

  Serial.print("UDP TX -> "); Serial.print(godotIpAddress); Serial.print(":"); Serial.print(godotPort);
  Serial.print(" | P"); Serial.print(playerId + 1); Serial.print(":"); Serial.println(PLAYER_ACTION_COMMAND);
}

// --- Helper Function: Update Status LED (Unchanged) ---
void updateStatusLed(unsigned long now) {
    if (isWifiConnected) {
        if (currentLedState != LED_ON_STATE) {
             digitalWrite(STATUS_LED_PIN, LED_ON_STATE);
             currentLedState = LED_ON_STATE;
        }
    } else {
        if (now - lastLedToggleTime >= currentBlinkInterval) {
            lastLedToggleTime = now;
            currentLedState = (currentLedState == LED_ON_STATE) ? LED_OFF_STATE : LED_ON_STATE;
            digitalWrite(STATUS_LED_PIN, currentLedState);
        }
    }
}

// --- Main Setup (Largely unchanged, but button setup is simplified) ---
void setup() {
  Serial.begin(115200);
  Serial.println("ESP32 Single Button Per Player Controller Starting...");

  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LED_OFF_STATE);
  currentLedState = LED_OFF_STATE;
  lastLedToggleTime = millis();
  currentBlinkInterval = BLINK_INTERVAL_CONNECTING;

  Serial.print("Connecting to ");
  Serial.println(ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  unsigned long connectionStartTime = millis();
  bool currentlyConnected = false;
  while (millis() - connectionStartTime < 20000) { // ~20 second timeout
      currentlyConnected = (WiFi.status() == WL_CONNECTED);
      if (currentlyConnected) break;
      unsigned long now = millis();
       if (now - lastLedToggleTime >= currentBlinkInterval) {
            lastLedToggleTime = now;
            currentLedState = (currentLedState == LED_ON_STATE) ? LED_OFF_STATE : LED_ON_STATE;
            digitalWrite(STATUS_LED_PIN, currentLedState);
       }
       delay(10);
  }

  if (currentlyConnected) {
    isWifiConnected = true;
    digitalWrite(STATUS_LED_PIN, LED_ON_STATE);
    currentLedState = LED_ON_STATE;
    Serial.println("\nWiFi connected!");
    Serial.print("ESP32 IP address: "); Serial.println(WiFi.localIP());
    Serial.print("Target Godot IP: "); Serial.println(godotIpAddress);
    Serial.print("Target Godot Port: "); Serial.println(godotPort);
  } else {
    isWifiConnected = false;
    currentBlinkInterval = BLINK_INTERVAL_ERROR;
    digitalWrite(STATUS_LED_PIN, LED_OFF_STATE);
    currentLedState = LED_OFF_STATE;
    lastLedToggleTime = millis();
    Serial.println("\nWiFi connection FAILED! Check SSID/Password/Signal.");
  }

  // Initialize each player's single button
  for (int i = 0; i < NUM_PLAYERS; ++i) {
    setupPlayerButton(playerButtons[i], PLAYER_BUTTON_PINS[i]);
  }

  Serial.println("Controller Initialized.");
}

// --- Main Loop (Simplified Button Processing) ---
void loop() {
  unsigned long now = millis();

  // --- Check WiFi Status & Update LED/State (Unchanged) ---
  bool currentConnectionStatus = (WiFi.status() == WL_CONNECTED);
  if (currentConnectionStatus != isWifiConnected) {
      isWifiConnected = currentConnectionStatus;
      if (isWifiConnected) {
          Serial.println("WiFi (Re)Connected.");
          digitalWrite(STATUS_LED_PIN, LED_ON_STATE);
          currentLedState = LED_ON_STATE;
      } else {
          Serial.println("WiFi Disconnected! Entering error state.");
          currentBlinkInterval = BLINK_INTERVAL_ERROR;
          lastLedToggleTime = now;
          currentLedState = LED_OFF_STATE;
          digitalWrite(STATUS_LED_PIN, currentLedState);
      }
  }
  updateStatusLed(now);


  // --- Process Buttons ONLY if WiFi is connected ---
  if (isWifiConnected) {
    for (int i = 0; i < NUM_PLAYERS; ++i) { // Iterate through each player's button
      ButtonState &btn = playerButtons[i];
      int currentReading = digitalRead(btn.pin);

      // Debouncing
      if (currentReading != btn.lastFlickerState) {
        btn.lastDebounceTime = now;
        btn.lastFlickerState = currentReading;
      }

      if ((now - btn.lastDebounceTime) > DEBOUNCE_DELAY) {
        // If the button state has changed (i.e., the debounced value is different)
        if (currentReading != btn.lastSteadyState) {
          btn.lastSteadyState = currentReading;

          // Check if the button was PRESSED (went from HIGH to LOW because of INPUT_PULLUP)
          if (btn.lastSteadyState == LOW) {
            // Player ID is 'i' (0-indexed for Player 1 to 4)
            sendPlayerAction(i); // Send the generic "mash" action for this player
          }
        }
      }
    } // End for loop (players)
  } // End if(isWifiConnected) for button processing

  delay(5); // Small delay
}