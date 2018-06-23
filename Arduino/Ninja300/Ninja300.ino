#include <SoftwareSerial.h>
#include <EEPROM.h>
#include "kawa.h"
#include "led.h"
 
SoftwareSerial bt(12, 13); // RX, TX
Kawa kawa; // uses Serial so do not use it anywhere else (pins 0 and 1)
RgbLed led(9, 10, 11);

const unsigned long defaultFeedRate = 2000;
unsigned long feedRate = defaultFeedRate;

uint8_t registerWanted = 0;
unsigned long lastRequest = 0;
char sz[64];

void setup() {
  registerWanted = EEPROM.read(0);
  bt.begin(9600);
  sprintf(sz, "Hello! Target register: %d (0x%02X) @ %lu", registerWanted, registerWanted, feedRate);
  printMessage(sz);
  connectToBike();
}

void loop() {
  if (bt.available()) {
    readRequest();
    lastRequest = 0;
  }
  if (millis() - lastRequest >= feedRate) {
    if (kawa.getLastError() != 0) {
      connectToBike();
    }
    if (kawa.getLastError() == 0) {
      requestRegister();
    }
    lastRequest = millis();
  }
}

void printMessage(const char* message) {
  bt.println(message);
}

void readRequest() {
  String s = bt.readString();
  uint8_t oldReg = registerWanted;
  sscanf(s.c_str(), "%hhu %lu", &registerWanted, &feedRate);
  if (oldReg != registerWanted) {
    EEPROM.write(0, registerWanted);
  }
  sprintf(sz, "Target register: %d (0x%02X%s) @ %lu",
    registerWanted, registerWanted, oldReg != registerWanted ? ", new" : "", feedRate);
  printMessage(sz);
}

void connectToBike() {
  led.set(RgbLed::yellow);
  printMessage("Connecting...");
  if (kawa.initPulse()) {
    led.set(RgbLed::green);
    printMessage("Handshake succeed");
  } else {
    led.set(RgbLed::red);
    sprintf(sz, "Handshake failed with error %d", kawa.getLastError());
    printMessage(sz);
  }
}

void requestRegister() {
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
  sprintf(sz, "Done in %lu ms\n", finish - start);
  printMessage(sz);
  led.set(kawa.getLastError() == 0 ? RgbLed::green : RgbLed::red);
}

