

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

#include <WiFi.h>
#include "time.h"
#include <FastLED.h>
#include <ESP32Time.h>
ESP32Time rtc(0);
#include <Arduino.h>
#include <IRremote.hpp>

#include <Espalexa.h>
#include <Preferences.h>

Preferences preferences;

void worclockAlexaChanged(uint8_t brightness);

#define NUM_LEDS 114
#define DATA_PIN 4
#define CLOCK_PIN 10
#define TOUCH_PIN 5
#define IR_RECEIVE_PIN 33

// See the following for generating UUIDs:
// https://www.uuidgenerator.net/

#define SERVICE_UUID "a5f125c0-7cec-4334-9214-58cffb8706c0"
#define CHARACTERISTIC_UUID_RX "a5f125c2-7cec-4334-9214-58cffb8706c0"
#define CHARACTERISTIC_UUID_TX "a5f125c1-7cec-4334-9214-58cffb8706c0"

bool deviceConnected = false;
bool advertising = false;
bool wifiConfigured = false;
bool initialBLEConnect = true;
bool noCredentialsFound = false;
bool alexaActivated = false;
bool notify = false;
char ssid[64] = {};
char password[64] = {};
bool alexaActivatedInitial = true;

long wifiTimeOutTimer = 0;

// Define the array of leds
CRGB leds[NUM_LEDS];

Espalexa espalexa;


//------------------------BLUETOOTH---------------------------------------------------------------------------

BLECharacteristic wordclockRxCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_NOTIFY);
BLECharacteristic wordclockTxCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_WRITE);


class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    //Serial.println("ble connected");
    if (WiFi.status() == WL_CONNECTED) {
      notify = true;
    }
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("BLE disconnected");
  }
};


const char* ntpServer = "pool.ntp.org";
const long gmtOffset_sec = 3600;
const int daylightOffset_sec = 3600;

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

//------------------------------------------------------------------
uint8_t vor[] = { 3, 74 };
uint8_t nach[] = { 4, 69 };

uint8_t ein[] = { 3, 48 };
uint8_t eins[] = { 4, 48 };
uint8_t zwei[] = { 4, 46 };
uint8_t drei[] = { 4, 41 };
uint8_t vier[] = { 4, 31 };
uint8_t fuenf[] = { 4, 35 };
uint8_t sechs[] = { 5, 2 };
uint8_t sieben[] = { 6, 51 };
uint8_t acht[] = { 4, 19 };
uint8_t neun[] = { 4, 27 };
uint8_t zehn[] = { 4, 15 };
uint8_t elf[] = { 3, 24 };
uint8_t zwoelf[] = { 5, 58 };

uint8_t es[] = { 2, 111 };
uint8_t ist[] = { 3, 107 };

uint8_t fuenfMin[] = { 4, 102 };
uint8_t zehnMin[] = { 4, 90 };
uint8_t viertel[] = { 7, 79 };
uint8_t zwanzig[] = { 7, 94 };
uint8_t halb[] = { 4, 64 };

uint8_t uhr[] = { 3, 1 };
uint8_t uhrleds[] = { 0, 113, 101, 12 };
//----------------------------------------------------------------


bool clockON = true;
bool debouncer = false;
bool debouncerTouch = false;
bool updateCorners = true;
bool updateWords = true;
bool updateTime = true;
bool partyMode = false;



color uhrfarbe = { 125, 255, 255 };
currentTime t = { 0, 0 };
struct tm timeinfo;



void setUhrfarbe(byte hue, byte saturation, byte brightness) {
  uhrfarbe.h = hue;
  uhrfarbe.s = saturation;
  uhrfarbe.b = brightness;
}


//prototype
void setWord(uint8_t wordLeds[], boolean indice = true);
void setWord(uint8_t wordLeds[], boolean indice) {
  if (indice) {
    for (int i = 0; i < wordLeds[0]; i++) {
      leds[wordLeds[1] + i] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
      //Serial.println(wordLeds[1] + i);
      //Serial.println("indice true");
    }
  } else {
    for (int i = 0; i < sizeof(wordLeds) / sizeof(uint8_t); i++) {
      leds[wordLeds[i]] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
      //Serial.println(wordLeds[i]);
    }
  }
}

