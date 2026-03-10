#!/bin/bash
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
