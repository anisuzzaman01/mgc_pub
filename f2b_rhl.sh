#!/bin/bash

# ========== Fail2Ban Manager for RHEL/CentOS ==========
clear
set -euo pipefail

# ========== Colors ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# ========== Logging Helpers ==========
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_done()  { echo -e "${GREEN}[✔]${NC} $*"; }

# ========== Custom SSHD Jail Block ==========
CUSTOM_SSHD_BLOCK="[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 3
findtime = 600
bantime = 3600
backend = systemd
action = iptables[name=SSH, port=ssh, protocol=tcp]"

# ========== Root & Binary Check ==========
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

check_binary() {
    command -v "$1" >/dev/null 2>&1 || { log_error "'$1' is required but not installed."; exit 1; }
}

# ========== Detect package manager ==========
get_pkg_mgr() {
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    else
        log_error "No supported package manager found (yum or dnf)."
        exit 1
    fi
}

# ========== EPEL installer with manual fallback ==========
install_epel() {
    if rpm -q epel-release &>/dev/null; then
        log_info "EPEL repository already installed."
        return
    fi

    log_info "Installing EPEL repository manually..."
    local epel_rpm="/tmp/epel-release-latest-7.noarch.rpm"

    # Remove old file if exists
    [[ -f "$epel_rpm" ]] && rm -f "$epel_rpm"

    # Try download with curl or wget
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$epel_rpm" https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || {
            log_error "curl failed to download EPEL RPM."
            exit 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$epel_rpm" https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || {
            log_error "wget failed to download EPEL RPM."
            exit 1
        }
    else
        log_error "Neither curl nor wget is installed."
        exit 1
    fi

    # Check if file exists and is not empty
    if [[ ! -s "$epel_rpm" ]]; then
        log_error "EPEL RPM file not found or empty: $epel_rpm"
        exit 1
    fi

    yum install -y "$epel_rpm" || {
        log_error "Failed to install EPEL repository."
        exit 1
    }

    # Clean up downloaded RPM file
    rm -f "$epel_rpm"
}

# ========== Install Fail2Ban ==========
install_fail2ban() {
    PKG_MGR=$(get_pkg_mgr)

    log_info "Installing EPEL and Fail2Ban..."
    install_epel

    $PKG_MGR install -y fail2ban

    systemctl enable fail2ban
    systemctl start fail2ban

    log_info "Backing up and modifying jail.local..."
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || true

    awk -v block="$CUSTOM_SSHD_BLOCK" '
        BEGIN {skip=0}
        /^\[sshd\]/ {print block; skip=1; next}
        skip && /^\[.*\]/ {skip=0}
        !skip {print}
    ' /etc/fail2ban/jail.local > /tmp/jail.local && mv /tmp/jail.local /etc/fail2ban/jail.local

    systemctl restart fail2ban
    log_done "Fail2Ban installed and SSH protection configured."
}

# ========== Remove Fail2Ban ==========
remove_fail2ban() {
    read -rp "$(echo -e "${YELLOW}Are you sure you want to remove Fail2Ban? [y/N]: ${NC}")" confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        PKG_MGR=$(get_pkg_mgr)

        log_info "Stopping Fail2Ban..."
        systemctl stop fail2ban

        $PKG_MGR remove -y fail2ban

        log_info "Removing Fail2Ban configs and logs..."
        rm -rf /etc/fail2ban /var/log/fail2ban.log /var/lib/fail2ban /var/run/fail2ban

        log_done "Fail2Ban completely removed."
    else
        log_info "Uninstall aborted."
    fi
}

# ========== Monitor Fail2Ban ==========
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
                log_info "Press Ctrl+C to stop logs."
                tail -f /var/log/fail2ban.log
                ;;
            2)
                fail2ban-client status sshd || log_warn "SSH jail not found."
                ;;
            3)
                fail2ban-client status || log_warn "Fail2Ban status not available."
                ;;
            4)
                if command -v nft >/dev/null && nft list ruleset 2>/dev/null | grep -q fail2ban; then
                    echo -e "${YELLOW}[+] nftables rules detected:${NC}"
                    nft list ruleset | grep -A10 fail2ban
                elif iptables -L -n | grep -q "f2b-"; then
                    echo -e "${YELLOW}[+] iptables rules detected:${NC}"
                    iptables -L -n --line-numbers | grep "f2b-"
                    for chain in $(iptables -S | grep -o 'f2b-[a-zA-Z0-9_-]*' | sort -u); do
                        echo -e "\n${BLUE}Chain: $chain${NC}"
                        iptables -L "$chain" -n --line-numbers
                    done
                else
                    log_warn "No ban rules found."
                fi
                ;;
            q|Q)
                break
                ;;
            *)
                log_warn "Invalid option."
                ;;
        esac
    done
}

# ========== Main
