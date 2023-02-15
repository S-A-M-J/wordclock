

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

#include <WiFi.h>
#include "time.h"
#include <ESP32Time.h>
ESP32Time rtc(0);
#include <Arduino.h>
#include <IRremote.hpp>

#include <Espalexa.h>
#include <Preferences.h>

#include <ArduinoOTA.h>

//#define language "english"  //comment out if german
#ifdef language
#include "english.h"
#else
#include "german.h"
#define language "german"
#endif


#include <FastLED.h>

#define NUM_LEDS 114
#define DATA_PIN 4
#define CLOCK_PIN 10

struct color {
  byte h;
  byte s;
  byte b;
};

Preferences preferences;

#define IR_RECEIVE_PIN 33
#define TOUCH_PIN 5

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
bool OTAactivated = false;
bool updateCorners = true;
bool updateWords = true;
bool clockON = true;
bool wifiTimerActive = false;

long wifiTimeOutTimer = 0;

IPAddress ip;
char ipString[20] = {};

Espalexa espalexa;


//------------------------OTA---------------------------------------------------------------------------
void setupOTA() {
  if (WiFi.status() == WL_CONNECTED) {
    ArduinoOTA
      .onStart([]() {
        String type;
        if (ArduinoOTA.getCommand() == U_FLASH)
          type = "sketch";
        else  // U_SPIFFS
          type = "filesystem";

        // NOTE: if updating SPIFFS this would be the place to unmount SPIFFS using SPIFFS.end()
        Serial.println("Start updating " + type);
      })
      .onEnd([]() {
        Serial.println("\nEnd");
      })
      .onProgress([](unsigned int progress, unsigned int total) {
        Serial.printf("Progress: %u%%\r", (progress / (total / 100)));
      })
      .onError([](ota_error_t error) {
        Serial.printf("Error[%u]: ", error);
        if (error == OTA_AUTH_ERROR) Serial.println("Auth Failed");
        else if (error == OTA_BEGIN_ERROR) Serial.println("Begin Failed");
        else if (error == OTA_CONNECT_ERROR) Serial.println("Connect Failed");
        else if (error == OTA_RECEIVE_ERROR) Serial.println("Receive Failed");
        else if (error == OTA_END_ERROR) Serial.println("End Failed");

        while (1) {  //kill power if failed
          ESP.restart();
        }
      });

    ArduinoOTA.begin();
    Serial.println("Ready");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
    OTAactivated = true;
    Serial.println("ota activated");
  }
}

void checkOTA() {
  if (WiFi.status() == WL_CONNECTED && OTAactivated) {
    ArduinoOTA.handle();
  }
}

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
    pServer->getAdvertising()->start();
    Serial.println("Waiting a client connection to notify...");
    advertising = true;
  }
};


const char* ntpServer = "pool.ntp.org";
const long gmtOffset_sec = 3600;
const int daylightOffset_sec = 3600;

struct currentTime {
  uint8_t hours;
  uint8_t minutes;
  uint8_t seconds;
};

bool debouncer = false;
bool debouncerTouch = false;
bool updateTime = true;
bool partyMode = false;

currentTime t = { 0, 0 };
struct tm timeinfo;

// Define the array of leds
CRGB leds[NUM_LEDS];

color uhrfarbe = { 125, 255, 255 };

