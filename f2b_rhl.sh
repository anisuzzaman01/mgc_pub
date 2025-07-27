#!/bin/bash

# Fail2Ban Interactive Installer and Manager for CentOS/RHEL
# Supports RHEL/CentOS 7, 8, 9

install_epel() {
    echo "[INFO] Detecting OS version..."
    OS_VERSION=$(rpm -q --qf "%{VERSION}" centos-release 2>/dev/null || rpm -q --qf "%{VERSION}" redhat-release 2>/dev/null)

    case "$OS_VERSION" in
        7)
            EPEL_URL="http://mirror.centos.org/centos/7/extras/x86_64/Packages/epel-release-7-13.noarch.rpm"
            ;;
        8)
            EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
            ;;
        9)
            EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
            ;;
        *)
            echo "[ERROR] Unsupported OS version: $OS_VERSION"
            return 1
            ;;
    esac

    echo "[INFO] Downloading EPEL repository for CentOS/RHEL $OS_VERSION..."
    curl -L -o /tmp/epel-release.rpm "$EPEL_URL"

    echo "[INFO] Validating downloaded RPM..."
    if ! rpm -K /tmp/epel-release.rpm &>/dev/null; then
        echo "[ERROR] Downloaded file is not a valid RPM or corrupted"
        return 1
    fi

    echo "[INFO] Installing EPEL..."
    yum install -y /tmp/epel-release.rpm || { echo "[ERROR] Failed to install EPEL."; return 1; }
    rm -f /tmp/epel-release.rpm
}


install_fail2ban() {
    echo "[INFO] Installing Fail2Ban..."
    yum install -y fail2ban || { echo "[ERROR] Fail2Ban installation failed."; return 1; }

    echo "[INFO] Enabling and starting Fail2Ban..."
    systemctl enable fail2ban
    systemctl start fail2ban

    echo "[INFO] Configuring jail.local for SSH..."
    cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 5
bantime = 3600
findtime = 600
EOF

    echo "[INFO] Restarting Fail2Ban..."
    systemctl restart fail2ban
    echo "[SUCCESS] Fail2Ban SSH protection installed and configured."
}

remove_fail2ban() {
    echo "[INFO] Stopping and removing Fail2Ban..."
    systemctl stop fail2ban
    yum remove -y fail2ban
    rm -f /etc/fail2ban/jail.local
    echo "[SUCCESS] Fail2Ban and configs removed."
}

monitor_fail2ban() {
    echo "========= Fail2Ban Monitor ========="
    echo "1) View live SSH ban logs"
    echo "2) View SSH jail status"
    echo "3) View all jail summary"
    echo "4) View firewall ban rules (iptables/nftables)"
    echo "q) Back to main menu"
    echo "===================================="
    read -rp "Choose an option: " monopt

    case "$monopt" in
        1) journalctl -u fail2ban -f ;;
        2) fail2ban-client status sshd ;;
        3) fail2ban-client status ;;
        4) iptables -L -n --line-numbers || nft list ruleset ;;
        q|Q) return ;;
        *) echo "[WARN] Invalid option." ;;
    esac
}

main_menu() {
    while true; do
        echo "========= Fail2Ban Manager ========="
        echo "1) Install Fail2Ban SSH protection"
        echo "2) Remove Fail2Ban and all configs"
        echo "3) Monitor/Report Fail2Ban activity"
        echo "q) Quit"
        echo "===================================="
        read -rp "Choose an option: " option

        case "$option" in
            1)
                install_epel && install_fail2ban
                ;;
            2)
                remove_fail2ban
                ;;
            3)
                monitor_fail2ban
                ;;
            q|Q)
                echo "[INFO] Exiting. Goodbye."
                exit 0
                ;;
            *)
                echo "[WARN] Invalid option. Try again."
                ;;
        esac
    done
}

main_menu
