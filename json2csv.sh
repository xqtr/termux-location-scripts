#!/usr/bin/env bash

if [ "$1" = "--help" ]; then
  echo ""
  echo "Output JSON formatted string of termux-location to csv"
  echo "and also copy to clipboard."
  echo ""
  echo "Parameters:"
  echo "  pos    : Shows Lat;Lon;Alt format"
  echo "  lat    : Shows only the lattitude"
  echo "  lon    : Shows only the longitude"
  echo "  alt    : Shows the altitude"
  echo "  speed  : Shows speed"
  echo "  bearing: Shows bearing"
  echo "  maps   : Shows Lat,Lon for Google Maps paste"
  echo ""
  echo "  If no paramaters the output format is:"
  echo "  Lat;Lon;Alt;Speed;Bearing;Provider"
  echo ""
  exit 1
fi

json=$(termux-location 2>/dev/null) || exit 1
[ -z "$json" ] && exit 1
lat=$(echo "$json" | jq -r '.latitude // 0')
lon=$(echo "$json" | jq -r '.longitude // 0')
alt=$(echo "$json" | jq -r '.altitude // 0')
acc=$(echo "$json" | jq -r '.accuracy // 1')
spd=$(echo "$json" | jq -r '.speed // 0')
provider=$(echo "$json" | jq -r '.provider // 0')
bearing=$(echo "$json" | jq -r '.bearing // 0')

if [ $# -eq 0 ]; then
    echo "$lat;$lon;$alt;$spd;$bearing;$provider"
    echo "$lat;$lon;$alt;$spd;$bearing;$provider" | xclip -selection clipboard
    exit 1
fi

CMD="$1"

case "$CMD" in
  "lat") output="$lat";;
  "lon") output="$lon";;
  "alt") output="$alt";;
  "speed") output="$spd";;
  "bearing") output="$bearing";;
  "pos") output="$lat;$lon;$alt";;
  "maps") output="$lat,$lon";;
  *) output="$lat;$lon;$alt;$spd;$bearing;$provider";;
esac

echo "$output"

if [ "$2" == "copy" ]; then
  echo "$output" | xclip -selection clipboard
fi

exit 0
