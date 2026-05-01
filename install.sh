#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/portfw"
RULES_DIR="/etc/portfw"
RULES_DB="$RULES_DIR/rules.db"
IPTABLES_SAVE_FILE="/etc/iptables/rules.v4"

mkdir -p "$RULES_DIR"
touch "$RULES_DB"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y whiptail iptables iptables-persistent

if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null

install -m 755 "$APP_DIR/portfw.sh" /usr/local/bin/portfw.sh
install -m 644 "$APP_DIR/portfw.service" /etc/systemd/system/portfw.service
install -m 644 "$APP_DIR/portfw.env" /etc/portfw/portfw.env

iptables-save > "$IPTABLES_SAVE_FILE"
netfilter-persistent save >/dev/null 2>&1 || true