//------------------------BLUETOOTH_CALLBACK---------------------------------------------------------------------------
class incomingCallbackHandler : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* wordclockTxCharacteristic) {
    char* incomingMessage = (char*)wordclockTxCharacteristic->getValue().c_str();
    Serial.print("message received: ");
    Serial.println(incomingMessage);
    char test[64];
    //memset(test,'\0',sizeof(test));
    strcpy(test, incomingMessage);
    strcat(test, "\0");
    Serial.println(test);
    char* messagePart;
    char delimiter[] = ",";
    messagePart = strtok(test, ",");
    Serial.println(messagePart);
    if (strcmp(messagePart, "#wifi") == 0) {
      messagePart = strtok(NULL, delimiter);
      Serial.println(messagePart);
      memcpy(ssid, messagePart, strlen(messagePart));
      Serial.print("ssid: ");
      Serial.println(messagePart);
      messagePart = strtok(NULL, delimiter);
      memcpy(password, messagePart, strlen(messagePart));
      Serial.print("password: ");
      Serial.println(messagePart);
      wifiConfigured = true;
      preferences.remove("ssid");
      preferences.remove("password");
      preferences.putString("ssid", ssid);
      preferences.putString("password", password);
      preferences.end();
      ESP.restart();
    } else if (strcmp(messagePart, "#kill") == 0) {
      delay(2000);
      ESP.restart();
    } else if (strcmp(messagePart, "#alexaOn") == 0) {
      alexaActivated = true;
      if (alexaActivatedInitial) {
        espalexa.addDevice("wortuhr", colorLightChanged, EspalexaDeviceType::color);
        espalexa.begin();
        //alexa callback handler
      }
      alexaActivatedInitial = false;
    } else if (strcmp(messagePart, "#alexaOff") == 0) {
      alexaActivated = false;
      if (!alexaActivatedInitial) {
      }
    } else if (strcmp(messagePart, "#reset") == 0) {
      preferences.clear();
      preferences.end();
      ESP.restart();
    } else if (strcmp(messagePart, "#test1") == 0) {
      FastLED.clear();
      FastLED.show();
      for (int i = 0; i < 114; i++) {
        leds[i] = CRGB::Red;
        FastLED.show();
        delay(100);
        leds[i] = CRGB::Black;
        FastLED.show();
      }
    } else if (strcmp(messagePart, "#test2") == 0) {
      FastLED.clear();
      FastLED.show();
      setUhrfarbe(255, 255, 255);
      setWord(es);
      displayOneSec();
      setWord(ist);
      displayOneSec();
      setWord(fuenfMin);
      displayOneSec();
      setWord(zehnMin);
      displayOneSec();
      setWord(viertel);
      displayOneSec();
      setWord(zwanzig);
      displayOneSec();
      setWord(halb);
      displayOneSec();
      setWord(vor);
      displayOneSec();
      setWord(nach);
      displayOneSec();
      setWord(ein);
      displayOneSec();
      setWord(eins);
      displayOneSec();
      setWord(zwei);
      displayOneSec();
      setWord(drei);
      displayOneSec();
      setWord(vier);
      displayOneSec();
      setWord(fuenf);
      displayOneSec();
      setWord(sechs);
      displayOneSec();
      setWord(sieben);
      displayOneSec();
      setWord(acht);
      displayOneSec();
      setWord(neun);
      displayOneSec();
      setWord(zehn);
      displayOneSec();
      setWord(elf);
      displayOneSec();
      setWord(zwoelf);
      displayOneSec();
      setWord(uhr);
      displayOneSec();
      updateCorners = true;
      updateWords = true;
    } else if (strcmp(messagePart, "#param") == 0) {
      if (WiFi.status() == WL_CONNECTED) {
        char value[64] = "stat,co,";
        wordclockRxCharacteristic.setValue(value);
        wordclockRxCharacteristic.notify();
        delay(300);
        strcpy(value, "ssid,");
        strcat(value, ssid);
        wordclockRxCharacteristic.setValue(value);
        wordclockRxCharacteristic.notify();
      }
    }
  }
};


void displayOneSec() {
  FastLED.show();
  delay(1000);
  FastLED.clear();
  FastLED.show();
}
//------------------------REST---------------------------------------------------------------------------



