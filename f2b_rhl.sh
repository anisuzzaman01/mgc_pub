#!/bin/bash

# Fail2Ban Manager with OS detection and EPEL fix
set -e

EPEL_URL_C7="https://mirrors.aliyun.com/epel/epel-release-latest-7.noarch.rpm"
EPEL_URL_C8="https://mirrors.aliyun.com/epel/epel-release-latest-8.noarch.rpm"
EPEL_URL_C9="https://mirrors.aliyun.com/epel/epel-release-latest-9.noarch.rpm"

function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION_ID=${VERSION_ID%%.*}
    elif [ -f /etc/centos-release ]; then
        OS_ID="centos"
        OS_VERSION_ID=$(rpm -q --qf "%{VERSION}" centos-release)
    else
        echo "[ERROR] Unsupported OS."
        exit 1
    fi
}

function install_epel() {
    echo "[INFO] Installing EPEL repository..."

    local epel_url=""
    case "$OS_VERSION_ID" in
        7) epel_url=$EPEL_URL_C7 ;;
        8) epel_url=$EPEL_URL_C8 ;;
        9) epel_url=$EPEL_URL_C9 ;;
        *) echo "[ERROR] Unsupported RHEL/CentOS version"; exit 1 ;;
    esac

    curl -Lo /tmp/epel-release.rpm "$epel_url"
    
    # Validate RPM
    if ! file /tmp/epel-release.rpm | grep -q 'RPM'; then
        echo "[ERROR] Downloaded file is not a valid RPM"
        rm -f /tmp/epel-release.rpm
        exit 1
    fi

    yum install -y /tmp/epel-release.rpm
    rm -f /tmp/epel-release.rpm
}

function install_fail2ban() {
    detect_os

    echo "[INFO] Installing Fail2Ban on $OS_ID $OS_VERSION_ID..."

    if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
        install_epel
        yum install -y fail2ban
    elif [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
        apt update && apt install -y fail2ban
    else
        echo "[ERROR] Unsupported OS: $OS_ID"
        exit 1
    fi

    systemctl enable fail2ban
    systemctl start fail2ban

    cat >/etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

    echo "[INFO] Fail2Ban installed and configured."
}

function remove_fail2ban() {
    detect_os

    echo "[INFO] Removing Fail2Ban..."

    if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
        yum remove -y fail2ban
    elif [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
        apt remove -y fail2ban
    fi

    rm -rf /etc/fail2ban
    echo "[INFO] Fail2Ban and configs removed."
}

function monitor_fail2ban() {
    echo "========= Fail2Ban Monitor ========="
    echo "1) View live SSH ban logs"
    echo "2) View SSH jail status"
    echo "3) View all jail summary"
    echo "4) View firewall ban rules (iptables/nftables)"
    echo "q) Back to main menu"
    echo "===================================="
    read -rp "Choose an option: " mon_choice

    case $mon_choice in
        1) journalctl -u fail2ban -f ;;
        2) fail2ban-client status sshd ;;
        3) fail2ban-client status ;;
        4) iptables -L -n --line-numbers ;;
        q) return ;;
        *) echo "[WARN] Invalid option" ;;
    esac
}

# Main Menu
while true; do
    echo "========= Fail2Ban Manager ========="
    echo "1) Install Fail2Ban SSH protection"
    echo "2) Remove Fail2Ban and all configs"
    echo "3) Monitor/Report Fail2Ban activity"
    echo "q) Quit"
    echo "===================================="
    read -rp "Choose an option: " choice

    case $choice in
        1) install_fail2ban ;;
        2) remove_fail2ban ;;
        3) monitor_fail2ban ;;
        q) exit 0 ;;
        *) echo "[WARN] Invalid selection" ;;
    esac
done
