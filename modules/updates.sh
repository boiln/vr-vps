#!/bin/bash
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
