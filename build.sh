#!/bin/bash
# Builds a single self-contained setup.sh from modules
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/dist/setup.sh"

mkdir -p "$SCRIPT_DIR/dist"

{
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo ''

    # Inline each module (strip shebangs and set commands)
    for mod in lib updates ssh firewall fail2ban kernel swap docker qol motd; do
        echo "# ── module: ${mod} ──"
        sed '/^#!/d; /^set -euo pipefail$/d' "$SCRIPT_DIR/modules/${mod}.sh"
        echo ''
    done

    # Inline the runner
    echo '# ── runner ──'
    cat << 'RUNNER'
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
RUNNER

} > "$OUT"

chmod +x "$OUT"
echo "Built → dist/setup.sh ($(wc -l < "$OUT") lines)"
