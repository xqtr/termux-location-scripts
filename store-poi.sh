#!/bin/bash

coords="$(./json2csv.sh pos)"
if [[ $coords != "-1" ]]; then
  r="$(termux-dialog text -t 'Enter Description for position' -i $coords)"
  code=$(echo $r | jq '.code')
  ans=$(echo $r | jq '.text')
  if [[ $code -eq -1 ]]; then
    echo "$coords;$ans" >> "./mylocations.poi"
  fi
fi
