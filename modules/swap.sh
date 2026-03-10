#!/bin/bash
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
