import usb_hid
import time
import board
import neopixel
import pwmio
from adafruit_motor import servo
import struct

print("Starting")

led = neopixel.NeoPixel(board.LED_DATA, board.NUM_LEDS)
led.brightness = 0.3

device = usb_hid.devices[0]
panRange = 360
tiltRange = 300

panServo = servo.Servo(
    pwmio.PWMOut(board.SERVO_1, duty_cycle=2 ** 15, frequency=50), 
    actuation_range=panRange,
    min_pulse=500,
    max_pulse=2500,
)
tiltServo = servo.Servo(
    pwmio.PWMOut(board.SERVO_2, duty_cycle=2 ** 15, frequency=50),
    actuation_range=tiltRange,
    min_pulse=500,
    max_pulse=2500,
)

panPosition = 128
tiltPosition = 50

panServo.angle = panRange * panPosition / 256.0
tiltServo.angle = tiltRange * tiltPosition / 256.0

for i in range(board.NUM_LEDS):
  led[i] = (0, 0, 0)

def p(k):
    v = device.get_last_received_report(k)
    if v is not None:
        print(k, v)

while True:
    p(1)
    p(2)
    p(3)
    p(4)
    p(5)

    command = device.get_last_received_report(3)
    if command is not None:
        print(command)
        """
        print(f"Current: {panServo.angle} {tiltServo.angle}")
        [newPanPosition, newTiltPosition] = command
        print(command)
        if newPanPosition != panPosition:
            panServo.angle = panRange * newPanPosition / 256.0 
            print(f"Setting pan {newPanPosition} {panServo.angle}")
            panPosition = newPanPosition
            led[0] = (255, 255, 255)
        if newTiltPosition != tiltPosition:
            tiltServo.angle = tiltRange * newTiltPosition / 256.0 
            print(f"Setting tilt {newTiltPosition} {tiltServo.angle}")
            tiltPosition = newTiltPosition
            led[1] = (255, 255, 255)
        """
    else:
        led[0] = (0, 0, 0)
        led[1] = (0, 0, 0)
    device.send_report(bytearray([4,5,0,0]), 1)
    #device.send_report(struct.pack('!h', tiltPosition), 2)
    time.sleep(0.01)