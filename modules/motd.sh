#!/bin/bash
# Custom MOTD module

run_motd() {
    log "Setting up custom MOTD"
    chmod -x /etc/update-motd.d/* 2>/dev/null || true

    cat > /etc/update-motd.d/00-custom << 'MOTDEOF'
#!/bin/bash

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[38;5;39m'
R='\033[0m'

NET_IFACE=$(ip route | awk '/default/ {print $5; exit}')

start_time=$(date +%s%3N)

# Gather data in parallel
tmp_ip=$(mktemp)
tmp_docker=$(mktemp)
trap "rm -f $tmp_ip $tmp_docker" EXIT

ip addr show "$NET_IFACE" > "$tmp_ip" &
docker ps --format "{{.Names}}\t{{.Status}}" 2>/dev/null > "$tmp_docker" &
wait

# Parse
ipv4=$(grep 'dynamic' "$tmp_ip" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
ipv4_additional=$(grep -v 'dynamic' "$tmp_ip" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ipv6=$(grep 'scope global' "$tmp_ip" | grep -oP '(?<=inet6\s)[0-9a-f:]+' | head -1)

echo -e "${ORANGE}$(date)${R}"
echo

# System
echo -e "${CYAN}System${R}"
(
    echo -e "  ${ORANGE}Uptime${R}\t$(uptime -p | sed 's/^up.//')"
    echo -e "  ${ORANGE}CPU${R}\t$(awk '/^cpu / {u=$2+$4; t=$2+$3+$4+$5; if(t>0) printf "%.1f%%", u*100/t}' /proc/stat)"
    echo -e "  ${ORANGE}Memory${R}\t$(awk '/MemTotal:/{t=$2} /MemAvailable:/{a=$2} END{printf "%.2f%%", (t-a)/t*100}' /proc/meminfo)"
    echo -e "  ${ORANGE}Logged In${R}\t$(who | wc -l)"
    echo -e "  ${ORANGE}Last login${R}\t$(last -1 "$USER" | awk 'NR==1 {print $4,$5,$6,$7}')"
    echo -e "  ${ORANGE}Failed SSH${R}\t$(grep -c 'Failed password' /var/log/auth.log 2>/dev/null || echo 0)"
    echo -e "  ${ORANGE}Network${R}\t$(awk -v iface="$NET_IFACE:" '$1 == iface {rx=$2/1024/1024; tx=$10/1024/1024; printf "%.2f / %.2f MB ", rx, tx; level="(Low)"; if(rx+tx > 1) level="(Moderate)"; if(rx+tx > 10) level="(High)"; print level}' /proc/net/dev)"
    echo -e "  ${ORANGE}IPv4${R}\t$ipv4"
    [ -n "$ipv4_additional" ] && echo -e "  ${ORANGE}IPv4 (extra)${R}\t$ipv4_additional"
    [ -n "$ipv6" ] && echo -e "  ${ORANGE}IPv6${R}\t$ipv6"
) | column -t -s $'\t'

echo

# Disk
echo -e "${CYAN}Disk${R}"
(
    df -h / | awk 'NR==2 {printf "  \033[0;33mRoot (/)\033[0m\t%s / %s (%s)\n", $3, $2, $5}'
    if swapon --show=SIZE --noheadings 2>/dev/null | grep -q .; then
        echo -e "  ${ORANGE}Swap${R}\t$(free -h | awk '/Swap:/{print $3, "/", $2}')"
    fi
) | column -t -s $'\t'

echo

# Updates
echo -e "${CYAN}Updates${R}"
if [ -f /var/lib/update-notifier/updates-available ]; then
  updates_pending=$(grep -oP '^\d+(?= updates can be applied)' /var/lib/update-notifier/updates-available 2>/dev/null || echo "0")
  security_updates=$(grep -oP '^\d+(?= of these updates are security)' /var/lib/update-notifier/updates-available 2>/dev/null || echo "0")
  (
    echo -e "  ${ORANGE}Pending${R}\t${updates_pending}"
    echo -e "  ${ORANGE}Security${R}\t${security_updates}"
  ) | column -t -s $'\t'
else
  echo "  No update information available"
fi

echo

# Docker
if command -v docker >/dev/null 2>&1; then
    echo -e "${CYAN}Containers${R}"
    if [ -s "$tmp_docker" ]; then
        (
            while IFS=$'\t' read -r name status; do
                [ -n "$name" ] && printf "  ${ORANGE}%s${R}\t%s\n" "$name" "$status"
            done < "$tmp_docker"
        ) | column -t -s $'\t'
    else
        echo "  No running containers"
    fi
    echo
fi

end_time=$(date +%s%3N)
execution_ms=$((end_time - start_time))

if [ "$execution_ms" -ge 1000 ]; then
    echo -e "${GREEN}$((execution_ms / 1000)).$((execution_ms % 1000 / 100))s${R}"
else
    echo -e "${GREEN}${execution_ms}ms${R}"
fi

echo
echo -e "${ORANGE}════════════════════════════════════════════${R}"
echo
MOTDEOF

    chmod +x /etc/update-motd.d/00-custom
    done "Custom MOTD installed"
}
