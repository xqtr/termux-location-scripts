#!/bin/bash

# GPS data receiver script for PC

PORT=50000
echo "Listening on port: $PORT..."

# Listen for incoming data forward to GPSD
nc -l $PORT | gpsd -n -N -D 5 /dev/stdin
