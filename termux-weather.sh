#!/bin/bash

coords="$(./json2csv.sh maps)"
if [ ! $# -eq 0 ]; then
  echo "Could not get coordinates. Exiting!"
  exit 1
fi
loc=$(termux-location) && curl "https://wttr.in/$coords)"
#wait until keypress
read -t 3 -n 1
