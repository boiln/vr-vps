# VPS Setup & Hardening

Fresh Ubuntu VPS → hardened + QoL in one command.

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/boiln/vr-vps/main/dist/setup.sh | bash
```

## What It Does

| Category       | Details                                                                                             |
| -------------- | --------------------------------------------------------------------------------------------------- |
| **Updates**    | `apt upgrade`, unattended-upgrades with auto-reboot at 04:00, needrestart auto mode                 |
| **SSH**        | Custom port, MaxAuthTries 3, disable forwarding/X11, optional password auth disable, cloud-init fix |
| **Firewall**   | UFW deny incoming, allow SSH port                                                                   |
| **Fail2ban**   | SSH jail — 3 failed attempts → 24h ban via UFW                                                      |
| **Kernel**     | sysctl: anti-spoof, SYN flood, disable redirects/source routing, dmesg/kptr restrict, BPF harden    |
| **Swap**       | Configurable swap file (default 2G) — prevents OOM kills                                            |
| **Docker**     | Optional install + log rotation (10m/3 files)                                                       |
| **Tools**      | tmux, htop, ncdu                                                                                    |
| **Shell**      | History timestamps, 10k lines                                                                       |
| **Monitoring** | Disk space alert cron (every 6h, warns at 85%)                                                      |
| **MOTD**       | Custom login banner: system stats, disk, containers, failed SSH, network                            |

## Structure

```
build.sh              ← builds dist/setup.sh from modules
modules/
  lib.sh              ← colors, helpers, prompt functions
  updates.sh          ← apt upgrade, unattended-upgrades, needrestart, timezone
  ssh.sh              ← sshd config, cloud-init fix, hardening
  firewall.sh         ← ufw setup
  fail2ban.sh         ← fail2ban + ssh jail
  kernel.sh           ← sysctl hardening
  swap.sh             ← swap file creation
  docker.sh           ← docker install + log rotation
  qol.sh              ← tmux/htop/ncdu, shell history, disk alert cron
  motd.sh             ← custom login banner
dist/
  setup.sh            ← built single-file script (curl this)
```

## Dev

Edit modules, then build:

```bash
./build.sh
```

<img width="557" height="624" alt="motd" src="https://github.com/user-attachments/assets/c40a595e-dc55-40ae-8607-10b0ebd3e99d" />
