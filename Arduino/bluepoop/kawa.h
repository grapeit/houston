#include <SoftwareSerial.h>

class Kawa {
private:
  const uint32_t responseByteDelay = 8; // Ninja 300 works with 7, does not work with 6
  const uint32_t delayBetweenRequests = 30; // Time between requests.
  const uint32_t maxSendTime = 5000; // 5 second timeout on KDS comms.
  const uint8_t ecuAddr = 0x11;
  const uint8_t myAddr = 0xF2;

  const byte      m_rx = 0;
  const byte      m_tx = 1;

  unsigned long   m_lastRequest = 0;
  int             m_lastError = 0;

public:
  int getLastError() const { return m_lastError; }
 
  bool initPulse() {
    uint8_t rLen;
    uint8_t req[2];
    uint8_t resp[3];

    Serial.end();
    pinMode(m_rx, INPUT);
    pinMode(m_tx, OUTPUT);
    
    // This is the ISO 14230-2 "Fast Init" sequence.
    digitalWrite(m_tx, HIGH);
    delay(300);
    digitalWrite(m_tx, LOW);
    delay(25);
    digitalWrite(m_tx, HIGH);
    delay(25);
  
    Serial.begin(10400);
  
    // Start Communication is a single byte "0x81" packet.
    req[0] = 0x81;
    rLen = sendRequest(req, 1, resp, 3);
  
    // Response should be 3 bytes: 0xC1 0xEA 0x8F
    if ((rLen == 3) && (resp[0] == 0xC1) && (resp[1] == 0xEA) && (resp[2] == 0x8F)) {
      // Success, so send the Start Diag frame
      // 2 bytes: 0x10 0x80
      req[0] = 0x10;
      req[1] = 0x80;
      rLen = sendRequest(req, 2, resp, 3);

      // OK Response should be 2 bytes: 0x50 0x80
      if ((rLen == 2) && (resp[0] == 0x50) && (resp[1] == 0x80)) {
        m_lastError = 0;
        return true;
      } else {
        m_lastError = 2;
      }
    }
    // Otherwise, we failed to init.
    m_lastError = 1;
    return false;
  }

  uint8_t requestRegister(uint8_t reg, uint8_t* response, uint8_t maxResponseLength) {
    uint8_t cmd[2] = {0x21, reg};
    uint8_t resp[16];
    uint8_t s = sendRequest(cmd, sizeof cmd, resp, sizeof resp);
    if (s >= 3 && resp[0] == 0x61 && resp[1] == reg) { // good response for requested register
      uint8_t rs = min(maxResponseLength, s - 2);
      memcpy(response, resp + 2, rs);
      return rs;
    }
    return 0;
  }

 private:
  // send a request to the ESC and wait for the response
  // request = buffer to send
  // reqLen = length of request
  // response = buffer to hold the response
  // maxResponseLength = maximum size of response buffer
  //
  // Returns: number of bytes of response returned.
  uint8_t sendRequest(const uint8_t *request, uint8_t reqLen, uint8_t *response, uint8_t maxResponseLength) {
    uint8_t buf[16], rbuf[16];
    uint8_t bytesToSend;
    uint8_t bytesToRcv = 0;
    uint8_t bytesRcvd = 0;
    uint8_t rCnt = 0;
    uint8_t c;
    bool forMe = false;

    memset(buf, 0, sizeof buf);
    memset(response, 0, maxResponseLength);
  
    // Form the request:
    if (reqLen == 1) {
      buf[0] = 0x81;
    } else {
      buf[0] = 0x80;
    }
    buf[1] = ecuAddr;
    buf[2] = myAddr;
    if (reqLen == 1) {
      buf[3] = request[0];
      buf[4] = calcChecksum(buf, 4);
      bytesToSend = 5;
    } else {
      buf[3] = reqLen;
      memcpy(buf + 4, request, reqLen);
      buf[4 + reqLen] = calcChecksum(buf, 4 + reqLen);
      bytesToSend = 5 + reqLen;
    }

    unsigned long startTime = millis();
    if (startTime - m_lastRequest < delayBetweenRequests) { // I doubt this condition will ever be triggered
      delay(delayBetweenRequests - (startTime - m_lastRequest));
    }

    Serial.write(buf, bytesToSend);

    startTime = millis();
 
    // Wait for and deal with the reply
    while ((bytesRcvd <= maxResponseLength) && ((millis() - startTime) < maxSendTime)) {
      delay(responseByteDelay);
      if (Serial.available()) {
        c = Serial.read();
        startTime = millis(); // reset the timer on each byte received
        rbuf[rCnt] = c;
        switch (rCnt) {
        case 0:
          // should be an addr packet either 0x80 or 0x81
          if (c == 0x81) {
            bytesToRcv = 1;
          } else if (c == 0x80) {
            bytesToRcv = 0;
          }
          rCnt++;
          break;
        case 1:
          // should be the target address
          if (c == myAddr) {
            forMe = true;
          }
          rCnt++;
          break;
        case 2:
          // should be the sender address
          if (c == ecuAddr) {
            forMe = true;
          } else if (c == myAddr) {
            forMe = false; // ignore the packet if it came from us!
          }
          rCnt++;
          break;
        case 3:
          // should be the number of bytes, or the response if its a single byte packet.
          if (bytesToRcv == 1) {
            bytesRcvd++;
            if (forMe) {
              response[0] = c; // single byte response so store it.
            }
          } else {
            bytesToRcv = c; // number of bytes of data in the packet.
          }
          rCnt++;
          break;
        default:
          if (bytesToRcv == bytesRcvd) {
            // must be at the checksum...
            if (forMe) {
              // Only check the checksum if it was for us - don't care otherwise!
              if (calcChecksum(rbuf, rCnt) == rbuf[rCnt]) {
                // Checksum OK.
                return(bytesRcvd);
              } else {
                // Checksum Error.
                return(0);
              }
            }
            // Reset the counters
            rCnt = 0;
            bytesRcvd = 0;
          } else {
            // must be data, so put it in the response buffer
            // rCnt must be >= 4 to be here.
            if (forMe) {
              response[bytesRcvd] = c;
            }
            bytesRcvd++;
            rCnt++;
          }
          break;
        }
      }
    }
    m_lastError = -1;
    return 0;
  }
  
  // Checksum is simply the sum of all data bytes modulo 0xFF
  // (same as being truncated to one byte)
  uint8_t calcChecksum(uint8_t *data, uint8_t len) {
    uint8_t crc = 0;
    for (uint8_t i = 0; i < len; i++) {
      crc = crc + data[i];
    }
    return crc;
  }
};

