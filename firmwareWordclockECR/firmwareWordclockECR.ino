
/*
    Based on Neil Kolban example for IDF: https://github.com/nkolban/esp32-snippets/blob/master/cpp_utils/tests/BLE%20Tests/SampleServer.cpp
    Ported to Arduino ESP32 by Evandro Copercini
    updates by chegewara
*/

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

#include <WiFi.h>
#include "time.h"
#include <FastLED.h>
#include <ESP32Time.h>
ESP32Time rtc(0);
#include <Arduino.h>
#include <IRremote.hpp>

#include <Preferences.h>

Preferences preferences;

#include <Espalexa.h>
Espalexa espalexa;
void worclockAlexaChanged(uint8_t brightness);

#define NUM_LEDS 114
#define DATA_PIN 4
#define CLOCK_PIN 10
#define TOUCH_PIN 5
#define IR_RECEIVE_PIN 33

// See the following for generating UUIDs:
// https://www.uuidgenerator.net/

#define SERVICE_UUID        "a5f125c0-7cec-4334-9214-58cffb8706c0"
#define CHARACTERISTIC_UUID_RX "a5f125c2-7cec-4334-9214-58cffb8706c0"
#define CHARACTERISTIC_UUID_TX "a5f125c1-7cec-4334-9214-58cffb8706c0"

bool deviceConnected = false;
bool advertising = false;
bool wifiConfigured = false;
bool initialBLEConnect = true;
bool noCredentialsFound = false;
bool alexaActivated = false;
char ssid[64] = {};
char password[64] = {};

long wifiTimeOutTimer = 0;

//------------------------BLUETOOTH---------------------------------------------------------------------------

BLECharacteristic wordclockRxCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_NOTIFY);
BLECharacteristic wordclockTxCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_WRITE);
BLEDescriptor wordclockRxDescriptor(BLEUUID((uint16_t)0x2902));

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("BLE disconnected");
    }
};

//------------------------BLUETOOTH_CALLBACK---------------------------------------------------------------------------
class incomingCallbackHandler: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* wordclockTxCharacteristic) {
      char *incomingMessage = (char*)wordclockTxCharacteristic->getValue().c_str();
      Serial.print("message received: ");
      Serial.println(incomingMessage);
      char test[64] = {};
      strcpy(test, incomingMessage);
      char *messagePart;
      char delimiter[] = ",";
      messagePart = strtok(test, ",");
      if (messagePart = "#wifi") {
        messagePart = strtok(NULL, delimiter);
        memcpy(ssid, messagePart, strlen(messagePart));
        Serial.print("ssid: ");
        Serial.println(messagePart);
        messagePart = strtok(NULL, delimiter);
        memcpy(password, messagePart, strlen(messagePart));
        Serial.print("password: ");
        Serial.println(messagePart);
        wifiConfigured = true;
        if (noCredentialsFound) {
          preferences.remove(ssid);
          preferences.remove(password);
        }
        preferences.putString("ssid", ssid);
        preferences.putString("password", password);
      } else if (messagePart = "#kill") {
        delay(2000);
        ESP.restart();
      } else if (messagePart = "#alexaOn") {
        alexaActivated = true;
      } else if (messagePart = "#alexaOff") {
        alexaActivated = false;
      }
    }
};

//------------------------REST---------------------------------------------------------------------------

// Define the array of leds
CRGB leds[NUM_LEDS];


const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 3600;
const int   daylightOffset_sec = 3600;

struct color {
  byte h;
  byte s;
  byte b;
};

struct currentTime {
  uint8_t hours;
  uint8_t minutes;
  uint8_t seconds;
};

uint8_t vor [] = {3, 74};
uint8_t nach [] = {4, 69};

uint8_t ein [] = {3, 48};
uint8_t eins [] = {4, 48};
uint8_t zwei [] = {4, 46};
uint8_t drei [] = {4, 41};
uint8_t vier [] = {4, 31};
uint8_t fuenf [] = {4, 35};
uint8_t sechs [] = {5, 2};
uint8_t sieben [] = {6, 51};
uint8_t acht [] = {4, 19};
uint8_t neun [] = {4, 27};
uint8_t zehn [] = {4, 15};
uint8_t elf [] = {3, 24};
uint8_t zwoelf [] = {5, 58};

