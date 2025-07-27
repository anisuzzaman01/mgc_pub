#!/bin/bash

# Fail2Ban Manager Script for RHEL/CentOS 7
# Author: ChatGPT | Version: 1.0

set -e

EPEL_URL="https://download.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-13.noarch.rpm"
EPEL_RPM="/tmp/epel-release-7-13.noarch.rpm"
JAIL_LOCAL="/etc/fail2ban/jail.local"
SSH_JAIL_CONFIG="
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 3
bantime = 3600
findtime = 600
"

# === Helper Functions ===

log_info() { echo -e "\e[32m[INFO]\e[0m $1"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }

pause() {
    read -rp $'\nPress ENTER to continue...'
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

install_epel() {
    if rpm -q epel-release &>/dev/null; then
        log_info "EPEL is already installed."
        return 0
    fi

    log_info "Installing EPEL repository..."

    rm -f "$EPEL_RPM"
    curl -s -L -o "$EPEL_RPM" "$EPEL_URL"

    if [[ ! -s "$EPEL_RPM" ]]; then
        log_error "Downloaded EPEL RPM is empty or failed."
        exit 1
    fi

    yum install -y "$EPEL_RPM" || {
        log_error "Failed to install EPEL."
        exit 1
    }

    log_info "EPEL installed successfully."
}

install_fail2ban() {
    install_epel

    log_info "Installing Fail2Ban..."
    yum install -y fail2ban

    systemctl enable fail2ban
    systemctl start fail2ban

    log_info "Fail2Ban installed and started."

    if [[ -f "$JAIL_LOCAL" ]]; then
        cp "$JAIL_LOCAL" "${JAIL_LOCAL}.bak"
    fi

    echo "$SSH_JAIL_CONFIG" > "$JAIL_LOCAL"
    systemctl restart fail2ban

    log_info "SSH jail configured in jail.local."
}

remove_fail2ban() {
    log_info "Removing Fail2Ban and its config..."

    systemctl stop fail2ban || true
    yum remove -y fail2ban || true

    rm -f /etc/fail2ban/jail.local
    rm -f /etc/fail2ban/jail.d/*

    log_info "Fail2Ban and configs removed."
}

monitor_fail2ban() {
    clear
    echo "========= Fail2Ban Monitor ========="
    echo "1) View live SSH ban logs"
    echo "2) View SSH jail status"
    echo "3) View all jail summary"
    echo "4) View firewall ban rules (iptables)"
    echo "q) Back to main menu"
    echo "===================================="
    read -rp "Choose an option: " choice

    case "$choice" in
        1) journalctl -u fail2ban -f ;;
        2) fail2ban-client status sshd ;;
        3) fail2ban-client status ;;
        4) iptables -L -n --line-numbers ;;
        q|Q) return ;;
        *) echo "Invalid option." ;;
    esac

    pause
}

# === Main Menu ===

main_menu() {
    check_root
    while true; do
        clear
        echo "========= Fail2Ban Manager ========="
        echo "1) Install Fail2Ban SSH protection"
        echo "2) Remove Fail2Ban and all configs"
        echo "3) Monitor/Report Fail2Ban activity"
        echo "q) Quit"
        echo "===================================="
        read -rp "Choose an option: " choice

        case "$choice" in
            1) install_fail2ban; pause ;;
            2) remove_fail2ban; pause ;;
            3) monitor_fail2ban ;;
            q|Q) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice."; pause ;;
        esac
    done
}

main_menu
