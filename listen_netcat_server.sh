#!/bin/bash

# GPS data receiver script for PC

PORT=50000
echo "Listening on port: $PORT..."

# Listen for incoming data and print it
nc -l $PORT
