# termux-location-scripts
A collection of scripts for using in Termux with the termux-location utility. The most useful one, is the send_gps.nmea.sh, which shares the GPS location of the smartphone to a GPSD server, enabling you to use your Android smartphone as a GPS device to a Raspberry Pi or other computer.


## Index of the files...
```
bt-connection.txt         How to share GPS data via Bleutooth
json2csv.sh               Convert JSON result from termux-location to simple csv
listen_gpsd_server.sh     Create GPSD server
listen_netcat_server.sh   Receive GPS/NMEA data via netcat
send_gps_nmea.sh          Sends NMEA data from smartphone/termux
termux-location           Fake 'termux-location' script, for testing
termux-weather.sh         Get weather from wttr site, using GPS coordinates of termux-location
store-poi.sh              Get location and store it as a POI in a text file
```

## Share smartphones GPS Location...

The `send_gps_nmea.sh` script, takes the GPS location of the phone, using the `termux-location` utility and converts it to NMEA data, which then shares with another computer via `netcat`. The same can be possible via Bluetooth.

### How to use it:

- Install Termux:API package
- Enable GPS on your smartphone.
- Run the `send_gps_nmea.sh` script on your phone, via Termux
- On your PC/Raspberry, run the `listen_gpsd_server.sh` script
- If everything works, any app that uses GPSD, should be able to get the GPS coordinates.

### Notes:
- Tested with: `cgps`, `xgps`, `gpspipe`, `gpsmon`
- Prefer to use GPSD ver. 3.26
