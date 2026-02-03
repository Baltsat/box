#!/usr/bin/env bash
# Linux server hardening script
# Usage: ./script/hardening.sh [full|firewall|fail2ban|ssh]
set -euo pipefail

log() { echo "[hardening] $*"; }
die() { log "error: $*"; exit 1; }
has_cmd() { command -v "$1" &>/dev/null; }

# Check if running as root or with sudo
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        die "run with sudo: sudo ./script/hardening.sh"
    fi
}

# Configure UFW firewall
setup_firewall() {
    log "configuring UFW firewall..."

    if ! has_cmd ufw; then
        apt-get update -qq && apt-get install -y ufw
    fi

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow essential ports
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Enable firewall
    ufw --force enable
    ufw status verbose

    log "firewall configured"
}

# Configure fail2ban
setup_fail2ban() {
    log "configuring fail2ban..."

    if ! has_cmd fail2ban-server; then
        apt-get update -qq && apt-get install -y fail2ban
    fi

    # Create local config
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    fail2ban-client status

    log "fail2ban configured"
}

# Harden SSH config
setup_ssh() {
    log "hardening SSH..."

    local sshd_config="/etc/ssh/sshd_config"
    local sshd_dir="/etc/ssh/sshd_config.d"

    # Create hardening config
    mkdir -p "$sshd_dir"
    cat > "$sshd_dir/99-hardening.conf" << 'EOF'
# SSH Hardening
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowAgentForwarding yes
AllowTcpForwarding yes
EOF

    # Test config
    sshd -t && {
        systemctl reload sshd
        log "SSH hardened"
    } || {
        rm -f "$sshd_dir/99-hardening.conf"
        die "SSH config invalid, reverted"
    }
}

# Install security tools
setup_tools() {
    log "installing security tools..."

    apt-get update -qq
    apt-get install -y \
        ufw \
        fail2ban \
        unattended-upgrades \
        apt-listchanges \
        logwatch

    # Enable unattended upgrades
    dpkg-reconfigure -plow unattended-upgrades

    log "security tools installed"
}

# Full hardening
full_hardening() {
    check_sudo
    setup_tools
    setup_firewall
    setup_fail2ban
    setup_ssh
    log "full hardening complete"
}

show_help() {
    cat << EOF
Linux Server Hardening

Commands:
  full       Run all hardening steps (default)
  firewall   Configure UFW firewall only
  fail2ban   Configure fail2ban only
  ssh        Harden SSH config only
  tools      Install security tools only
  status     Show current security status

Usage:
  sudo ./script/hardening.sh full
  sudo ./script/hardening.sh firewall
  sudo ./script/hardening.sh status

Ports opened by default:
  22  - SSH
  80  - HTTP
  443 - HTTPS

To add more ports:
  sudo ufw allow 8080/tcp comment 'Custom app'
EOF
}

show_status() {
    echo "=== Firewall ==="
    has_cmd ufw && ufw status || echo "UFW not installed"
    echo ""
    echo "=== Fail2ban ==="
    has_cmd fail2ban-client && fail2ban-client status || echo "fail2ban not installed"
    echo ""
    echo "=== SSH ==="
    [[ -f /etc/ssh/sshd_config.d/99-hardening.conf ]] && echo "hardening config: active" || echo "hardening config: not found"
}

case "${1:-full}" in
    full) full_hardening ;;
    firewall) check_sudo && setup_firewall ;;
    fail2ban) check_sudo && setup_fail2ban ;;
    ssh) check_sudo && setup_ssh ;;
    tools) check_sudo && setup_tools ;;
    status) show_status ;;
    *) show_help ;;
esac
