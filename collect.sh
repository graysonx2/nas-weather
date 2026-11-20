#!/usr/bin/env bash
# NAS Weather collector. Reads only standard Linux files; no root needed.
# Usage:
#   ./collect.sh <out-dir>   write <out-dir>/forecast.json and append <out-dir>/history.jsonl
#   ./collect.sh --stdout    print the reading as JSON and write nothing
# Env: VOLUME (default /volume1, falls back to /), HISTORY_DAYS (default 14)
set -euo pipefail

VOLUME="${VOLUME:-/volume1}"; [ -d "$VOLUME" ] || VOLUME=/
HISTORY_DAYS="${HISTORY_DAYS:-14}"

host=$(hostname)
now=$(date +%s)
read -r load1 load5 load15 _ < /proc/loadavg
uptime_days=$(awk '{printf "%d", $1/86400}' /proc/uptime)

# Disk space for the main volume (bytes)
read -r size used < <(df -B1 --output=size,used "$VOLUME" | tail -1)

# Temperatures (°C) from hwmon by sensor name
temp_of() { # $1 = hwmon name
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "$1" ] || continue
    [ -r "$h/temp1_input" ] && awk '{printf "%d", $1/1000}' "$h/temp1_input" && return
  done
  echo null
}
cpu=$(temp_of coretemp); [ "$cpu" = null ] && cpu=$(temp_of k10temp)
nvme=$(temp_of nvme)

# Software RAID (md): level, member devices, and reshape/resync/recovery progress
raid=null
if [ -r /proc/mdstat ] && grep -q '^md' /proc/mdstat; then
  raid=$(awk '
    /^md/ { if (name) { out = out sep obj; sep="," }
            name=$1; level=$4; members="";
            for (i=5;i<=NF;i++){ d=$i; sub(/[0-9]*\[.*$/,"",d); members = members (members?",":"") "\"" d "\"" }
            act="null"; pct="null"; eta="null"; degraded="false" }
    /\[[U_]+\]/ { if ($NF ~ /_/) degraded="true" }
    /(reshape|resync|recovery|check) *=/ {
            match($0,/(reshape|resync|recovery|check)/); act="\"" substr($0,RSTART,RLENGTH) "\"";
            match($0,/[0-9.]+%/); pct=substr($0,RSTART,RLENGTH-1);
            if (match($0,/finish=[0-9.]+min/)) eta=substr($0,RSTART+7,RLENGTH-10) }
    { obj = "{\"name\":\"" name "\",\"level\":\"" level "\",\"members\":[" members "],\"degraded\":" degraded ",\"activity\":" act ",\"progress\":" pct ",\"etaMin\":" eta "}" }
    END { if (name) print "[" out sep obj "]"; else print "null" }' /proc/mdstat)
fi

# Drives: bay from the controller port in /dev/disk/by-path (falls back to discovery order)
drives=""; n=0
for dev in /sys/block/sd*; do
  [ -e "$dev" ] || continue
  name=$(basename "$dev"); n=$((n+1)); bay=$n
  link=$(ls -l /dev/disk/by-path/ 2>/dev/null | grep -E "ata-[0-9]+ -> \.\./\.\./$name\$" | head -1 || true)
  [[ $link =~ ata-([0-9]+)\ -\> ]] && bay=${BASH_REMATCH[1]}
  model=$(tr -s ' ' < "$dev/device/model" 2>/dev/null | sed 's/ *$//' || echo "")
  bytes=$(( $(cat "$dev/size") * 512 ))
  drives+="${drives:+,}{\"bay\":$bay,\"dev\":\"$name\",\"model\":\"$model\",\"bytes\":$bytes}"
done

json="{\"host\":\"$host\",\"time\":$now,\"load\":[$load1,$load5,$load15],\"uptimeDays\":$uptime_days,\"temps\":{\"cpu\":$cpu,\"nvme\":$nvme},\"volume\":{\"path\":\"$VOLUME\",\"bytes\":$size,\"used\":$used},\"raid\":$raid,\"drives\":[$drives]}"

if [ "${1:-}" = "--stdout" ]; then echo "$json"; exit 0; fi
out="${1:?usage: collect.sh <out-dir> | --stdout}"
mkdir -p "$out"
echo "$json" > "$out/forecast.json.tmp" && mv "$out/forecast.json.tmp" "$out/forecast.json"
# History: one compact line per reading, trimmed to HISTORY_DAYS
echo "{\"t\":$now,\"load\":$load1,\"cpu\":$cpu,\"used\":$used}" >> "$out/history.jsonl"
cutoff=$((now - HISTORY_DAYS*86400))
awk -v c="$cutoff" -F'[:,]' '$2+0 >= c' "$out/history.jsonl" > "$out/history.jsonl.tmp" && mv "$out/history.jsonl.tmp" "$out/history.jsonl"
