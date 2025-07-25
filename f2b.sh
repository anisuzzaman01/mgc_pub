#!/bin/bash

clear
# ========== COLORS ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# ========== CUSTOM SSHD BLOCK ==========
CUSTOM_SSHD_BLOCK="[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600
backend = systemd
action = iptables[name=SSH, port=ssh, protocol=tcp]"

# ========== INSTALL FAIL2BAN ==========
install_fail2ban() {
    echo -e "${CYAN}[*] Installing Fail2Ban...${NC}"
    sudo apt update && sudo apt install -y fail2ban

    echo -e "${CYAN}[*] Enabling and starting Fail2Ban...${NC}"
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban

    echo -e "${CYAN}[*] Configuring jail.local...${NC}"
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

    # Replace SSHD block
    sudo awk -v block="$CUSTOM_SSHD_BLOCK" '
        BEGIN {skip=0}
        /^\[sshd\]/ {print block; skip=1; next}
        skip && /^\[.*\]/ {skip=0}
        !skip {print}
    ' /etc/fail2ban/jail.local > /tmp/jail.local && sudo mv /tmp/jail.local /etc/fail2ban/jail.local

    sudo systemctl restart fail2ban
    echo -e "${GREEN}[✔] Fail2Ban installed and configured for SSH.${NC}"
}

# ========== REMOVE FAIL2BAN ==========
remove_fail2ban() {
    echo -e "${RED}[-] Removing Fail2Ban...${NC}"
    sudo systemctl stop fail2ban
    sudo apt purge -y fail2ban
    sudo apt autoremove -y
    sudo rm -rf /etc/fail2ban /var/log/fail2ban.log /var/lib/fail2ban /var/run/fail2ban
    echo -e "${GREEN}[✔] Fail2Ban and related files removed.${NC}"
}

# ========== MONITOR MENU ==========
monitor_fail2ban() {
    while true; do
        echo -e "\n${CYAN}========= Fail2Ban Monitor =========${NC}"
        echo -e "${YELLOW}1${NC}) View live SSH ban logs"
        echo -e "${YELLOW}2${NC}) View SSH jail status"
        echo -e "${YELLOW}3${NC}) View all jail summary"
        echo -e "${YELLOW}4${NC}) View firewall ban rules (iptables/nftables)"
        echo -e "${YELLOW}q${NC}) Back to main menu"
        echo -e "${CYAN}====================================${NC}"
        read -rp "$(echo -e "${CYAN}Choose an option: ${NC}")" monitor_choice

        case "$monitor_choice" in
            1)
                echo -e "${GREEN}==> Press Ctrl+C to stop logs.${NC}"
                sudo tail -f /var/log/fail2ban.log
                ;;
            2)
                echo -e "${GREEN}==> SSH Jail Status:${NC}"
                sudo systemctl is-active --quiet fail2ban || sudo systemctl start fail2ban
                sudo fail2ban-client status sshd 2>/dev/null || echo -e "${RED}[!] Jail not active or error reading status.${NC}"
                ;;
            3)
                echo -e "${GREEN}==> All Jail Summary:${NC}"
                sudo systemctl is-active --quiet fail2ban || sudo systemctl start fail2ban
                sudo fail2ban-client status 2>/dev/null || echo -e "${RED}[!] Failed to retrieve summary.${NC}"
                ;;
            4)
                echo -e "${GREEN}==> Checking active firewall bans...${NC}"
                if sudo nft list ruleset 2>/dev/null | grep -q fail2ban; then
                    echo -e "${YELLOW}[+] nftables rules detected:${NC}"
                    sudo nft list ruleset | grep -A10 fail2ban
                elif sudo iptables -L -n | grep -q "f2b-"; then
                    echo -e "${YELLOW}[+] iptables rules detected:${NC}"
                    sudo iptables -L -n --line-numbers | grep "f2b-" || echo "No rules in main chain."
                    echo -e "\n${CYAN}→ Checking contents of f2b-* chains:${NC}"
                    for chain in $(sudo iptables -S | grep -o 'f2b-[a-zA-Z0-9_-]*' | sort -u); do
                        echo -e "\n${BLUE}Chain: $chain${NC}"
                        sudo iptables -L $chain -n --line-numbers
                    done
                else
                    echo -e "${RED}[!] No active ban rules found in iptables or nftables.${NC}"
                fi
                ;;
            q|Q)
                break
                ;;
            *)
                echo -e "${RED}[!] Invalid option.${NC}"
                ;;
        esac
    done
}

# ========== MAIN MENU ==========
while true; do
    echo -e "\n${BLUE}========= Fail2Ban Manager =========${NC}"
    echo -e "${YELLOW}1${NC}) Install Fail2Ban SSH protection"
    echo -e "${YELLOW}2${NC}) Remove Fail2Ban and all configs"
    echo -e "${YELLOW}3${NC}) Monitor/Report Fail2Ban activity"
    echo -e "${YELLOW}q${NC}) Quit"
    echo -e "${BLUE}====================================${NC}"
    read -rp "$(echo -e "${CYAN}Choose an option: ${NC}")" main_choice

    case "$main_choice" in
        1)
            if command -v fail2ban-client >/dev/null; then
                echo -e "${YELLOW}[!] Fail2Ban already installed.${NC}"
            else
                install_fail2ban
            fi
            ;;
        2) remove_fail2ban ;;
        3) monitor_fail2ban ;;
        q|Q)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *) echo -e "${RED}[!] Invalid option.${NC}" ;;
    esac
done
