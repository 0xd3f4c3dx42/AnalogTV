import RPi.GPIO as GPIO
import os
import time

GPIO.setmode(GPIO.BCM)
GPIO.setup(21, GPIO.IN, pull_up_down=GPIO.PUD_UP)

def shutdown(channel):
    os.system("sudo shutdown -h now")

GPIO.add_event_detect(21, GPIO.BOTH, callback=shutdown, bouncetime=200)

try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    GPIO.cleanup()
