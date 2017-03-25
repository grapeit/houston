#include <SoftwareSerial.h>
#include "kawa.h"
#include "led.h"
 
SoftwareSerial bt(12, 13); // RX, TX
Kawa kawa; // uses Serial so do not use it anywhere else (pins 0 and 1)
RgbLed led(9, 10, 11);

const unsigned long feedInterval = 2000;

uint8_t registerWanted = 0;
unsigned long lastRequest = 0;
char sz[64];

void printMessage(char* message) {
  bt.println(message);
}

void connectToBike() {
  led.set(RgbLed::yellow);
  printMessage("Connecting...");
  if (kawa.initPulse()) {
    led.set(RgbLed::green);
    printMessage("Handshake succeed");
  } else {
    led.set(RgbLed::red);
    sprintf(sz, "Handshake failed: %d", kawa.getLastError());
    printMessage(sz);
  }
}

void setup() {
  bt.begin(9600);
  printMessage("Hello");
  connectToBike();
}

void loop() {
  if (bt.available()) {
    String s = bt.readString();
    registerWanted = s.toInt();
    sprintf(sz, "Register 0x%02X (%d)", registerWanted, registerWanted);
    printMessage(sz);
    lastRequest = 0;
  }
  if (millis() - lastRequest >= feedInterval) {
    if (kawa.getLastError() != 0) {
      connectToBike();
    }
    if (kawa.getLastError() == 0) {
      led.set(RgbLed::blue);
      uint8_t response[16];
      unsigned long start = millis();
      uint8_t r = kawa.requestRegister(registerWanted, response, sizeof response);
      unsigned long finish = millis();
      int s = sprintf(sz, "Response for %d (%d): ", registerWanted, r);
      for (int i = 0; i < r; ++i) {
        s += sprintf(sz + s, "%02X", response[i]);
      }
      strcat(sz, "\n");
      printMessage(sz);
      sprintf(sz, "Done in %d ms\n");
      printMessage(sz);
      led.set(kawa.getLastError() == 0 ? RgbLed::green : RgbLed::red);
    }
    lastRequest = millis();
  }
}

