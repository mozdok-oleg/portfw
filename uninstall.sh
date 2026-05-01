#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root"
  exit 1
fi

echo "=== Деинсталляция Port Forward Manager ==="
echo ""

# Остановить и отключить сервис
if systemctl is-active --quiet portfw.service; then
  echo "Останавливаю сервис portfw.service..."
  systemctl stop portfw.service
fi

if systemctl is-enabled --quiet portfw.service 2>/dev/null; then
  echo "Отключаю автозапуск portfw.service..."
  systemctl disable portfw.service
fi

# Удалить все правила из iptables
echo "Удаляю правила из iptables..."
if [ -f /etc/portfw/rules.db ]; then
  while IFS='|' read -r id ts in_if out_if src_ip dst_ip in_port dst_port mode; do
    [ -n "${id:-}" ] || continue
    
    for proto in tcp udp; do
      [ "$mode" = "both" ] || [ "$mode" = "$proto" ] || continue
      
      # Удалить DNAT
      iptables -t nat -D PREROUTING -i "$in_if" -p "$proto" --dport "$in_port" -j DNAT --to-destination "${dst_ip}:${dst_port}" 2>/dev/null || true
      
      # Удалить FORWARD правила
      iptables -D FORWARD -i "$in_if" -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      iptables -D FORWARD -i "$out_if" -o "$in_if" -p "$proto" -s "$dst_ip" --sport "$dst_port" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      
      # Удалить SNAT/MASQUERADE
      if [ -n "$src_ip" ]; then
        iptables -t nat -D POSTROUTING -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null || true
      else
        iptables -t nat -D POSTROUTING -o "$out_if" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE 2>/dev/null || true
      fi
    done
  done < /etc/portfw/rules.db
fi

# Сохранить очищенные правила
if command -v netfilter-persistent >/dev/null 2>&1; then
  echo "Сохраняю очищенные правила iptables..."
  netfilter-persistent save >/dev/null 2>&1 || true
fi

# Удалить файлы
echo "Удаляю файлы..."
rm -f /usr/local/bin/portfw.sh
rm -f /usr/local/bin/portfw-restore.sh
rm -f /etc/systemd/system/portfw.service

# Удалить конфигурацию (опционально)
read -p "Удалить конфигурацию и базу правил из /etc/portfw? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[YyДд]$ ]]; then
  echo "Удаляю /etc/portfw..."
  rm -rf /etc/portfw
else
  echo "Конфигурация сохранена в /etc/portfw"
fi

# Перезагрузить systemd
echo "Перезагружаю systemd..."
systemctl daemon-reload

# Отключить IP forwarding (опционально)
read -p "Отключить IP forwarding в системе? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[YyДд]$ ]]; then
  echo "Отключаю IP forwarding..."
  sysctl -w net.ipv4.ip_forward=0 >/dev/null
  sed -i '/^net.ipv4.ip_forward=1/d' /etc/sysctl.conf 2>/dev/null || true
else
  echo "IP forwarding оставлен включённым"
fi

echo ""
echo "=== Деинсталляция завершена ==="
echo ""
echo "Удалённые компоненты:"
echo "  - Сервис portfw.service"
echo "  - Скрипты в /usr/local/bin/"
echo "  - Правила iptables"
echo ""
echo "Если вы сохранили конфигурацию, она находится в /etc/portfw"
