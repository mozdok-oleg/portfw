#!/usr/bin/env bash
set -euo pipefail

RULES_DB="${RULES_DB:-/etc/portfw/rules.db}"

add_rule_iptable() {
  local proto="$1" in_if="$2" out_if="$3" src_ip="$4" dst_ip="$5" in_port="$6" dst_port="$7"
  iptables -t nat -A PREROUTING -i "$in_if" -p "$proto" --dport "$in_port" -j DNAT --to-destination "${dst_ip}:${dst_port}"
  iptables -A FORWARD -i "$in_if" -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -i "$out_if" -o "$in_if" -p "$proto" -s "$dst_ip" --sport "$dst_port" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  if [ -n "$src_ip" ]; then
    iptables -t nat -A POSTROUTING -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip"
  else
    iptables -t nat -A POSTROUTING -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE
  fi
}

[ -f "$RULES_DB" ] || exit 0

while IFS='|' read -r id ts in_if out_if src_ip dst_ip in_port dst_port mode; do
  [ -n "${id:-}" ] || continue
  case "$mode" in
    tcp) add_rule_iptable tcp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port" ;;
    udp) add_rule_iptable udp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port" ;;
    both)
      add_rule_iptable tcp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port"
      add_rule_iptable udp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port"
      ;;
  esac
done < "$RULES_DB"
