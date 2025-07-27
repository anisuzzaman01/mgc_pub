#!/bin/bash

# Fail2Ban Interactive Installer and Manager for CentOS/RHEL 7, 8, 9

install_epel() {
    echo "[INFO] Detecting OS version..."
    OS_RELEASE=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)

    case "$OS_RELEASE" in
        7)
            EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
            ;;
        8)
            EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
            ;;
        9)
            EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
            ;;
        *)
            echo "[ERROR] Unsupported OS version: $OS_RELEASE"
            return 1
            ;;
    esac

    echo "[INFO] Downloading EPEL from $EPEL_URL ..."
    curl -Ls -o /tmp/epel-release.rpm "$EPEL_URL"

    echo "[INFO] Validating downloaded RPM..."
    if ! file /tmp/epel-release.rpm | grep -q "RPM"; then
        echo "[ERROR] Downloaded file is not a valid RPM."
        return 1
    fi

    echo "[INFO] Installing EPEL..."
    yum install -y /tmp/epel-release.rpm || {
        echo "[ERROR] Failed to install EPEL."
        return 1
    }

    rm -f /tmp/epel-release.rpm
    return 0
}

install_fail2ban() {
    echo "[INFO] Installing Fail2Ban..."
    yum install -y fail2ban || {
        echo "[ERROR] Fail2Ban installation failed."
        return 1
    }

    echo "[INFO] Enabling and starting Fail2Ban..."
    systemctl enable fail2ban
    systemctl start fail2ban

    echo "[INFO] Creating jail.local for SSH protection..."
    cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 5
bantime = 600
findtime = 600
EOF

    systemctl restart fail2ban
    echo "[SUCCESS] Fail2Ban SSH protection is now active."
}

remove_fail2ban() {
    echo "[INFO] Removing Fail2Ban and configuration..."
    systemctl stop fail2ban
    yum remove -y fail2ban
    rm -f /etc/fail2ban/jail.local
    echo "[INFO] Fail2Ban removed successfully."
}

monitor_menu() {
    while true; do
        echo -e "\n========= Fail2Ban Monitor ========="
        echo "1) View live SSH ban logs"
        echo "2) View SSH jail status"
        echo "3) View all jail summary"
        echo "4) View firewall ban rules (iptables/nftables)"
        echo "q) Back to main menu"
        echo "===================================="
        read -rp "Choose an option: " sub_choice

        case "$sub_choice" in
            1) journalctl -u fail2ban -f ;;
            2) fail2ban-client status sshd ;;
            3) fail2ban-client status ;;
            4) iptables -L -n --line-numbers | grep -i "fail2ban" || nft list ruleset | grep -i "fail2ban" ;;
            q) break ;;
            *) echo "Invalid option. Try again." ;;
        esac
    done
}

main_menu() {
    while true; do
        echo -e "\n========= Fail2Ban Manager ========="
        echo "1) Install Fail2Ban SSH protection"
        echo "2) Remove Fail2Ban and all configs"
        echo "3) Monitor/Report Fail2Ban activity"
        echo "q) Quit"
        echo "===================================="
        read -rp "Choose an option: " choice

        case "$choice" in
            1)
                install_epel && install_fail2ban
                ;;
            2)
                remove_fail2ban
                ;;
            3)
                monitor_menu
                ;;
            q)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid option. Try again."
                ;;
        esac
    done
}

# Run the main menu
main_menu
