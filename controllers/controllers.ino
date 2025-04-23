#include <Arduino.h>
#include <WiFi.h>       // For WiFi connectivity
#include <WiFiUdp.h>    // For UDP communication

// --- WiFi Configuration ---
const char* ssid = "brisa-2206203";         // <<-- REPLACE with your WiFi network name
const char* password = "ok6gysuy"; // <<-- REPLACE with your WiFi password

// --- Network Configuration ---
// IP address of the computer running Godot. Find this using 'ipconfig' (Windows) or 'ip addr' (Linux/macOS)
// It's best to set a static IP for the Godot machine on your router if possible.
const char* godotIpAddress = "192.168.0.10";
const int godotPort = 4210;

// --- UDP Object ---
WiFiUDP udp;

// --- Button Configuration (Single Button per Player) ---
const unsigned long DEBOUNCE_DELAY = 50;
const unsigned long LONG_PRESS_THRESHOLD = 600;
const unsigned long MULTI_PRESS_WINDOW = 350;
const int NUM_PLAYERS = 4;

const int PLAYER_BUTTON_PINS[NUM_PLAYERS] = {
    22, // Player 1 Button Pin (Example GPIO)
    23, // Player 2 Button Pin (Example GPIO)
    19, // Player 3 Button Pin (Example GPIO)
    21  // Player 4 Button Pin (Example GPIO)
    // Make sure these pins match your actual wiring and are suitable inputs
};

// --- Status LED Configuration ---
const int STATUS_LED_PIN = 2; // Usually GPIO 2 on many boards
const int LED_ON_STATE = HIGH;
const int LED_OFF_STATE = LOW;
const unsigned long BLINK_INTERVAL_CONNECTING = 500; // ms (Slow blink)
const unsigned long BLINK_INTERVAL_ERROR = 150;     // ms (Fast blink)

// --- Button State Structure & Enum (Unchanged) ---
enum ButtonFsmState { STATE_IDLE, STATE_PRESSED, STATE_WAITING_FOR_NEXT };
struct PlayerButton {
  int pin;
  ButtonFsmState currentState;
  int lastSteadyState;
  int lastFlickerState;
  unsigned long lastDebounceTime;
  unsigned long pressStartTime;
  unsigned long multiPressTimeoutTime;
  int pressCount;
};
PlayerButton playerButtons[NUM_PLAYERS];

// --- Global State Variables ---
bool isWifiConnected = false;          // Track current connection status
unsigned long lastLedToggleTime = 0;   // For non-blocking LED blink
int currentLedState = LED_OFF_STATE;   // Track current LED state
unsigned long currentBlinkInterval = BLINK_INTERVAL_CONNECTING; // Controls blink speed

// --- Helper Function: Setup Button (Unchanged) ---
void setupPlayerButton(PlayerButton &button, int pin) {
  button.pin = pin;
  pinMode(pin, INPUT_PULLUP);
  button.lastSteadyState = digitalRead(pin);
  button.lastFlickerState = button.lastSteadyState;
  button.lastDebounceTime = 0;
  button.currentState = STATE_IDLE;
  button.pressStartTime = 0;
  button.multiPressTimeoutTime = 0;
  button.pressCount = 0;
}

// --- Helper Function: Send Action via UDP (Unchanged) ---
void sendAction(int playerId, const String& action) {
  // Only send if WiFi is actually connected
  if (!isWifiConnected) {
      // Serial.println("WARN: Tried to send action while WiFi disconnected.");
      return;
  }

  // Player IDs are 1-based for Godot
  String command = "P" + String(playerId + 1) + ":" + action;

  // Send UDP packet
  udp.beginPacket(godotIpAddress, godotPort);
  udp.write((uint8_t*)command.c_str(), command.length());
  udp.endPacket();

  // Optional: Serial debug output
  Serial.print("UDP TX -> "); Serial.print(godotIpAddress); Serial.print(":"); Serial.print(godotPort);
  Serial.print(" | P"); Serial.print(playerId + 1); Serial.print(":"); Serial.println(action);
}