//prototype
void setWord(uint8_t wordLeds[], boolean indice = true);

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
      preferences.begin("credentials", false);
      preferences.remove("ssid");
      preferences.remove("password");
      preferences.putString("ssid", ssid);
      preferences.putString("password", password);
      preferences.end();
      if (WiFi.status() == WL_CONNECTED) {
        WiFi.disconnect();
      }
      WiFi.begin(ssid, password);
    } else if (strcmp(messagePart, "#kill") == 0) {
      delay(2000);
      ESP.restart();
    } else if (strcmp(messagePart, "#alexaOn") == 0) {
      alexaActivated = true;
      if (alexaActivatedInitial) {
        espalexa.addDevice("wortuhr", colorLightChanged, EspalexaDeviceType::color);
        espalexa.begin();
      }
      preferences.begin("alexaSettings", false);
      preferences.remove("status");
      preferences.putBool("status", true);
      preferences.end();
      alexaActivatedInitial = false;
    } else if (strcmp(messagePart, "#alexaOff") == 0) {
      alexaActivated = false;
      preferences.begin("alexaSettings", false);
      preferences.clear();
      preferences.putBool("status", false);
      preferences.end();
    } else if (strcmp(messagePart, "#reset") == 0) {
      preferences.begin("credentials", false);
      preferences.clear();
      preferences.end();
      preferences.begin("alexaSettings", false);
      preferences.clear();
      preferences.end();
      ESP.restart();
    } else if (strcmp(messagePart, "#test1") == 0) {
      //clockON = false;
      FastLED.clear();
      FastLED.show();
      for (int k = 0; k < 114; k++) {
        leds[k] = CRGB::Red;
        FastLED.show();
        delay(100);
        leds[k] = CRGB::Black;
        FastLED.show();
        delay(10);
      }
      //clockON = true;
    } else if (strcmp(messagePart, "#OTAOn") == 0) {
      //add indicator
      setupOTA();
    } else if (strcmp(messagePart, "#test2") == 0) {
      //clockON = false;
      FastLED.clear();
      FastLED.show();
      //setClockColor(125, 255, 255);
      for (int i = 0; i < sizeof(allWords) / sizeof(allWords[0]); i++) {
        setWord(allWords[i]);
        displayOneSec();
      }
    } else if (strcmp(messagePart, "#param") == 0) {
      Serial.println("Parameters sent");
      if (WiFi.status() == WL_CONNECTED) {
        sendBLEData();
      } else if (wifiConfigured) {
        wordclockRxCharacteristic.setValue("wifiFailed");
        wordclockRxCharacteristic.notify();
      } else {
        wordclockRxCharacteristic.setValue("wifiNotConfigured");
        wordclockRxCharacteristic.notify();
      }
    } else if (strcmp(messagePart, "#debug") == 0) {
      char value[64] = "debug,";
      strcat(value, ssid);
      strcat(value, ",");
      strcat(value, password);
      wordclockRxCharacteristic.setValue(value);
      wordclockRxCharacteristic.notify();
    } else if (strcmp(messagePart, "#setColor") == 0) {
      char value[16] = {};
      messagePart = strtok(NULL, delimiter);
      Serial.println(messagePart);
      memcpy(value, messagePart, strlen(messagePart));
      uhrfarbe.h = atoi(value);
      messagePart = strtok(NULL, delimiter);
      memcpy(value, messagePart, strlen(messagePart));
      uhrfarbe.s = atoi(value);
      messagePart = strtok(NULL, delimiter);
      memcpy(value, messagePart, strlen(messagePart));
      uhrfarbe.b = atoi(value);
    }
    updateCorners = true;
    updateWords = true;
  }
};

//-----------------------LED HANDLING------------------------------------------------------------------


void setUhrfarbe(byte hue, byte saturation, byte brightness) {
  uhrfarbe.h = hue;
  uhrfarbe.s = saturation;
  uhrfarbe.b = brightness;
}

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

void displayOneSec() {
  FastLED.show();
  delay(900);
  FastLED.clear();
  FastLED.show();
  delay(100);
}

//-----------------------IR----------------------------------------------------------------------------

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

//------------------------REST---------------------------------------------------------------------------



void colorLightChanged(EspalexaDevice* dev);
void colorLightChanged(EspalexaDevice* d) {
  if (d == nullptr) return;
  clockON = d->getState();
  Serial.printf("%d , %d ,%d\n", d->getPercent(), d->getHue(), d->getSat());
  uhrfarbe.b = d->getPercent() * 2, 55;
  uhrfarbe.h = d->getHue() / 255;
  uhrfarbe.s = d->getSat();
  //Serial.println(d->getColorMode());
  updateWords = true;
  updateCorners = true;
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
  if (WiFi.status() == WL_CONNECTED) {
    configTime(0, 0, ntpServer);
    setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1);
    tzset();
    struct tm timeinfo;
  }
}

void sendBLEData() {
  char value[64] = "stat,co,";
  strcat(value, ssid);
  strcat(value, ",");
  ip = WiFi.localIP();
  strcat(value, ip.toString().c_str());
  strcat(value, ",");
  if (alexaActivated) {
    strcat(value, "on");
  } else {
    strcat(value, "off");
  }
  wordclockRxCharacteristic.setValue(value);
  wordclockRxCharacteristic.notify();
}

