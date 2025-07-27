#!/bin/bash

# Fail2Ban Installer & SSH Protector for CentOS/RHEL 7

set -e

EPEL_RPM_TMP="/tmp/epel-release-7.noarch.rpm"
EPEL_PRIMARY="https://mirrors.aliyun.com/epel/epel-release-latest-7.noarch.rpm"
EPEL_FALLBACK="http://mirror.centos.org/centos/7/extras/x86_64/Packages/epel-release-7-13.noarch.rpm"

install_epel() {
  echo "[INFO] Attempting to download EPEL repository..."

  curl -Lo "$EPEL_RPM_TMP" "$EPEL_PRIMARY" || {
    echo "[WARN] Primary EPEL download failed, trying fallback..."
    curl -Lo "$EPEL_RPM_TMP" "$EPEL_FALLBACK" || {
      echo "[ERROR] Both EPEL URLs failed."
      exit 1
    }
  }

  # Validate if it's a real RPM
  if file "$EPEL_RPM_TMP" | grep -qv "RPM"; then
    echo "[ERROR] Downloaded file is not a valid RPM. Aborting."
    rm -f "$EPEL_RPM_TMP"
    exit 1
  fi

  echo "[INFO] Installing EPEL from $EPEL_RPM_TMP..."
  yum install -y "$EPEL_RPM_TMP"
}

install_fail2ban() {
  echo "[INFO] Installing Fail2Ban..."
  yum install -y fail2ban

  echo "[INFO] Enabling and starting Fail2Ban..."
  systemctl enable fail2ban
  systemctl start fail2ban
}

configure_ssh_jail() {
  echo "[INFO] Configuring SSH jail for Fail2Ban..."
  cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 3
findtime = 600
bantime = 3600
EOF

  systemctl restart fail2ban
  echo "[INFO] Fail2Ban SSH jail has been configured and restarted."
}

# ==== MAIN MENU ====

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
    1)
      install_epel
      install_fail2ban
      configure_ssh_jail
      echo "[DONE] Fail2Ban is installed and protecting SSH."
      read -rp "Press Enter to return to menu..."
      ;;
    2)
      echo "[INFO] Removing Fail2Ban..."
      systemctl stop fail2ban || true
      yum remove -y fail2ban
      rm -f /etc/fail2ban/jail.local
      echo "[DONE] Fail2Ban removed."
      read -rp "Press Enter to return to menu..."
      ;;
    3)
      echo "========= Fail2Ban Monitor ========="
      echo "1) View live SSH ban logs"
      echo "2) View SSH jail status"
      echo "3) View all jail summary"
      echo "4) View firewall ban rules (iptables)"
      echo "q) Back to main menu"
      echo "===================================="
      read -rp "Choose an option: " mon
      case "$mon" in
        1) journalctl -u fail2ban -f ;;
        2) fail2ban-client status sshd ;;
        3) fail2ban-client status ;;
        4) iptables -L -n --line-numbers ;;
        q|Q) continue ;;
        *) echo "Invalid option."; sleep 1 ;;
      esac
      read -rp "Press Enter to return to monitor..."
      ;;
    q|Q)
      echo "Goodbye!"
      exit 0
      ;;
    *)
      echo "Invalid option."
      sleep 1
      ;;
  esac
done