// --- Helper Function: Update Status LED (Handles blinking) ---
void updateStatusLed(unsigned long now) {
    if (isWifiConnected) {
        // Solid ON if connected
        if (currentLedState != LED_ON_STATE) {
             digitalWrite(STATUS_LED_PIN, LED_ON_STATE);
             currentLedState = LED_ON_STATE;
        }
    } else {
        // Blink if not connected (connecting or error)
        if (now - lastLedToggleTime >= currentBlinkInterval) {
            lastLedToggleTime = now;
            currentLedState = (currentLedState == LED_ON_STATE) ? LED_OFF_STATE : LED_ON_STATE;
            digitalWrite(STATUS_LED_PIN, currentLedState);
        }
    }
}

// --- Main Setup ---
void setup() {
  Serial.begin(115200);
  Serial.println("ESP32 WiFi Controller Starting...");

  // --- Initialize LED ---
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LED_OFF_STATE); // Start with LED off
  currentLedState = LED_OFF_STATE;
  lastLedToggleTime = millis();
  currentBlinkInterval = BLINK_INTERVAL_CONNECTING; // Start with connecting blink rate

  // --- Connect to WiFi ---
  Serial.print("Connecting to ");
  Serial.println(ssid);
  WiFi.mode(WIFI_STA); // Set WiFi mode to Station explicitly
  WiFi.begin(ssid, password);

  unsigned long connectionStartTime = millis();
  bool currentlyConnected = false;

  // Connection attempt loop with timeout and LED blinking
  while (millis() - connectionStartTime < 20000) { // ~20 second timeout
      currentlyConnected = (WiFi.status() == WL_CONNECTED);
      if (currentlyConnected) {
          break; // Exit loop if connected
      }

      // Update LED while trying to connect (non-blocking blink)
      unsigned long now = millis();
       if (now - lastLedToggleTime >= currentBlinkInterval) {
            lastLedToggleTime = now;
            currentLedState = (currentLedState == LED_ON_STATE) ? LED_OFF_STATE : LED_ON_STATE;
            digitalWrite(STATUS_LED_PIN, currentLedState);
       }
       delay(10); // Small delay to allow ESP background tasks
  }


  // --- Check final connection result ---
  if (currentlyConnected) {
    isWifiConnected = true;
    currentBlinkInterval = 0; // Not needed when solid ON
    digitalWrite(STATUS_LED_PIN, LED_ON_STATE); // Ensure LED is ON
    currentLedState = LED_ON_STATE;

    Serial.println("");
    Serial.println("WiFi connected!");
    Serial.print("ESP32 IP address: ");
    Serial.println(WiFi.localIP());
    Serial.print("Target Godot IP: ");
    Serial.println(godotIpAddress);
    Serial.print("Target Godot Port: ");
    Serial.println(godotPort);
  } else {
    isWifiConnected = false;
    currentBlinkInterval = BLINK_INTERVAL_ERROR; // Set fast blink for error state
    digitalWrite(STATUS_LED_PIN, LED_OFF_STATE); // Start blink from OFF state
    currentLedState = LED_OFF_STATE;
    lastLedToggleTime = millis(); // Reset timer for error blink

    Serial.println("");
    Serial.println("WiFi connection FAILED! Check SSID/Password/Signal.");
    Serial.println("Controller will use error blink pattern.");
    // NOTE: We are NOT halting here. The main loop will handle the error state.
  }

  // --- Initialize Buttons (Unchanged) ---
  for (int i = 0; i < NUM_PLAYERS; ++i) {
    setupPlayerButton(playerButtons[i], PLAYER_BUTTON_PINS[i]);
  }

  Serial.println("Controller Initialized.");
}

