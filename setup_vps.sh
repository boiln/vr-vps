#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

prompt_input() {
    read -p "$1: " value
    echo "$value"
}

prompt_yes_no() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Initialize task list
tasks=()

echo -e "${YELLOW}Welcome to VPS Setup Script${NC}"

# Prompt for necessary inputs
NEW_PASSWORD=$(prompt_input "Enter new password for root")
SSH_PORT=$(prompt_input "Enter desired SSH port")
INSTALL_DOCKER=$(prompt_yes_no "Do you want to install Docker?")

# Update and upgrade packages
echo -e "\n${YELLOW}Updating and upgrading packages...${NC}"
apt-get update -y && apt-get upgrade -y && apt-get autoremove -y
tasks+=("Update and upgrade packages")

# Change root password
echo -e "\n${YELLOW}Changing root password...${NC}"
echo "root:$NEW_PASSWORD" | chpasswd
tasks+=("Change root password")

# Install and configure unattended-upgrades
echo -e "\n${YELLOW}Installing and configuring unattended-upgrades...${NC}"
apt-get install -y unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
tasks+=("Install and configure unattended-upgrades")

# Install and configure UFW
echo -e "\n${YELLOW}Installing and configuring UFW...${NC}"
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw --force enable
tasks+=("Install and configure UFW")

# Configure SSH and SFTP
echo -e "\n${YELLOW}Configuring SSH and SFTP...${NC}"
apt-get install -y openssh-server
systemctl enable ssh
systemctl start ssh
cat > /etc/ssh/sshd_config <<EOL
Include /etc/ssh/sshd_config.d/*.conf

ClientAliveInterval 60
ClientAliveCountMax 3

Port $SSH_PORT
AddressFamily inet

PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication no

UsePAM yes

X11Forwarding yes
PrintMotd no

AcceptEnv LANG LC_*

Subsystem sftp internal-sftp
EOL

systemctl restart sshd
tasks+=("Configure SSH and SFTP")

# Install Docker if requested
if ! $INSTALL_DOCKER; then
    echo -e "\n${YELLOW}Skipping Docker installation...${NC}"
fi

if $INSTALL_DOCKER; then
    echo -e "\n${YELLOW}Installing Docker...${NC}"
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    tasks+=("Install Docker")
fi

# Disable default MOTD components
echo -e "\n${YELLOW}Disabling default MOTD components...${NC}"
chmod -x /etc/update-motd.d/*
tasks+=("Disable default MOTD components")

# Print summary of tasks
echo -e "\n${GREEN}Setup complete. The following tasks were performed:${NC}"
for task in "${tasks[@]}"; do
    echo -e "${GREEN}✓ $task${NC}"
done

echo -e "\n${YELLOW}Rebooting in 10 seconds...${NC}"
sleep 10
reboot
