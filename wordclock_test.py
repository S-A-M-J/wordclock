#wordclock node red interfaced script
# Author: S.A.M.
#


import sys

from rpi_ws281x import Color, PixelStrip, ws

# LED strip configuration:
LED_COUNT = 114        # Number of LED pixels.
LED_PIN = 18          # GPIO pin connected to the pixels (must support PWM!).
LED_FREQ_HZ = 800000  # LED signal frequency in hertz (usually 800khz)
LED_DMA = 10          # DMA channel to use for generating signal (try 10)
LED_BRIGHTNESS = 255  # Set to 0 for darkest and 255 for brightest
LED_INVERT = False    # True to invert the signal (when using NPN transistor level shift)
LED_CHANNEL = 0
# LED_STRIP = ws.SK6812_STRIP_RGBW
LED_STRIP = ws.SK6812W_STRIP

gammaList = [0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1,  1,  1,
    1,  1,  1,  1,  1,  1,  1,  1,  1,  2,  2,  2,  2,  2,  2,  2,
    2,  3,  3,  3,  3,  3,  3,  3,  4,  4,  4,  4,  4,  5,  5,  5,
    5,  6,  6,  6,  6,  7,  7,  7,  7,  8,  8,  8,  9,  9,  9, 10,
   10, 10, 11, 11, 11, 12, 12, 13, 13, 13, 14, 14, 15, 15, 16, 16,
   17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 24, 24, 25,
   25, 26, 27, 27, 28, 29, 29, 30, 31, 32, 32, 33, 34, 35, 35, 36,
   37, 38, 39, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 50,
   51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 66, 67, 68,
   69, 70, 72, 73, 74, 75, 77, 78, 79, 81, 82, 83, 85, 86, 87, 89,
   90, 92, 93, 95, 96, 98, 99,101,102,104,105,107,109,110,112,114,
  115,117,119,120,122,124,126,127,129,131,133,135,137,138,140,142,
  144,146,148,150,152,154,156,158,160,162,164,167,169,171,173,175,
  177,180,182,184,186,189,191,193,196,198,200,203,205,208,210,213,
  215,218,220,223,225,228,231,233,236,239,241,244,247,249,252,255]

corners = [0,113,101,12]

uhr = [9,10,11]

es = [111,112]
ist = [109,108,107]

ein = [48,49,50]
eins = [48,49,50,51]
zwei = [46,47,48,49]
drei = [41,42,43,44]
vier = [31,32,33,34]
fuenf = [35,36,37,38]
sechs = [2,3,4,5,6]
sieben = [51,52,53,54,55,56,57]
acht = [19,20,21,22]
neun = [27,28,29,30]
zehn = [15,16,17,18]
elf = [24,25,26]
zwoelf = [58,59,60,61,62]

nach = [69,70,71,72]
vor = [74,75,76]

halb = [64,65,66,67]
viertel = [79,80,81,82,83,84,85]
zehnMin = [90,91,92,93]
zwanzigMin = [94,95,96,97,98,99,100]
fuenfMin =[102,103,104,105]

# Define functions which animate LEDs in various ways.
def colorWipe(strip, color):
    """Wipe color across display a pixel at a time."""
    for i in range(strip.numPixels()):
        strip.setPixelColor(i, color)
    strip.show()
        
def setWord(wordLeds, clockColorSet):
    for i in wordLeds:
        strip.setPixelColor(i, Color(clockColorSet[0], clockColorSet[1], clockColorSet[2], clockColorSet[3]))
        #strip.show()
        #print(i)

# Main program logic follows:
if __name__ == '__main__':
    hours = int(sys.argv[1])
    minutes = int(sys.argv[2])
    if minutes >= 25:
        hours = hours+1
    hours = hours % 12
    brightnessFloat = float(sys.argv[3])
    brightness = round(brightnessFloat)
    clockcolor = [int(sys.argv[4]),int(sys.argv[5]),int(sys.argv[6]),int(sys.argv[7])]
    highestValue = 0
    for element in clockcolor:
        #element = element / 100 * brightness
        #print(element)
        if element > highestValue:
            highestValue = element
    #print(brightness)
    # Create PixelStrip object with appropriate configuration.
    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL, LED_STRIP)
    # Intialize the library (must be called once before other functions).
    strip.begin()
    strip.setGamma(gammaList)
    
    setWord(es,clockcolor)
    setWord(ist,clockcolor)
    if highestValue == 0:
        colorWipe(strip,Color(0,0,0,0))
        print('clock is turned off.')
        strip._cleanup()
        exit()
        
    activeCorners = minutes % 5
    print(activeCorners)
    for x in range(activeCorners):
        strip.setPixelColor(corners[x], Color(clockcolor[0], clockcolor[1], clockcolor[2], clockcolor[3]))
     
    minutes = minutes - activeCorners
    
        
    if hours == 1:
        if minutes<5:
            setWord(ein,clockcolor)
        else:
            setWord(eins,clockcolor)
    elif hours == 2:
        setWord(zwei,clockcolor)
    elif hours == 3:
        setWord(drei,clockcolor)
    elif hours == 4:
        setWord(vier,clockcolor)
    elif hours == 5:
        setWord(fuenf,clockcolor)
    elif hours == 6:
        setWord(sechs,clockcolor)
    elif hours == 7:
        setWord(sieben,clockcolor)
    elif hours == 8:
        setWord(acht,clockcolor)
    elif hours == 9:
        setWord(neun,clockcolor)
    elif hours == 10:
        setWord(zehn,clockcolor)
    elif hours == 11:
        setWord(elf,clockcolor)
    elif hours == 0:
        setWord(zwoelf,clockcolor)
    
    if minutes < 5:
        setWord(uhr,clockcolor)
    else:
        if minutes == 5 or minutes == 25 or minutes == 35 or minutes == 55:
            setWord(fuenfMin,clockcolor)
        elif minutes == 10 or minutes == 50:
            setWord(zehnMin,clockcolor)
        elif minutes == 15 or minutes == 45:
            setWord(viertel,clockcolor)
        elif minutes == 20 or minutes == 40:
            setWord(zwanzigMin,clockcolor)
    
        if minutes >=25 and minutes <= 35:
            setWord(halb,clockcolor)
        
        if minutes < 25 or minutes == 35:
            setWord(nach,clockcolor)
        elif minutes == 25 or minutes>35:
            setWord(vor,clockcolor)
    strip.setBrightness(int(brightness))
    strip.show()
    print('program finished')
    strip._cleanup()
    exit()
    
