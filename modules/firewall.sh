#!/bin/bash
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
