#!/bin/bash

set -e

# === System Detection ===
OS=""
VERSION_ID=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "[ERROR] Cannot detect OS."
    exit 1
fi

# === Logging ===
log() {
    echo -e "[INFO] $1"
}

err() {
    echo -e "[ERROR] $1"
    exit 1
}

# === EPEL Setup ===
install_epel() {
    log "Installing EPEL repository..."

    case "$VERSION_ID" in
        7)
            EPEL_RPM="epel-release-7-13.noarch.rpm"
            EPEL_URL="https://mirrors.aliyun.com/epel/$EPEL_RPM"
            ;;
        8)
            EPEL_RPM="epel-release-latest-8.noarch.rpm"
            EPEL_URL="https://mirrors.aliyun.com/epel/$EPEL_RPM"
            ;;
        9)
            EPEL_RPM="epel-release-latest-9.noarch.rpm"
            EPEL_URL="https://mirrors.aliyun.com/epel/$EPEL_RPM"
            ;;
        *)
            err "Unsupported version: $VERSION_ID"
            ;;
    esac

    curl -Lo /tmp/$EPEL_RPM "$EPEL_URL" || err "Failed to download EPEL from $EPEL_URL"
    
    file_type=$(file /tmp/$EPEL_RPM)
    echo "$file_type" | grep -q "RPM" || err "Downloaded file is not a valid RPM"

    yum install -y /tmp/$EPEL_RPM || err "YUM failed to install EPEL"
}

# === Fail2Ban Installation ===
install_fail2ban() {
    log "Installing Fail2Ban..."
    yum install -y fail2ban || err "Fail2Ban installation failed"
    systemctl enable fail2ban
    systemctl start fail2ban
}

# === SSH Jail Configuration ===
configure_ssh_jail() {
    log "Configuring Fail2Ban SSH jail..."
    JAIL_LOCAL="/etc/fail2ban/jail.local"
    cp /etc/fail2ban/jail.conf "$JAIL_LOCAL"

    sed -i '/^\[sshd\]/,/^\[.*\]/d' "$JAIL_LOCAL"

    cat <<EOF >> "$JAIL_LOCAL"
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
}

# === Main ===
log "Detected OS: $OS $VERSION_ID"

if [[ "$OS" =~ (centos|rhel|almalinux|rocky) ]]; then
    install_epel
    install_fail2ban
    configure_ssh_jail
    log "Fail2Ban installed and configured successfully."
else
    err "Unsupported OS: $OS"
fi