uint8_t es [] = {2, 111};
uint8_t ist [] = {3, 107};

uint8_t fuenfMin [] = {4, 102};
uint8_t zehnMin [] = {4, 90};
uint8_t viertel [] = {7, 79};
uint8_t zwanzig [] = {7, 94};
uint8_t halb [] = {4, 64};

uint8_t uhr [] = {3, 9};
uint8_t uhrleds [] = {0, 113, 101, 12};

bool clockON = true;
bool debouncer = false;
bool debouncerTouch = false;
bool updateCorners = true;
bool updateWords = true;
bool updateTime = true;
bool partyMode = false;



color uhrfarbe = {125, 255, 255};
currentTime t = {0, 0};
struct tm timeinfo;

//prototype
void setWord(uint8_t wordLeds[], boolean indice = true);
void setWord(uint8_t wordLeds[], boolean indice) {
  if (indice) {
    for (int i = 0; i < wordLeds[0]; i++) {
      leds[wordLeds[1] + i] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
      Serial.println(wordLeds[1] + i);
      Serial.println("indice true");
    }
  } else {
    for (int i = 0; i < sizeof(wordLeds) / sizeof(uint8_t); i++) {
      leds[wordLeds[i]] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
      Serial.println(wordLeds[i]);
    }
  }
}

/*void updateTime() {

  }
*/

void wordclockAlexaChanged(EspalexaDevice* wordclockAlexa) {
  setUhrfarbe(wordclockAlexa->getHue(),wordclockAlexa->getSat(),wordclockAlexa->getPercent()*2.55);

}

void handleIRCommand(uint8_t cmd) {
  Serial.println(cmd);
  switch (cmd) {
    case 0:
      if (uhrfarbe.b < 245) {
        uhrfarbe.b = uhrfarbe.b + 10;
      }
      break;
    case 1:
      if (uhrfarbe.b > 20) {
        uhrfarbe.b = uhrfarbe.b - 10;
      }
      break;
    case 2:
      clockON = false;
      break;
    case 3:
      clockON = true;
      break;
    case 4: //red
      setUhrfarbe(0,255,255);
      break;
    case 5: //green
      setUhrfarbe(96,255,255);
      break;
    case 6: //blue
      setUhrfarbe(160,255,255);
      break;
    case 7: //white
      setUhrfarbe(0,0,255);
      break;
    case 8: //orange
      setUhrfarbe(32,255,255);
      break;
    case 9: //light green
      setUhrfarbe(105,255,255);
      break;
    case 10: //light blue
      setUhrfarbe(175,255,255);
      break;
    case 11: //flash
      if (partyMode) {
        partyMode = false;
        updateWords = true;
        updateCorners = true;
      } else {
        partyMode = true;
      }
      break;
    case 12: //light orange
      setUhrfarbe(32,255,255);
      break;
    case 13: //aqua
      setUhrfarbe(128,255,255);
      break;
    case 14: //purple
      setUhrfarbe(192,255,255);
      break;
    case 15:  //strobe

      break;
    case 16: //very light orange
      setUhrfarbe(32,255,255);
      break;
    case 17: //marine
      setUhrfarbe(140,255,255);
      break;
    case 18: //light purple
      setUhrfarbe(192,200,255);
      break;
    case 19: //fade
//
      break;
    case 20: //yellow
      setUhrfarbe(64,255,255);
      break;
    case 21: //dark aqua
      setUhrfarbe(150,255,150);
      break;
    case 22: //pink
      setUhrfarbe(224,255,255);
      break;
    case 23: //smooth
//
      break;
  }
  Serial.println("handled IR Command");
}

void IRAM_ATTR TOUCH_ISR() {
  if (clockON) {
    clockON = false;
  } else {
    clockON = true;
    updateWords = true;
    updateCorners = true;
  }
}

