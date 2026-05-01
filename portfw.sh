#!/usr/bin/env bash
set -euo pipefail

RULES_DB="${RULES_DB:-/etc/portfw/rules.db}"
IPTABLES_SAVE_FILE="${IPTABLES_SAVE_FILE:-/etc/iptables/rules.v4}"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "Запустите от root"; exit 1; }; }

enable_forwarding() {
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

persist_rules() {
  iptables-save > "$IPTABLES_SAVE_FILE"
  netfilter-persistent save >/dev/null 2>&1 || true
}

next_id() {
  [ -s "$RULES_DB" ] && awk -F'|' 'END{print $1+1}' "$RULES_DB" || echo 1
}

get_interfaces() {
  ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | tr '\n' ' '
}

select_interface() {
  local title="$1"
  local ifaces=($(get_interfaces))
  local menu_items=()
  local i=1
  for iface in "${ifaces[@]}"; do
    menu_items+=("$iface" "")
    ((i++))
  done
  whiptail --menu "$title" 16 60 8 "${menu_items[@]}" 3>&1 1>&2 2>&3
}

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

append_db() {
  local id="$1" in_if="$2" out_if="$3" src_ip="$4" dst_ip="$5" in_port="$6" dst_port="$7" mode="$8"
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$(date '+%F %T')" "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port" "$mode" >> "$RULES_DB"
}

add_rule_menu() {
  local in_if out_if src_ip dst_ip in_port dst_port mode id
  
  in_if=$(select_interface "Выберите входящий интерфейс:") || return
  out_if=$(select_interface "Выберите исходящий интерфейс:") || return
  src_ip=$(whiptail --inputbox "SNAT source IP (пусто = MASQUERADE):" 12 78 "" 3>&1 1>&2 2>&3) || return
  dst_ip=$(whiptail --inputbox "IP назначения:" 12 78 3>&1 1>&2 2>&3) || return
  in_port=$(whiptail --inputbox "Входящий порт:" 12 78 3>&1 1>&2 2>&3) || return
  dst_port=$(whiptail --inputbox "Порт назначения:" 12 78 3>&1 1>&2 2>&3) || return
  mode=$(whiptail --menu "Протокол:" 12 60 3 "tcp" "Только TCP" "udp" "Только UDP" "both" "TCP и UDP" 3>&1 1>&2 2>&3) || return
  
  enable_forwarding
  id="$(next_id)"
  
  case "$mode" in
    tcp) add_rule_iptable tcp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port" ;;
    udp) add_rule_iptable udp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port" ;;
    both)
      add_rule_iptable tcp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port"
      add_rule_iptable udp "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port"
      ;;
  esac
  
  append_db "$id" "$in_if" "$out_if" "$src_ip" "$dst_ip" "$in_port" "$dst_port" "$mode"
  persist_rules
  whiptail --msgbox "Правило #$id добавлено." 8 40
}

show_rules() {
  [ -s "$RULES_DB" ] || { whiptail --msgbox "Нет правил." 8 30; return; }
  local tmp; tmp="$(mktemp)"
  awk -F'|' 'BEGIN{printf "%-4s %-16s %-16s %-15s %-15s %-8s %-8s %-6s\n","ID","ВХ_ИНТ","ИСХ_ИНТ","SRC_IP","DST_IP","ВХ_ПОРТ","ИСХ_ПОРТ","ПРОТ"} {printf "%-4s %-16s %-16s %-15s %-15s %-8s %-8s %-6s\n",$1,$3,$4,$5,$6,$7,$8,$9}' "$RULES_DB" > "$tmp"
  whiptail --textbox "$tmp" 22 110
  rm -f "$tmp"
}

delete_rule() {
  [ -s "$RULES_DB" ] || { whiptail --msgbox "Нет правил." 8 30; return; }
  local del_id line
  del_id=$(whiptail --inputbox "ID правила для удаления:" 10 40 3>&1 1>&2 2>&3) || return
  line="$(awk -F'|' -v id="$del_id" '$1==id{print; exit}' "$RULES_DB")" || true
  [ -n "$line" ] || { whiptail --msgbox "ID не найден." 8 30; return; }
  IFS='|' read -r id ts in_if out_if src_ip dst_ip in_port dst_port mode <<< "$line"
  for proto in tcp udp; do
    [ "$mode" = "both" ] || [ "$mode" = "$proto" ] || continue
    iptables -t nat -D PREROUTING -i "$in_if" -p "$proto" --dport "$in_port" -j DNAT --to-destination "${dst_ip}:${dst_port}" 2>/dev/null || true
    iptables -D FORWARD -i "$in_if" -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$out_if" -o "$in_if" -p "$proto" -s "$dst_ip" --sport "$dst_port" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    if [ -n "$src_ip" ]; then
      iptables -t nat -D POSTROUTING -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null || true
    else
      iptables -t nat -D POSTROUTING -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE 2>/dev/null || true
    fi
  done
  tmp="$(mktemp)"
  awk -F'|' -v id="$del_id" '$1!=id' "$RULES_DB" > "$tmp"
  mv "$tmp" "$RULES_DB"
  persist_rules
  whiptail --msgbox "Удалено." 8 30
}

restore_all() {
  [ -s "$RULES_DB" ] || return 0
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
  persist_rules
}

main_menu() {
  while true; do
    choice=$(whiptail --title "Менеджер проброса портов" --menu "Выберите действие" 18 78 8 \
      "1" "Добавить правило" \
      "2" "Показать правила" \
      "3" "Удалить правило" \
      "4" "Восстановить все правила" \
      "5" "Сохранить конфиг" \
      "6" "Выход" 3>&1 1>&2 2>&3) || exit 0
    case "$choice" in
      1) add_rule_menu ;;
      2) show_rules ;;
      3) delete_rule ;;
      4) restore_all; whiptail --msgbox "Восстановлено." 8 30 ;;
      5) persist_rules; whiptail --msgbox "Сохранено." 8 25 ;;
      6) exit 0 ;;
    esac
  done
}

need_root
[ -f "$RULES_DB" ] || mkdir -p "$(dirname "$RULES_DB")" && touch "$RULES_DB"
main_menu
