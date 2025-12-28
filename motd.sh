#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[38;5;39m'
R='\033[0m'

start_time=$(date +%s.%N)

echo -e "${ORANGE}$(date)${R}"

echo

# System information
echo -e "${CYAN}System${R}"
(
    echo -e "  ${ORANGE}Uptime${R}\t$(uptime -p | sed 's/^up.//')"
    echo -e "  ${ORANGE}CPU${R}\t$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
    echo -e "  ${ORANGE}Memory${R}\t$(free -m | awk '/Mem:/ {printf("%.2f%%\n", $3/$2*100)}')"
    echo -e "  ${ORANGE}Logged In${R}\t$(who | wc -l)"
    echo -e "  ${ORANGE}Last login${R}\t$(last -1 $USER | awk 'NR==1 {print $4,$5,$6,$7}')"
    echo -e "  ${ORANGE}Failed SSH attempts${R}\t$(grep "Failed password" /var/log/auth.log | wc -l)"
    echo -e "  ${ORANGE}Network traffic${R}\t$(awk '{if(NR==3) {rx=$2/1024/1024; tx=$10/1024/1024; printf "%.2f / %.2f MB ", rx, tx; if(rx+tx > 10) print "(High)"; else if(rx+tx > 1) print "(Moderate)"; else print "(Low)"}}' /proc/net/dev)"
    echo -e "  ${ORANGE}IPv4 address${R}\t$(ip addr show ens3 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
    echo -e "  ${ORANGE}IPv6 address${R}\t$(ip addr show ens3 | grep -oP '(?<=inet6\s)\S+' | head -n 1)"
) | column -t -s $'\t'

echo

# Disk usage
echo -e "${CYAN}Disk${R}"
(
    echo -e "  ${ORANGE}Root (/)${R}\t$(df -h / | awk '/\// {print $3" / "$2}')"
    echo -e "  ${ORANGE}Home (/home)${R}\t$(df -h /home | awk '/\// {print $3" / "$2}')"
    echo -e "  ${ORANGE}Docker (/var/lib/docker)${R}\t$(df -h /var/lib/docker | awk 'NR==2 {print $3" / "$2}')"
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
    # echo -e "  NAMES\tSTATUS"
    docker ps --format "{{.Names}}\t{{.Status}}" | \
    while IFS=$'\t' read -r name status id; do
      printf "  ${ORANGE}%s${R}\t%s\t%s\n" "$name" "$status" "$id"
    done
  ) | column -t -s $'\t'
fi

echo

end_time=$(date +%s.%N)
execution_time=$(echo "$end_time - $start_time" | bc)
execution_ms=$(echo "$execution_time * 1000" | bc | cut -d'.' -f1)

if [ "$execution_ms" -ge 1000 ]; then
    execution_s=$(echo "scale=1; $execution_ms / 1000" | bc)
    echo -e "${CYAN}${GREEN}${execution_s} s${R}"
fi

if [ "$execution_ms" -lt 1000 ]; then
    echo -e "${CYAN}${GREEN}${execution_ms} ms${R}"
fi

echo
echo -e "${ORANGE}════════════════════════════════════════════${R}"
echo
