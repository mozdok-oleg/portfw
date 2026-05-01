# Port Forward Manager

Менеджер проброса портов для Linux с текстовым меню на русском языке.

## Установка

```bash
git clone git@github.com:mozdok-oleg/portfw.git /opt/portfw
cd /opt/portfw
bash deploy.sh
```

## Использование

Запустить меню:
```bash
/usr/local/bin/portfw.sh
```

Или напрямую:
```bash
portfw.sh
```

## Деинсталляция

```bash
cd /opt/portfw
bash uninstall.sh
```

Скрипт удалит:
- Сервис systemd
- Все скрипты из /usr/local/bin/
- Правила iptables
- Опционально: конфигурацию и IP forwarding

## Возможности

- ✅ Добавление правил проброса портов через меню
- ✅ Автоматическое определение сетевых интерфейсов
- ✅ Сохранение правил в базу данных
- ✅ Автовосстановление после перезагрузки
- ✅ Поддержка TCP, UDP и обоих протоколов
- ✅ Русский интерфейс
- ✅ Полная деинсталляция

## Файлы

- `deploy.sh` — установка/обновление
- `install.sh` — установка компонентов
- `uninstall.sh` — полное удаление
- `portfw.sh` — главное меню
- `portfw-restore.sh` — восстановление правил при загрузке
- `portfw.service` — systemd сервис
- `portfw.env` — переменные окружения

## Требования

- Linux с systemd
- iptables
- whiptail
- root права
