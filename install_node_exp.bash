#!/bin/bash

# -------------------------------
# Node Exporter Auto Installer
# -------------------------------
# OS: Ubuntu / Debian
# -------------------------------

LOG_FILE="/var/log/node_exporter_install.log"
DEFAULT_VERSION="1.9.1"

# --- Colors ---
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

log() {
    echo -e "${BLUE}[INFO]${RESET} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "${RED}[ERROR]${RESET} $1" | tee -a "$LOG_FILE"
    exit 1
}

# --- Ensure script is run as root ---
if [ "$EUID" -ne 0 ]; then
    error_exit "Please run as root."
fi

log "Starting Node Exporter installation..."

# --- Step 1: Install prerequisites ---
log "Installing dependencies..."
apt update -y && apt install -y wget curl tar || error_exit "Failed to install required packages."

# --- Step 2: Create dedicated user ---
if id "node_exporter" &>/dev/null; then
    warn "User 'node_exporter' already exists. Skipping user creation."
else
    useradd --no-create-home --shell /bin/false node_exporter || error_exit "Failed to create user."
    log "User 'node_exporter' created."
fi

# --- Step 3: Fetch latest release version ---
log "Fetching latest Node Exporter version from GitHub..."

NODE_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f 4)

if [[ -z "$NODE_VERSION" ]]; then
    warn "Could not fetch latest version. Falling back to v$DEFAULT_VERSION"
    NODE_VERSION="v$DEFAULT_VERSION"
fi

NODE_VERSION_STRIPPED="${NODE_VERSION#v}"
TAR_FILE="node_exporter-${NODE_VERSION_STRIPPED}.linux-amd64.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/${NODE_VERSION}/${TAR_FILE}"
EXTRACT_DIR="node_exporter-${NODE_VERSION_STRIPPED}.linux-amd64"

cd /tmp || error_exit "Failed to change to /tmp directory."

# --- Step 4: Download and extract ---
log "Downloading Node Exporter $NODE_VERSION ..."
wget -q --show-progress "$DOWNLOAD_URL" || error_exit "Download failed."

log "Extracting $TAR_FILE..."
tar -xf "$TAR_FILE" || error_exit "Extraction failed."

# --- Step 5: Install binary ---
log "Installing Node Exporter binary..."
cp "${EXTRACT_DIR}/node_exporter" /usr/local/bin/ || error_exit "Failed to move binary."
chown node_exporter:node_exporter /usr/local/bin/node_exporter || error_exit "Failed to set permissions."

# --- Step 6: Create systemd service ---
log "Creating systemd service..."
tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# --- Step 7: Start service ---
log "Enabling and starting node_exporter service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now node_exporter || error_exit "Failed to start node_exporter service."

# --- Step 8: Verify ---
systemctl is-active --quiet node_exporter
if [ $? -eq 0 ]; then
    IP=$(hostname -I | awk '{print $1}')
    log "✅ Node Exporter installed and running successfully!"
    echo -e "${GREEN}👉 Metrics available at: http://$IP:9100/metrics${RESET}"
else
    error_exit "node_exporter service is not active."
fi

# --- Step 9: Clean up ---
log "Cleaning up temporary files..."
rm -rf "/tmp/$TAR_FILE" "/tmp/$EXTRACT_DIR"

log "Installation complete. Log saved to $LOG_FILE"