void printLocalTime() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    Serial.println("Failed to obtain time");
    return;
  }
  Serial.println(&timeinfo, "%A, %B %d %Y %H:%M:%S");
}

void updateRTC() {
  configTime(0, 0, ntpServer);
  setenv("TZ","CET-1CEST,M3.5.0,M10.5.0/3",1);
  tzset();
  struct tm timeinfo;
}

void setUhrfarbe(byte hue, byte saturation, byte brightness) {
  uhrfarbe.h = hue;
  uhrfarbe.s = saturation;
  uhrfarbe.b = brightness;
}
//------------------------SETUP---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  preferences.begin("credentials", false);
  String readout = preferences.getString("ssid", "");
  strcpy(ssid, readout.c_str());
  if (ssid[0] != '\0') {
    wifiConfigured = true ;
    readout = preferences.getString("password", "");
    strcpy(password, readout.c_str());
    noCredentialsFound = false;
  } else {
    wifiConfigured = false;
    noCredentialsFound = true;
  }
  if (wifiConfigured) {
    Serial.println(ssid);
    Serial.println(password);
  }
  FastLED.addLeds<NEOPIXEL, DATA_PIN>(leds, NUM_LEDS);
  Serial.println("Starting BLE work!");

  // Create the BLE Device
  BLEDevice::init("wordclock");

  // Create the BLE Server
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *comService = pServer->createService(SERVICE_UUID);

  comService->addCharacteristic(&wordclockTxCharacteristic);
  comService->addCharacteristic(&wordclockRxCharacteristic);
  wordclockRxCharacteristic.addDescriptor(&wordclockRxDescriptor);

  wordclockTxCharacteristic.setCallbacks(new incomingCallbackHandler());
  // Start the service
  comService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pServer->getAdvertising()->start();
  Serial.println("Waiting a client connection to notify...");
  advertising = true;
  //---------------------------SETUP_LOOP-----------------------
  int i = 0;
  long blinkTimer = 0;
  while (1) {
    if (millis() - blinkTimer > 500) {
      leds[uhrleds[i]] = CHSV(0, 0, 255);
      if (i > 0) {
        leds[uhrleds[i - 1]] = CHSV(0, 0, 0);
      } else {
        leds[uhrleds[3]] = CHSV(0, 0, 0);
      }
      FastLED.show();
      i++;
      if (i > 3) {
        i = 0;
      }
      blinkTimer = millis();
    }
    if (deviceConnected) {
      if (initialBLEConnect) {
        Serial.println("Bluetooth connected");
        initialBLEConnect = false;
        setUhrfarbe(160, 255, 255);
        setWord(uhrleds, false);
        FastLED.show();
        delay(1000);
        setUhrfarbe(0, 0, 0);
        setWord(uhrleds, false);
        FastLED.show();
      } 
    }
    if (wifiConfigured) {
      delay(500);
      WiFi.begin(ssid, password);
      wifiTimeOutTimer = millis();
      while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
        if (millis() - wifiTimeOutTimer > 10000) {
          wordclockRxCharacteristic.setValue("wifiFailed");
          wordclockRxCharacteristic.notify();
          wifiConfigured = false;
        }
      }
      if (WiFi.status() == WL_CONNECTED) {
        Serial.println("WiFi connected.");
        wifiConfigured = false;
        char value[] = "stat,co,";
        strcat(value, ssid);
        wordclockRxCharacteristic.setValue(value);
        wordclockRxCharacteristic.notify();
        setUhrfarbe(96, 255, 255);
        setWord(uhrleds, false);
        FastLED.show();
        delay(1000);
        setUhrfarbe(0, 0, 0);
        setWord(uhrleds, false);
        FastLED.show();
        break;
      }
    }
  }
  FastLED.clear();

  updateRTC();
  printLocalTime();
  IrReceiver.begin(IR_RECEIVE_PIN, ENABLE_LED_FEEDBACK);
  Serial.println("loop begins");
  setUhrfarbe(0, 255, 255);
  if(alexaActivated){
    espalexa.addDevice("wordclock", wordclockAlexaChanged, EspalexaDeviceType::color);
    espalexa.begin();
  }
}
//--------------------LOOP-----------------------------------------
void loop() {
  if(alexaActivated){
    espalexa.loop();
  }
  t.hours = rtc.getHour();
  t.minutes = rtc.getMinute();
  t.seconds = rtc.getSecond();
  //Serial.print(t.hours);
  //Serial.print(":");
  //Serial.print(t.minutes);
  //Serial.print(":");
  //Serial.println(t.seconds);
  if (IrReceiver.decode()) {
    IrReceiver.resume(); // Enable receiving of the next value
    handleIRCommand(IrReceiver.decodedIRData.command);
    updateWords = true;
    updateCorners = true;
  }
  if (partyMode) {
    FastLED.clear();
    FastLED.show();
    for (int i = 0; i < 4; i++) {
      leds[random(0, 113)] = CHSV(random(0, 255), random(0, 255), uhrfarbe.b);
    }
    FastLED.show();
    delay(200);
    return;
  }

  if (t.seconds == 0 && t.minutes == 0 && updateTime) {
    updateRTC();
    updateTime = false;
  }

  if (!updateTime && t.minutes != 0) {
    updateTime = true;
  }

  if (t.seconds == 0 && !debouncer) {
    updateCorners = true;
    if (t.minutes % 5 == 0) {
      updateWords = true;
    }
    debouncer = true;
  }
  if (t.seconds != 0 && debouncer) {
    debouncer = false;
  }

  if (clockON) {
    int minutedivision = t.minutes % 5; //modulo 5 für äußere minutenanzeige
       if (updateWords) {
      FastLED.clear();
      setWord(es);
      setWord(ist);
      if (t.minutes > 24) {
        t.hours = t.hours + 1;
      }
      t.hours = t.hours % 12;
      switch (t.hours) {
        case 1:
          if (t.minutes >= 5) {
            setWord(eins);
          } else {
            setWord(ein);
          }
          break;
        case 2:
          setWord(zwei);
          break;
        case 3:
          setWord(drei);
          break;
        case 4:
          setWord(vier);
          break;
        case 5:
          setWord(fuenf);
          break;
        case 6:
          setWord(sechs);
          break;
        case 7:
          setWord(sieben);
          break;
        case 8:
          setWord(acht);
          break;
        case 9:
          setWord(neun);
          break;
        case 10:
          setWord(zehn);
          break;
        case 11:
          setWord(elf);
          break;
        case 0:
          setWord(zwoelf);
          break;
      }

      //es ist x "UHR" minuten
      if (t.minutes <= 4) {
        setWord(uhrleds);
      }
      int minuteStep = t.minutes - minutedivision;
      switch (minuteStep) {
        case 5:
          setWord(nach);
          setWord(fuenfMin);
          break;
        case 10:
          setWord(nach);
          setWord(zehnMin);
          break;
        case 15:
          setWord(nach);
          setWord(viertel);
          break;
        case 20:
          setWord(nach);
          setWord(zwanzig);
          break;
        case 25:
          setWord(vor);
          setWord(fuenfMin);
          setWord(halb);
          break;
        case 30:
          setWord(halb);
          break;
        case 35:
          setWord(nach);
          setWord(fuenfMin);
          setWord(halb);
          break;
        case 40:
          setWord(vor);
          setWord(zwanzig);
          break;
        case 45:
          setWord(vor);
          setWord(viertel);
          break;
        case 50:
          setWord(vor);
          setWord(zehnMin);
          break;
        case 55:
          setWord(vor);
          setWord(fuenfMin);
          break;
      }
      updateWords = false; 
    }
    if (updateCorners) {
      switch (minutedivision) {
        case 1:
          leds[0] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          break;
        case 2:
          leds[0] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          leds[113] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          break;
        case 3:
          leds[0] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          leds[113] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);  
          leds[101] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          break;
        case 4:
          leds[0] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          leds[113] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          leds[101] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          leds[12] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
          break;
      }
      FastLED.show();
      updateCorners = false;
    }
   

  } else {
    FastLED.clear();
    FastLED.show();
  }
}
