#!/usr/bin/env bash
# Persistent Termux GPS → NMEA streamer to PC (with GGA/RMC + GSA/GSV/VTG/ZDA)
#
# Sends realistic-looking satellite/fix sentences so gpsd treats the feed as a real fix.

PC_IP="$1"
PORT="$2"

if [ -z "$PC_IP" ] || [ -z "$PORT" ]; then
  echo "Usage: $0 <PC-IP> <PORT>"
  exit 1
fi

INTERVAL=1  # seconds between updates
# number of fake satellites to report (between 6 and 12)
MIN_SATS=6
MAX_SATS=10

# ---------- helpers ----------
to_nmea_coord() {
  # convert decimal degrees to NMEA ddmm.mmmm (lat) / dddmm.mmmm (lon)
  local dec=$(printf "%.8f" "$1")
  local is_lat=$2
  # preserve sign for direction detection but use absolute value for formatting
  local sign=1
  if [[ "$dec" =~ ^- ]]; then
    sign=-1
    dec=${dec#-}
  fi
  local deg=$(echo "$dec" | awk -F. '{print int($1)}')
  local min=$(echo "scale=6; (($dec - $deg) * 60)" | bc -l)
  if [ "$is_lat" -eq 1 ]; then
    printf "%02d%07.4f" "$deg" "$min"
  else
    printf "%03d%07.4f" "$deg" "$min"
  fi
}

nmea_checksum() {
  local sentence="$1" checksum=0
  for ((i=0;i<${#sentence};i++)); do
    checksum=$((checksum ^ $(printf "%d" "'${sentence:$i:1}'")))
  done
  printf "%02X" "$checksum"
}

# produce pseudo-random but deterministic-ish SNR and satellite PRNs
# returns a space-separated list of PRN:elev:azim:snr
gen_sat_list() {
  local n=$1
  local i prn elev az snr seed
  seed=$(( $(date +%s) % 1000 ))
  for ((i=0;i<n;i++)); do
    prn=$(( 1 + (seed + i*7) % 32 ))           # PRN 1..32
    elev=$(( 10 + (seed + i*11) % 70 ))       # elevation 10..79
    az=$(( (seed*3 + i*13) % 360 ))           # azimuth 0..359
    snr=$(( 20 + (seed + i*5) % 35 ))         # snr 20..54 dB
    printf "%s:%d:%d:%d " "$prn" "$elev" "$az" "$snr"
  done
}

# produce GSV sentences (max 4 satellites per GSV message)
generate_gsv_sentences() {
  local satlist=($1) # passed as array-like string elements "PRN:el:az:snr"
  local total=${#satlist[@]}
  local msg_count=$(( (total + 3) / 4 ))
  local idx=0
  local seq s prn el az sn

  for ((seq=1; seq<=msg_count; seq++)); do
    local fields=()
    for ((i=0;i<4 && idx<total;i++, idx++)); do
      s=${satlist[idx]}
      prn=${s%%:*}
      rest=${s#*:}
      el=${rest%%:*}
      rest2=${rest#*:}
      az=${rest2%%:*}
      sn=${rest2#*:}
      fields+=("$prn,$el,$az,$sn")
    done
    # pad to make 4 groups if needed
    while [ ${#fields[@]} -lt 4 ]; do
      fields+=(",,,")
    done
    # total messages, message number, total sats, then groups
    local gsv="GPGSV,$msg_count,$seq,$total,${fields[0]},${fields[1]},${fields[2]},${fields[3]}"
    printf "\$%s*%s\n" "$gsv" "$(nmea_checksum "$gsv")"
  done
}

# produce GSA sentence
generate_gsa_sentence() {
  # mode: M = manual, A = automatic. Use 'A'. fix type: 3 = 3D
  local mode="A"
  local fix=3
  shift
  local sat_prns=("$@")
  # make a list of exactly 12 PRN slots (empty where none)
  local prnlist=()
  local i
  for ((i=0;i<12;i++)); do
    prnlist[i]=""
  done
  for ((i=0;i<${#sat_prns[@]} && i<12;i++)); do
    prnlist[i]="${sat_prns[i]}"
  done
  # PDOP, HDOP, VDOP: fabricate reasonable values
  local pdop=$(printf "%.1f" "$(awk -v a=1 'BEGIN{srand(); print 1.5 + rand()*2.0}')")
  local hdop=$(printf "%.1f" "$(awk -v a=1 'BEGIN{srand(); print 0.8 + rand()*1.2}')")
  local vdop=$(printf "%.1f" "$(awk -v a=1 'BEGIN{srand(); print 0.8 + rand()*1.5}')")
  local gsa="GPGSA,$mode,$fix"
  for i in "${prnlist[@]}"; do
    gsa+=",${i}"
  done
  gsa+=",$pdop,$hdop,$vdop"
  printf "\$%s*%s\n" "$gsa" "$(nmea_checksum "$gsa")"
}

# generate VTG sentence (track and speed)
generate_vtg_sentence() {
  local track="$1"
  local speed_knots="$2"
  # track true, track mag empty, speed knots, speed km/h
  local speed_kmph=$(printf "%.1f" "$(awk -v s="$speed_knots" 'BEGIN{printf "%.3f", s*1.852}')")
  local vtg="GPVTG,$track.,T,,M,$speed_knots,N,$speed_kmph,K"
  printf "\$%s*%s\n" "$vtg" "$(nmea_checksum "$vtg")"
}

# generate ZDA sentence (time + date)
generate_zda_sentence() {
  # format: hhmmss.ss, dd, mm, yyyy, local-zone-hours, local-zone-minutes
  local t=$(date -u +"%H%M%S")
  local dd=$(date -u +"%d")
  local mm=$(date -u +"%m")
  local yyyy=$(date -u +"%Y")
  local zda="GPZDA,$t.00,$dd,$mm,$yyyy,00,00"
  printf "\$%s*%s\n" "$zda" "$(nmea_checksum "$zda")"
}

# ---------- main NMEA generator ----------
generate_nmea_full() {
  # read termux location
  local json lat lon alt acc spd bearing
  json=$(termux-location 2>/dev/null) || return
  [ -z "$json" ] && return

  lat=$(echo "$json" | jq -r '.latitude // 0')
  lon=$(echo "$json" | jq -r '.longitude // 0')
  alt=$(echo "$json" | jq -r '.altitude // 0')
  acc=$(echo "$json" | jq -r '.accuracy // 1')
  spd=$(echo "$json" | jq -r '.speed // 0')
  bearing=$(echo "$json" | jq -r '.bearing // 0')

  # prepare formatted fields
  local lat_nmea lon_nmea lat_dir lon_dir
  lat_nmea=$(to_nmea_coord "$lat" 1)
  lon_nmea=$(to_nmea_coord "$lon" 0)
  if awk "BEGIN{print ($lat < 0)}"; then lat_dir="S"; else lat_dir="N"; fi
  if awk "BEGIN{print ($lon < 0)}"; then lon_dir="W"; else lon_dir="E"; fi

  local time_utc date_utc hhmmss ddmmyy
  time_utc=$(date -u +"%H%M%S")
  hhmmss="$time_utc.00"
  date_utc=$(date -u +"%d%m%y")
  ddmmyy="$date_utc"

  # pick fix quality and satellites
  local fix_quality=1
  # make hdop from accuracy (if acc small -> hdop small)
  local hdop=$(awk -v a="$acc" 'BEGIN{ if(a<=0) a=1; printf "%.1f", (a/5) }')
  local altitude=$(printf "%.1f" "$alt")
  local geoid_height=0.0

  # speed knots (if spd number in m/s)
  local speed_knots
  speed_knots=$(awk -v s="$spd" 'BEGIN{ if(s==""||s==null) s=0; printf "%.2f", s*1.943844 }')
  local bearing_fmt=$(printf "%.1f" "${bearing:-0.0}")

  # Build GGA and RMC
  local gga="GPGGA,$time_utc,$lat_nmea,$lat_dir,$lon_nmea,$lon_dir,$fix_quality,00,$hdop,$altitude,M,$geoid_height,M,,"
  local rmc="GPRMC,$time_utc,A,$lat_nmea,$lat_dir,$lon_nmea,$lon_dir,$speed_knots,$bearing_fmt,$ddmmyy,,"

  printf "\$%s*%s\n" "$gga" "$(nmea_checksum "$gga")"
  printf "\$%s*%s\n" "$rmc" "$(nmea_checksum "$rmc")"

  # create satellite list (PRN:el:az:snr), number between MIN_SATS..MAX_SATS
  local sats=$(( MIN_SATS + RANDOM % (MAX_SATS - MIN_SATS + 1) ))
  local satstr
  satstr=$(gen_sat_list "$sats")
  # convert to array
  IFS=' ' read -r -a satarr <<< "$satstr"

  # Generate GSV messages
  generate_gsv_sentences "${satarr[*]}"

  # Build GSA: need only PRNs (extract from satarr)
  local prnlist=()
  for s in "${satarr[@]}"; do
    prnlist+=("${s%%:*}")
  done
  generate_gsa_sentence "${prnlist[@]}"

  # VTG and ZDA
  generate_vtg_sentence "$bearing_fmt" "$speed_knots"
  generate_zda_sentence
}

# ---------- main loop sending to PC ----------
echo "[*] Persistent Termux → NMEA streamer (full sentences)"
echo "[*] Sending GPS/NMEA to $PC_IP:$PORT every $INTERVAL second(s)"
echo "[*] Local IP:"
ifconfig | grep netmask
echo "[*] Press Ctrl+C to stop"

while true; do
  echo "[*] Connecting to $PC_IP:$PORT..."
  # feed the loop directly into nc so nc writes to TCP socket
  while true; do
    generate_nmea_full
    sleep "$INTERVAL"
  done | nc "$PC_IP" "$PORT"
  echo "[!] Connection lost. Retrying in 5s..."
  sleep 5
done
