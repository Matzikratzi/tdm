#! /bin/bash

# Setting linux GPIO for debug use
echo out > /sys/class/gpio/gpio66/direction
echo 1 > /sys/class/gpio/gpio66/value

# # preparing inputs for up to 8 loops of ICS-52000
# for i in {39..46}
# do
#     config-pin PU_$i pruin
# done

# # preparing outputs for up to 4 SCK and 2 WS
# for i in 20 21 27 28 29 30
# do
#     config-pin PU_$i pruout
# done


# Setting PRU GPIO as out for use as SCK and WS
# config-pin P8_27 pruout
# config-pin P8_28 pruout
# config-pin P8_29 pruout
# config-pin P8_30 pruout

# echo 0 > /sys/devices/virtual/misc/beaglelogic/sampleunit
# cat /sys/devices/virtual/misc/beaglelogic/sampleunit

# echo 100000000 > /sys/devices/virtual/misc/beaglelogic/samplerate
# cat /sys/devices/virtual/misc/beaglelogic/samplerate

echo 33554432 > /sys/devices/virtual/misc/beaglelogic/memalloc

rm -rf mydump
dd if=/dev/beaglelogic of=mydump bs=1M count=1

hexdump -C mydump|head
