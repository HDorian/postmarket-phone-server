#!/bin/bash
# server-dash.sh — flicker-free full-height server metrics panel (top tmux pane).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
INTERVAL=2
BATP=/sys/class/power_supply/bq27411-0
STATSF=/tmp/.nono-dstats

bar(){ local p=${1:-0} w=${2:-10} i f s=""; f=$((p*w/100)); [ $f -gt $w ]&&f=$w; [ $f -lt 0 ]&&f=0
  for ((i=0;i<w;i++)); do [ $i -lt $f ]&&s+='#'||s+='.'; done; printf '%s' "$s"; }
mark(){ case $1 in *healthy*|*running*|*up*) printf '\033[32m%s\033[0m' "$2";; *) printf '\033[31m%s\033[0m' "$2";; esac; }
sep(){ printf '\033[K\n \033[90m──── \033[36m%s \033[90m%s\033[0m\033[K\n' "$1" "$(printf '%.0s─' $(seq 1 $((56-${#1}))) )"; }

declare -A PI PT CP
read_cpu(){ local core a b c d e f g h idle tot di dt
  while read -r core a b c d e f g h _; do case $core in cpu|cpu[0-9]*) ;; *) continue;; esac
    idle=$((d+e)); tot=$((a+b+c+d+e+f+g+h)); di=$((idle-${PI[$core]:-$idle})); dt=$((tot-${PT[$core]:-$tot}))
    CP[$core]=0; [ $dt -gt 0 ]&&CP[$core]=$(((dt-di)*100/dt)); PI[$core]=$idle; PT[$core]=$tot
  done < <(grep '^cpu' /proc/stat); }
rate(){ local b=${1:-0}; if [ $b -ge 1048576 ]; then awk -v b=$b 'BEGIN{printf "%5.1f MB/s",b/1048576}'
  elif [ $b -ge 1024 ]; then awk -v b=$b 'BEGIN{printf "%5.1f KB/s",b/1024}'; else printf '%4d B/s' $b; fi; }
cst(){ grep "^$1|" "$STATSF" 2>/dev/null | head -1; }

