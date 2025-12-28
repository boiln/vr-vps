#!/bin/bash

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[38;5;39m'
R='\033[0m'

NET_IFACE=$(ip route | awk '/default/ {print $5; exit}')

start_time=$(date +%s%3N)

# Gather data in parallel using temp files for subshell capture
tmp_ip=$(mktemp)
tmp_docker=$(mktemp)
trap "rm -f $tmp_ip $tmp_docker" EXIT

ip addr show "$NET_IFACE" > "$tmp_ip" &
docker ps --format "{{.Names}}\t{{.Status}}" 2>/dev/null > "$tmp_docker" &
wait

# Parse gathered data
ipv4=$(grep 'dynamic' "$tmp_ip" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
ipv4_additional=$(grep -v 'dynamic' "$tmp_ip" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ipv6=$(grep 'scope global' "$tmp_ip" | grep -oP '(?<=inet6\s)[0-9a-f:]+' | head -1)

echo -e "${ORANGE}$(date)${R}"

echo

# System information
echo -e "${CYAN}System${R}"
(
    echo -e "  ${ORANGE}Uptime${R}\t$(uptime -p | sed 's/^up.//')"
    echo -e "  ${ORANGE}CPU${R}\t$(awk '/^cpu / {u=$2+$4; t=$2+$3+$4+$5; if(t>0) printf "%.1f%%", u*100/t}' /proc/stat)"
    echo -e "  ${ORANGE}Memory${R}\t$(awk '/MemTotal:/{t=$2} /MemAvailable:/{a=$2} END{printf "%.2f%%", (t-a)/t*100}' /proc/meminfo)"
    echo -e "  ${ORANGE}Logged In${R}\t$(who | wc -l)"
    echo -e "  ${ORANGE}Last login${R}\t$(last -1 $USER | awk 'NR==1 {print $4,$5,$6,$7}')"
    echo -e "  ${ORANGE}Failed SSH attempts${R}\t$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)"
    echo -e "  ${ORANGE}Network traffic${R}\t$(awk -v iface="$NET_IFACE:" '$1 == iface {rx=$2/1024/1024; tx=$10/1024/1024; printf "%.2f / %.2f MB ", rx, tx; level="(Low)"; if(rx+tx > 1) level="(Moderate)"; if(rx+tx > 10) level="(High)"; print level}' /proc/net/dev)"
    echo -e "  ${ORANGE}IPv4 address${R}\t$ipv4"
    [ -n "$ipv4_additional" ] && echo -e "  ${ORANGE}IPv4 additional${R}\t$ipv4_additional"
    echo -e "  ${ORANGE}IPv6 address${R}\t$ipv6"
) | column -t -s $'\t'

echo

# Disk usage
echo -e "${CYAN}Disk${R}"
(
    df -h / | awk 'NR==2 {printf "  \033[0;33mRoot (/)\033[0m\t%s / %s\n", $3, $2}'
) | column -t -s $'\t'

echo

# Update information
echo -e "${CYAN}Updates${R}"
if [ ! -f /var/lib/update-notifier/updates-available ]; then
  echo "  No update information available"
fi

if [ -f /var/lib/update-notifier/updates-available ]; then
  updates_pending=$(sed -n 's/^[0-9]* updates can be applied immediately\.$/\0/p' /var/lib/update-notifier/updates-available | rg -o '[0-9]*')
  security_updates=$(sed -n 's/^[0-9]* of these updates are security updates\.$/\0/p' /var/lib/update-notifier/updates-available | rg -o '[0-9]*')
  
  (
    echo -e "  ${ORANGE}General updates${R}\t${updates_pending:-0}"
    echo -e "  ${ORANGE}Security updates${R}\t${security_updates:-0}"
  ) | column -t -s $'\t'
fi

echo

# Docker container information
echo -e "${CYAN}Containers${R}"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not accessible."
fi

if command -v docker >/dev/null 2>&1; then
  (
    cat "$tmp_docker" | while IFS=$'\t' read -r name status; do
      [ -n "$name" ] && printf "  ${ORANGE}%s${R}\t%s\n" "$name" "$status"
    done
  ) | column -t -s $'\t'
fi

echo

end_time=$(date +%s%3N)
execution_ms=$((end_time - start_time))

if [ "$execution_ms" -ge 1000 ]; then
    echo -e "${GREEN}$((execution_ms / 1000)).$((execution_ms % 1000 / 100)) s${R}"
fi

if [ "$execution_ms" -lt 1000 ]; then
    echo -e "${GREEN}${execution_ms} ms${R}"
fi

echo
echo -e "${ORANGE}════════════════════════════════════════════${R}"
echo