//------------------------SETUP---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  preferences.begin("credentials", false);
  String readout = preferences.getString("ssid", " ");
  strcpy(ssid, readout.c_str());
  if (ssid[0] != ' ') {
    wifiConfigured = true;
    readout = preferences.getString("password", "");
    preferences.end();
    strcpy(password, readout.c_str());
    noCredentialsFound = false;
  } else {
    wifiConfigured = false;
    noCredentialsFound = true;
  }
  if (wifiConfigured) {
    Serial.println(ssid);
    Serial.println(password);
    Serial.println(alexaActivated);
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
  //---------------------------SETUP_LOOP----------------------------------------------------------------------
  int i = 0;
  long blinkTimer = 0;
  while (1) {
    if (millis() - blinkTimer > 500) {
      leds[cornerLeds[i]] = CHSV(0, 0, 255);
      if (i > 0) {
        leds[cornerLeds[i - 1]] = CHSV(0, 0, 0);
      } else {
        leds[cornerLeds[3]] = CHSV(0, 0, 0);
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
        setWord(cornerLeds, false);
        FastLED.show();
        delay(1000);
        setUhrfarbe(0, 0, 0);
        setWord(cornerLeds, false);
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
          Serial.println("wifiFailed");
          wifiConfigured = false;
          break;
        }
      }
      if (WiFi.status() == WL_CONNECTED) {
        wifiTimeOutTimer = 0;
        Serial.println("WiFi connected.");
        wifiConfigured = false;
        sendBLEData();
        setUhrfarbe(96, 255, 255);
        setWord(cornerLeds, false);
        FastLED.show();
        delay(1000);
        setUhrfarbe(0, 0, 0);
        setWord(cornerLeds, false);
        FastLED.show();
        preferences.begin("alexaSettings", false);
        alexaActivated = preferences.getBool("status", false);
        preferences.end();
        if (alexaActivated) {
          if (alexaActivatedInitial) {
            espalexa.addDevice("wortuhr", colorLightChanged, EspalexaDeviceType::color);
            espalexa.begin();
            alexaActivatedInitial = false;
          }
        }
        break;
      }
    }
  }
  FastLED.clear();
  updateRTC();
  printLocalTime();
  IrReceiver.begin(IR_RECEIVE_PIN, ENABLE_LED_FEEDBACK);
  Serial.println("loop begins");
  preferences.begin("color", true);
  uhrfarbe.h = preferences.getInt("hue", 0);
  uhrfarbe.s = preferences.putInt("sat", 255);
  uhrfarbe.b = preferences.putInt("bri", 255);
  preferences.end();
  if(uhrfarbe.b == 0){
    uhrfarbe.b = 255;
  }
}
//--------------------LOOP-----------------------------------------
void loop() {
  if (WiFi.status() != WL_CONNECTED && !wifiTimerActive) {
    wifiTimeOutTimer = millis();
    wifiTimerActive = true;
    WiFi.reconnect();
  }
  if (wifiTimerActive) {
    if (WiFi.status() == WL_CONNECTED) {
      wifiTimerActive = false;
      wifiTimeOutTimer = 0;
    } else if (millis() - wifiTimeOutTimer > 10000 && wifiTimeOutTimer != 0) {
      preferences.begin("color", false);
      preferences.putInt("hue", uhrfarbe.h);
      preferences.putInt("sat", uhrfarbe.s);
      preferences.putInt("bri", uhrfarbe.b);
      preferences.end();
      Serial.println("Restarting now");
      ESP.restart();
    }
  }
  if (OTAactivated) {
    checkOTA();
  } else {
    if (alexaActivated) {
      espalexa.loop();
    }
    t.hours = rtc.getHour();
    t.minutes = rtc.getMinute();
    t.seconds = rtc.getSecond();
    if (IrReceiver.decode()) {
      IrReceiver.resume();  // Enable receiving of the next value
      handleIRCommand(IrReceiver.decodedIRData.command);
      updateWords = true;
      updateCorners = true;
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
        if (strcmp(language, "german") == 0) {
          //-------german----------------------------------------------------------------------------------------------
          setWord(es);
          setWord(ist);
          if (t.minutes > 24) {
            t.hours = t.hours + 1;
          }
          t.hours = t.hours % 12;
          if(t.minutes < 5){
            setWord(uhr);
          }
          //es ist x "UHR" minuten
          if (t.hours == 2) {
            if (t.minutes > 5) {
              setWord(eins);
            } else {
              setWord(hourArray[t.hours]);
            }
          } else {
            setWord(hourArray[t.hours]);
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
          //-------german end----------------------------------------------------------------------------------------------
        } else if (strcmp(language, "english") == 0) {
          //-------english-------------------------------------------------------------------------------------------------
          /*
          setWord(it);
          setWord(is);
          if (t.minutes > 24) {
            t.hours = t.hours + 1;
          }
          t.hours = t.hours % 12;
          setWord(hourArray[t.hours]);

          //es ist x "UHR" minuten
          if (t.minutes <= 4) {
            setWord(oclock);
          }
          int minuteStep = (t.minutes - minutedivision);
          switch (minuteStep) {
            case 5:
              setWord(past);
              setWord(fiveMinutes);
              break;
            case 10:
              setWord(past);
              setWord(tenMinutes);
              break;
            case 15:
              setWord(past);
              setWord(quarter);
              break;
            case 20:
              setWord(past);
              setWord(twenty);
              break;
            case 25:
              setWord(fiveMinutes);
              setWord(twenty);
              break;
            case 30:
              setWord(half);
              break;
            case 35:
              setWord(past);
              setWord(fiveMinutes);
              setWord(half);
              break;
            case 40:
              setWord(to);
              setWord(twenty);
              break;
            case 45:
              setWord(to);
              setWord(quarter);
              break;
            case 50:
              setWord(to);
              setWord(tenMinutes);
              break;
            case 55:
              setWord(to);
              setWord(fiveMinutes);
              break;
          }
          */
          //------------------english end--------------------------------------------------------------
        }
        updateWords = false;
      }
      if (updateCorners) {
        for (int i = 0; i < minutedivision; i++) {
          leds[cornerLeds[i]] = CHSV(uhrfarbe.h, uhrfarbe.s, uhrfarbe.b);
        }
        FastLED.show();
        updateCorners = false;
      }
    } else {
      FastLED.clear();
      FastLED.show();
    }
  }
}