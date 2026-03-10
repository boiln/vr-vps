#!/bin/bash
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