void colorLightChanged(EspalexaDevice* dev);
void colorLightChanged(EspalexaDevice* d){
  if (d == nullptr) return;
  clockON = d->getState();
  Serial.printf("%d , %d ,%d\n",d->getPercent(),d->getHue(),d->getSat());
  uhrfarbe.b = d->getPercent()*2,55;
  uhrfarbe.h = d->getHue()/255;
  uhrfarbe.s = d->getSat();
  //Serial.println(d->getColorMode());
  updateWords = true;
  updateCorners = true;
}


void handleIRCommand(uint8_t cmd) {
  //Serial.println(cmd);
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
    case 4:  //red
      setUhrfarbe(0, 255, 255);
      break;
    case 5:  //green
      setUhrfarbe(96, 255, 255);
      break;
    case 6:  //blue
      setUhrfarbe(160, 255, 255);
      break;
    case 7:  //white
      setUhrfarbe(0, 0, 255);
      break;
    case 8:  //orange
      setUhrfarbe(32, 255, 255);
      break;
    case 9:  //light green
      setUhrfarbe(105, 255, 255);
      break;
    case 10:  //light blue
      setUhrfarbe(175, 255, 255);
      break;
    case 11:  //flash
      if (partyMode) {
        partyMode = false;
        updateWords = true;
        updateCorners = true;
      } else {
        partyMode = true;
      }
      break;
    case 12:  //light orange
      setUhrfarbe(32, 255, 255);
      break;
    case 13:  //aqua
      setUhrfarbe(128, 255, 255);
      break;
    case 14:  //purple
      setUhrfarbe(192, 255, 255);
      break;
    case 15:  //strobe

      break;
    case 16:  //very light orange
      setUhrfarbe(32, 255, 255);
      break;
    case 17:  //marine
      setUhrfarbe(140, 255, 255);
      break;
    case 18:  //light purple
      setUhrfarbe(192, 200, 255);
      break;
    case 19:  //fade
              //
      break;
    case 20:  //yellow
      setUhrfarbe(64, 255, 255);
      break;
    case 21:  //dark aqua
      setUhrfarbe(150, 255, 150);
      break;
    case 22:  //pink
      setUhrfarbe(224, 255, 255);
      break;
    case 23:  //smooth
              //
      break;
  }
  //Serial.println("handled IR Command");
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
  setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1);
  tzset();
  struct tm timeinfo;
}

//------------------------SETUP---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  preferences.begin("credentials", false);
  String readout = preferences.getString("ssid", "");
  strcpy(ssid, readout.c_str());
  if (ssid[0] != '\0') {
    wifiConfigured = true;
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
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService* comService = pServer->createService(SERVICE_UUID);

  comService->addCharacteristic(&wordclockTxCharacteristic);
  comService->addCharacteristic(&wordclockRxCharacteristic);
  wordclockRxCharacteristic.addDescriptor(new BLE2902());
  wordclockTxCharacteristic.setCallbacks(new incomingCallbackHandler());
  // Start the service
  comService->start();

  // Start advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
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
        if (millis() - wifiTimeOutTimer > 3000) {
          wordclockRxCharacteristic.setValue("wifiFailed");
          wordclockRxCharacteristic.notify();
          wifiConfigured = false;
          break;
        }
      }
      if (WiFi.status() == WL_CONNECTED) {
        Serial.println("WiFi connected.");
        wifiConfigured = false;
        char value[64] = "stat,co,";
        wordclockRxCharacteristic.setValue(value);
        wordclockRxCharacteristic.notify();
        delay(50);
        strcpy(value, "ssid,");
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
}
//--------------------LOOP-----------------------------------------
void loop() {
  if (alexaActivated) {
    espalexa.loop();
  }
  if (notify) {
    char value[64] = "stat,co,";
    wordclockRxCharacteristic.setValue(value);
    wordclockRxCharacteristic.notify();
    delay(50);
    strcpy(value, "ssid,");
    strcat(value, ssid);
    wordclockRxCharacteristic.setValue(value);
    wordclockRxCharacteristic.notify();
    notify = false;
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
    IrReceiver.resume();  // Enable receiving of the next value
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
    int minutedivision = t.minutes % 5;  //modulo 5 für äußere minutenanzeige
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
        setWord(uhr);
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
      for (int i = 0; i < minutedivision; i++) {
        leds[uhrleds[i]] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
      }
      FastLED.show();
      updateCorners = false;
    }


  } else {
    FastLED.clear();
    FastLED.show();
  }
}