# background: cpu/mem for ALL running containers (docker stats is slow -> decoupled)
( while :; do docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' \
    >"$STATSF.tmp" 2>/dev/null && mv "$STATSF.tmp" "$STATSF"; sleep 4; done ) &
SPID=$!
NC=$(nproc); PRX=0; PTX=0; FIRST=1
printf '\033[?25l\033[2J'
trap 'kill $SPID 2>/dev/null; printf "\033[?25h\033[2J\033[H"; exit 0' INT TERM

while true; do
  read_cpu; CA=${CP[cpu]:-0}
  read -r L1 L2 L3 _ </proc/loadavg
  FREQ=$(awk -v f="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null||cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq 2>/dev/null||echo 0)" 'BEGIN{printf "%.2f", f/1e6}')
  CMAX=0; GPU=?; MODEM=?; WLANT=?; MEMT=?
  for z in /sys/class/thermal/thermal_zone*; do ty=$(cat "$z/type" 2>/dev/null); tv=$(cat "$z/temp" 2>/dev/null); [ -z "$tv" ]&&continue; cc=$((tv/1000))
    case $ty in cpu*thermal) [ $cc -gt $CMAX ]&&CMAX=$cc;; gpu*) GPU=$cc;; modem*) MODEM=$cc;; wlan*) WLANT=$cc;; mem-*) MEMT=$cc;; esac; done
  MT=$(awk '/MemTotal/{print $2}' /proc/meminfo); MA=$(awk '/MemAvailable/{print $2}' /proc/meminfo); MU=$((MT-MA)); MP=$((MU*100/MT))
  read -r DGT DGU DP < <(df -P / | awk 'NR==2{gsub("%","",$5);print $2,$3,$5}')
  RX=$(cat /sys/class/net/wlan0/statistics/rx_bytes 2>/dev/null||echo 0); TX=$(cat /sys/class/net/wlan0/statistics/tx_bytes 2>/dev/null||echo 0)
  DRX=$(((RX-PRX)/INTERVAL)); DTX=$(((TX-PTX)/INTERVAL)); [ $FIRST -eq 1 ]&&{ DRX=0; DTX=0; }; PRX=$RX; PTX=$TX
  IP=$(ip -4 addr show wlan0 2>/dev/null|awk '/inet /{print $2;exit}'); IP=${IP%/*}
  EST=$(ss -tH state established 2>/dev/null | wc -l); [ -z "$EST" ]&&EST=?
  BP=$(cat $BATP/capacity 2>/dev/null); BS=$(cat $BATP/status 2>/dev/null); BTC=$(( $(cat $BATP/temp 2>/dev/null||echo 0)/10 ))
  BV=$(cat $BATP/voltage_now 2>/dev/null||echo 0); BIc=$(cat $BATP/current_now 2>/dev/null||echo 0)
  BINFO=$(awk -v v=$BV -v c=$BIc 'BEGIN{printf "%.2f V  %+.2f A  %+.1f W", v/1e6, c/1e6, (v/1e6)*(c/1e6)}')
  case $BS in Charging) BA=charging;; Full) BA=full;; *) BA=discharging;; esac
  read -r UP _ </proc/uptime; UP=${UP%.*}; UPS=$(printf '%dd %02dh %02dm' $((UP/86400)) $(((UP%86400)/3600)) $(((UP%3600)/60)))
  YR=$(date +%Y); [ "$YR" -ge 2025 ]&&NTP='\033[32msynced\033[0m'||NTP='\033[31m1970!\033[0m'
  { pidof cloudflared >/dev/null 2>&1 || pgrep cloudflared >/dev/null 2>&1; } && TUN=up || TUN=DOWN
  RJOB=$(docker logs --tail 40 nono-runner 2>/dev/null | grep -E 'Running job|Listening for Jobs' | tail -1)
  case $RJOB in *Running*) RST='\033[33mrunning a job\033[0m';; *Listening*) RST='\033[32midle\033[0m';; *) RST='?';; esac
  HM=$(docker ps -q 2>/dev/null | xargs -r docker inspect -f '{{.Name}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null | sed 's#^/##' | sort)
  NCT=$(printf '%s\n' "$HM" | grep -c .)

  {
  printf '\033[H'
  printf ' \033[1;36mNoNo server\033[0m · dumpling            up %s\033[K\n' "$UPS"
  printf ' %s   NTP %b\033[K\n' "$(date '+%a %Y-%m-%d %H:%M:%S')" "$NTP"
  sep CPU
  printf ' total [%s] %3d%%  %dc @%sG   ld %s %s %s\033[K\n' "$(bar $CA 12)" "$CA" "$NC" "$FREQ" "$L1" "$L2" "$L3"
  printf ' c0[%s]%3d c1[%s]%3d c2[%s]%3d c3[%s]%3d\033[K\n' "$(bar ${CP[cpu0]:-0} 4)" "${CP[cpu0]:-0}" "$(bar ${CP[cpu1]:-0} 4)" "${CP[cpu1]:-0}" "$(bar ${CP[cpu2]:-0} 4)" "${CP[cpu2]:-0}" "$(bar ${CP[cpu3]:-0} 4)" "${CP[cpu3]:-0}"
  printf ' c4[%s]%3d c5[%s]%3d c6[%s]%3d c7[%s]%3d\033[K\n' "$(bar ${CP[cpu4]:-0} 4)" "${CP[cpu4]:-0}" "$(bar ${CP[cpu5]:-0} 4)" "${CP[cpu5]:-0}" "$(bar ${CP[cpu6]:-0} 4)" "${CP[cpu6]:-0}" "$(bar ${CP[cpu7]:-0} 4)" "${CP[cpu7]:-0}"
  sep THERMAL
  printf ' cpu \033[33m%s°\033[0m  gpu %s°  mem %s°  modem %s°  wlan %s°  batt %s°\033[K\n' "$CMAX" "$GPU" "$MEMT" "$MODEM" "$WLANT" "$BTC"
  sep 'MEM / DISK'
  printf ' mem  [%s] %3d%%   %d / %d MB   free %d MB\033[K\n' "$(bar $MP 12)" "$MP" "$((MU/1024))" "$((MT/1024))" "$((MA/1024))"
  printf ' disk [%s] %3s%%   %d / %d GB  (/)\033[K\n' "$(bar ${DP:-0} 12)" "${DP:-0}" "$((DGU/1048576))" "$((DGT/1048576))"
  sep NETWORK
  printf ' wlan0 %-16s ↓%s  ↑%s  tcp %s\033[K\n' "${IP:-none}" "$(rate $DRX)" "$(rate $DTX)" "$EST"
  sep POWER
  printf ' batt [%s] %3s%%  %s\033[K\n' "$(bar ${BP:-0} 12)" "${BP:-?}" "$BA"
  printf '      %s   %s°C\033[K\n' "$BINFO" "$BTC"
  sep "CONTAINERS — $NCT up"
  printf '%s\n' "$HM" | while IFS='|' read -r nm hs; do
    [ -z "$nm" ] && continue
    l=$(cst "$nm"); cpu=$(printf '%s' "$l"|cut -d'|' -f2); mem=$(printf '%s' "$l"|cut -d'|' -f3|awk '{print $1}')
    printf ' %-13s %b %-9s cpu %-6s mem %s\033[K\n' "$nm" "$(mark "$hs" '●')" "$hs" "${cpu:-—}" "${mem:-—}"
  done
  sep SERVICES
  printf ' tunnel %b %b   runner %b\033[K\n' "$(mark "$TUN" '●')" "$TUN" "$RST"
  printf ' shop-dev.nonos-shop.com   admin-dev.nonos-shop.com\033[K'
  printf '\033[J'
  }
  FIRST=0; sleep $INTERVAL
done
