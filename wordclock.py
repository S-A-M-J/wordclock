#wordclock node red interfaced script
# Author: S.A.M.
#

import time
import sys

from rpi_ws281x import Color, PixelStrip, ws

# LED strip configuration:
LED_COUNT = 1        # Number of LED pixels.
LED_PIN = 18          # GPIO pin connected to the pixels (must support PWM!).
LED_FREQ_HZ = 800000  # LED signal frequency in hertz (usually 800khz)
LED_DMA = 10          # DMA channel to use for generating signal (try 10)
LED_BRIGHTNESS = 255  # Set to 0 for darkest and 255 for brightest
LED_INVERT = False    # True to invert the signal (when using NPN transistor level shift)
LED_CHANNEL = 0
# LED_STRIP = ws.SK6812_STRIP_RGBW
LED_STRIP = ws.SK6812W_STRIP


# Define functions which animate LEDs in various ways.
def colorWipe(strip, color, wait_ms=50):
    """Wipe color across display a pixel at a time."""
    for i in range(strip.numPixels()):
        strip.setPixelColor(i, color)
        strip.show()
        time.sleep(wait_ms / 1000.0)

minPlus4 = 0
minPlus1 = 12
minPlus2 = 113
minPlus3 = 101
uhr = [1,2,3]
sechs = [6,7,8,9,10]
zehn = [17,18,19,20]
vier = [23,24,25,26]
acht = [13,14,15,16]
neun = [27,28,29,30]
elf = [31,32,33]
zwei = [34,35,36]
sieben = [38,39,40,41,42,43,44]
zwoelf = [46,47,48,49,50]
halb = [52,53,54,55]
nach = [57,58,59,60]
vor = [62,63,64]
viertel = [67,68,69,70,71,72,73]
drei = [74,75,76,77]
zehnM = [78,79,80,81]
zwanzig = [82,83,84,85,86,87,88]
fuenf =[1,2,3,4]

# Main program logic follows:
if __name__ == '__main__':
    red = sys.argv[4]
    blue = sys.argv[5]
    green = sys.argv[6]
    white = sys.argv[7]
    # Create PixelStrip object with appropriate configuration.
    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL, LED_STRIP)
    # Intialize the library (must be called once before other functions).
    strip.begin()

    print('Press Ctrl-C to quit.')
    for x in range(5):
        # Color wipe animations.
        colorWipe(strip, Color(int(red), int(blue), int(green), int(white)), 0)  # Composite White + White LED wipe
        time.sleep(2)
        colorWipe(strip, Color(0 ,0 ,0 ,0), 0) 
