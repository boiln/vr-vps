#!/bin/bash
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
