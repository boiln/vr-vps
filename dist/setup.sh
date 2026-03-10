#!/bin/bash
set -euo pipefail

# ── module: lib ──
# Shared helpers — sourced by all modules

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[38;5;39m'
NC='\033[0m'

_STEP=0
tasks=()

log() {
    _STEP=$((_STEP + 1))
    echo -e "\n${YELLOW}[${_STEP}] $1${NC}"
}

done() {
    tasks+=("$1")
    echo -e "${GREEN}  ✓ $1${NC}"
}

fail() {
    echo -e "${RED}  ✗ $1${NC}"
}

prompt_input() {
    local value
    read -rp "$1: " value
    echo "$value"
}

prompt_input_default() {
    local value
    read -rp "$1 [$2]: " value
    echo "${value:-$2}"
}

prompt_yes_no() {
    while true; do
        read -rp "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# ── module: updates ──
# Updates + unattended-upgrades + needrestart module
# Requires: TIMEZONE

run_updates() {
    log "Updating packages"
    apt-get update -y -qq
    apt-get upgrade -y -qq
    apt-get autoremove -y -qq
    done "Update & upgrade packages"

    log "Setting timezone to $TIMEZONE"
    timedatectl set-timezone "$TIMEZONE"
    done "Timezone → $TIMEZONE"

    log "Configuring unattended-upgrades"
    apt-get install -y -qq unattended-upgrades

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    cat > /etc/apt/apt.conf.d/52unattended-upgrades-local << 'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF

    done "Unattended-upgrades (auto-reboot 04:00, auto-cleanup)"

    log "Setting needrestart to auto"
    apt-get install -y -qq needrestart
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    done "Needrestart → auto (no interactive prompts)"
}

# ── module: ssh ──
# SSH hardening module
# Requires: SSH_PORT, DISABLE_PASSWORD_AUTH

run_ssh() {
    log "Hardening SSH (port $SSH_PORT)"

    local pass_auth="yes"
    if $DISABLE_PASSWORD_AUTH; then
        pass_auth="no"
    fi

    # Fix cloud-init override if present
    if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
        echo "PasswordAuthentication $pass_auth" > /etc/ssh/sshd_config.d/50-cloud-init.conf
    fi

    cat > /etc/ssh/sshd_config << SSHEOF
Include /etc/ssh/sshd_config.d/*.conf

Port $SSH_PORT
AddressFamily inet
ClientAliveInterval 60
ClientAliveCountMax 3

PermitRootLogin yes
PasswordAuthentication $pass_auth
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitUserEnvironment no
DebianBanner no

PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp
SSHEOF

    sshd -t || { fail "SSH config invalid! Aborting."; exit 1; }
    systemctl restart sshd
    done "SSH hardened (port $SSH_PORT, password auth: $pass_auth)"
}

# ── module: firewall ──
# UFW firewall module
# Requires: SSH_PORT

run_firewall() {
    log "Configuring UFW"
    apt-get install -y -qq ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT/tcp" comment "SSH"
    ufw --force enable
    done "UFW enabled (deny incoming, SSH on $SSH_PORT allowed)"
}

# ── module: fail2ban ──
# Fail2ban module
# Requires: SSH_PORT

run_fail2ban() {
    log "Installing fail2ban"
    apt-get install -y -qq fail2ban

    cat > /etc/fail2ban/jail.local << F2BEOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
F2BEOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    done "Fail2ban (SSH: 3 attempts → 24h ban)"
}

# ── module: kernel ──
# Kernel hardening module (sysctl)

run_kernel() {
    log "Applying kernel hardening (sysctl)"
    cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Ignore ICMP broadcasts
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 router advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Harden BPF JIT
net.core.bpf_jit_harden = 2
EOF

    sysctl --system > /dev/null 2>&1
    done "Kernel hardened (anti-spoof, SYN flood, dmesg restrict, etc.)"
}

# ── module: swap ──
# Swap file module
# Requires: SWAP_SIZE

run_swap() {
    if [ "$SWAP_SIZE" = "0" ]; then
        return
    fi

    log "Creating ${SWAP_SIZE} swap"
    if [ ! -f /swapfile ]; then
        fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        done "Swap ${SWAP_SIZE} created"
    else
        echo "  Swap already exists, skipping."
        done "Swap (already existed)"
    fi
}

# ── module: docker ──
# Docker install + log rotation module

run_docker() {
    log "Installing Docker"
    apt-get install -y -qq ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Docker log rotation — merge into existing config or create new
    if [ -f /etc/docker/daemon.json ]; then
        python3 -c "
import json
with open('/etc/docker/daemon.json') as f:
    cfg = json.load(f)
cfg['log-driver'] = 'json-file'
cfg['log-opts'] = {'max-size': '10m', 'max-file': '3'}
with open('/etc/docker/daemon.json', 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
"
    else
        cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    fi

    systemctl restart docker
    done "Docker + log rotation (10m/3 files)"
}

# ── module: qol ──
# QoL tools, shell history, disk alert module

run_qol() {
    log "Installing QoL tools"
    apt-get install -y -qq tmux htop ncdu
    done "Installed tmux, htop, ncdu"

    log "Improving shell history"
    if ! grep -q 'HISTTIMEFORMAT' /root/.bashrc 2>/dev/null; then
        cat >> /root/.bashrc << 'EOF'

# History improvements
HISTTIMEFORMAT="%F %T  "
HISTSIZE=10000
HISTFILESIZE=20000
EOF
    fi
    done "Shell history (timestamps, 10k lines)"

    log "Adding disk space alert cron"
    local disk_cron='0 */6 * * * df / --output=pcent | tail -1 | tr -d " %" | xargs -I{} sh -c "[ {} -gt 85 ] && echo DISK {}% FULL | wall"'
    if ! crontab -l 2>/dev/null | grep -qF "DISK"; then
        (crontab -l 2>/dev/null; echo "$disk_cron") | crontab -
    fi
    done "Disk alert cron (every 6h, warns at 85%)"
}

# ── module: motd ──
# Custom MOTD module

run_motd() {
    log "Setting up custom MOTD"
    chmod -x /etc/update-motd.d/* 2>/dev/null || true

    cat > /etc/update-motd.d/00-custom << 'MOTDEOF'

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

# ── runner ──
# ── Preflight ───────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Run as root.${NC}"; exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          VPS Setup & Hardening             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo

# ── Prompts ─────────────────────────────────────────────────────────
SSH_PORT=$(prompt_input_default "SSH port" "22")
TIMEZONE=$(prompt_input_default "Timezone" "America/Chicago")
SWAP_SIZE=$(prompt_input_default "Swap size (0 to skip)" "2G")
INSTALL_DOCKER=false
prompt_yes_no "Install Docker?" && INSTALL_DOCKER=true
DISABLE_PASSWORD_AUTH=false
prompt_yes_no "Disable SSH password authentication?" && DISABLE_PASSWORD_AUTH=true
echo

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ── Run modules ─────────────────────────────────────────────────────
run_updates
run_ssh
run_firewall
run_fail2ban
run_kernel
run_swap
$INSTALL_DOCKER && run_docker
run_qol
run_motd

# ── Summary ─────────────────────────────────────────────────────────
echo
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Setup Complete                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo
for task in "${tasks[@]}"; do
    echo -e "  ${GREEN}✓${NC} $task"
done
echo
echo -e "${YELLOW}Reboot recommended to apply all changes.${NC}"
if prompt_yes_no "Reboot now?"; then
    reboot
fi
