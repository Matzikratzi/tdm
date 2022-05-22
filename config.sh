#! /bin/bash

# Setting linux GPIO for debug use
echo out > /sys/class/gpio/gpio66/direction
echo 1 > /sys/class/gpio/gpio66/value

# preparing inputs for up to 8 loops of ICS-52000
for i in {39..46}
do
    config-pin P8_$i pruin
    
done

# preparing outputs for up to 2 SCK and 2 WS
for i in 27 28 29 30
do
    config-pin P8_$i pruout
done

# echo 0 > /sys/devices/virtual/misc/beaglelogic/sampleunit
# cat /sys/devices/virtual/misc/beaglelogic/sampleunit

# echo 100000000 > /sys/devices/virtual/misc/beaglelogic/samplerate
# cat /sys/devices/virtual/misc/beaglelogic/samplerate

echo 33554432 > /sys/devices/virtual/misc/beaglelogic/memalloc

# 16 kHz (when we have the downscaling functionality in BITFILL)
echo 50000000 > /sys/devices/virtual/misc/beaglelogic/samplerate

