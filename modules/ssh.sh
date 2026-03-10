#!/bin/bash
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