// --- Main Loop ---
void loop() {
  unsigned long now = millis();

  // --- Check WiFi Status & Update LED/State ---
  bool currentConnectionStatus = (WiFi.status() == WL_CONNECTED);

  if (currentConnectionStatus != isWifiConnected) {
      // Connection status changed!
      isWifiConnected = currentConnectionStatus;
      if (isWifiConnected) {
          Serial.println("WiFi (Re)Connected.");
          currentBlinkInterval = 0; // Stop blinking
          digitalWrite(STATUS_LED_PIN, LED_ON_STATE);
          currentLedState = LED_ON_STATE;
      } else {
          Serial.println("WiFi Disconnected! Entering error state.");
          currentBlinkInterval = BLINK_INTERVAL_ERROR; // Start fast blink
          lastLedToggleTime = now; // Reset blink timer
          currentLedState = LED_OFF_STATE; // Start blink from off
          digitalWrite(STATUS_LED_PIN, currentLedState);
          // Optional: Attempt reconnection immediately or periodically
          // WiFi.disconnect(); // Ensure clean state before reconnecting?
          // WiFi.begin(ssid, password);
      }
  }

  // --- Update LED (Handles blinking if !isWifiConnected) ---
  updateStatusLed(now);


  // --- Process Buttons ONLY if WiFi is connected ---
  if (isWifiConnected) {
    for (int i = 0; i < NUM_PLAYERS; ++i) {
      PlayerButton &btn = playerButtons[i];

      // --- Debouncing Logic ---
      int currentReading = digitalRead(btn.pin);
      if (currentReading != btn.lastFlickerState) {
        btn.lastDebounceTime = now;
        btn.lastFlickerState = currentReading;
      }
      if ((now - btn.lastDebounceTime) > DEBOUNCE_DELAY) {
        if (currentReading != btn.lastSteadyState) {
          btn.lastSteadyState = currentReading;
          bool pressed = (btn.lastSteadyState == LOW);

          // --- State Machine Logic ---
          switch (btn.currentState) {
            case STATE_IDLE:
              if (pressed) {
                btn.currentState = STATE_PRESSED;
                btn.pressStartTime = now;
              }
              break;
            case STATE_PRESSED:
              if (!pressed) {
                unsigned long pressDuration = now - btn.pressStartTime;
                if (pressDuration >= LONG_PRESS_THRESHOLD) {
                  sendAction(i, "emergencyAdjust");
                  btn.pressCount = 0;
                  btn.currentState = STATE_IDLE;
                } else {
                  btn.pressCount++;
                  btn.currentState = STATE_WAITING_FOR_NEXT;
                  btn.multiPressTimeoutTime = now + MULTI_PRESS_WINDOW;
                }
              }
              break;
            case STATE_WAITING_FOR_NEXT:
              if (pressed) {
                btn.currentState = STATE_PRESSED;
                btn.pressStartTime = now;
              } else if (now >= btn.multiPressTimeoutTime) {
                if (btn.pressCount == 1) sendAction(i, "generate");
                else if (btn.pressCount == 2) sendAction(i, "stabilize");
                else if (btn.pressCount >= 3) sendAction(i, "stealGrid");
                btn.pressCount = 0;
                btn.currentState = STATE_IDLE;
              }
              break;
          } // End switch
        } // End if state changed
      } // End if stable

      // --- Handle Timeout While Waiting (Crucial Check) ---
      // This check needs to run even if the button state didn't change
      // in the debouncer, to catch the timeout itself.
      if (btn.currentState == STATE_WAITING_FOR_NEXT && now >= btn.multiPressTimeoutTime) {
          if (btn.pressCount == 1) sendAction(i, "generate");
          else if (btn.pressCount == 2) sendAction(i, "stabilize");
          else if (btn.pressCount >= 3) sendAction(i, "stealGrid");
          btn.pressCount = 0;
          btn.currentState = STATE_IDLE;
      }
    } // End for loop (players)
  } // End if(isWifiConnected) for button processing

  // Small delay to be friendly to the system, adjust if needed
  delay(5);
}