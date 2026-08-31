# TG WS Proxy (Go) для Armbian / Orange Pi

Это адаптированная версия менеджера [tg-ws-proxy-go](https://github.com/d0mhate/-tg-ws-proxy-Manager-go) для систем на базе Armbian (Debian/Ubuntu), таких как ваш **Orange Pi Zero 2W**.

Вместо OpenWrt-скриптов используется **systemd** для автозапуска, а управление осуществляется через простые CLI-команды.

## Особенности

*   **Один бинарный файл**: Не требует Python или других зависимостей.
*   **Лёгкость**: Исполняемый файл весит около 5-7 МБ.
*   **Управление**: Простые команды `tgm start`, `stop`, `status`, `enable`, `disable`.
*   **Автозапуск**: Встроенная поддержка systemd.
*   **Поддержка архитектур**: Автоматически определяет arm64, armv7, amd64 и другие.

## Быстрая установка

Подключитесь к вашему Orange Pi по SSH и выполните:

```bash
wget -O tg-ws-proxy-armbian.sh https://github.com/san4jkee/tg-ws-proxy-go-systemd/blob/main/tg-ws-proxy-armbian.sh
chmod +x tg-ws-proxy-armbian.sh
sudo ./tg-ws-proxy-armbian.sh install
```

После установки будет доступна команда `tgm`.

## Управление прокси

Все команды нужно выполнять с `sudo` (кроме `status`):

| Команда | Описание |
|---|---|
| `sudo tgm install` | Скачать и установить последнюю версию бинарника |
| `sudo tgm update` | Обновить бинарник до последней версии |
| `sudo tgm start` | Запустить прокси-сервис |
| `sudo tgm stop` | Остановить прокси-сервис |
| `sudo tgm restart` | Перезапустить прокси-сервис |
| `tgm status` | Показать статус и логи сервиса |
| `sudo tgm enable` | Включить автозапуск при загрузке системы |
| `sudo tgm disable` | Отключить автозапуск |
| `sudo tgm remove` | **Полностью удалить** прокси и все его файлы |

## Настройка

По умолчанию прокси запускается в режиме **SOCKS5** на порту **1080** и слушает все интерфейсы (`0.0.0.0`).

**Чтобы изменить настройки** (порт, режим MTProto, включить Cloudflare), отредактируйте файл сервиса:

```
sudo nano /etc/systemd/system/tg-ws-proxy.service
```

Найдите строку `ExecStart` и измените аргументы. Например, для запуска MTProto с секретом:

```
ExecStart=/usr/local/bin/tg-ws-proxy --mode mtproto --secret ВАШ_32_СИМВОЛЬНЫЙ_HEX --host 0.0.0.0 --port 1080 --link-ip ВАШ_ПУБЛИЧНЫЙ_IP
```

После изменения настроек выполните:

```
sudo systemctl daemon-reload
sudo tgm restart
```

### SOCKS5

В настройках Telegram (или другого клиента) укажите:

- Тип: `SOCKS5`
- Хост: IP-адрес вашего Orange Pi в локальной сети
- Порт: `1080`

### MTProto

Если вы включили режим MTProto, после запуска прокси вы увидите ссылку для подключения в логах:

```
sudo journalctl -u tg-ws-proxy -f
```

Или сгенерируйте ссылку вручную:
`tg://proxy?server=ВАШ_IP&port=1080&secret=ВАШ_СЕКРЕТ`

## Решение проблем

**1. Прокси не запускается:**

- Проверьте логи: `sudo journalctl -u tg-ws-proxy -xe`
- Убедитесь, что порт 1080 свободен: `sudo ss -tulpn | grep 1080`

**2. Не удаётся скачать бинарник:**

- Проверьте интернет-соединение на Orange Pi.
- Возможно, устарел URL. Проверьте последние релизы на [GitHub](https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases).

**3. Хочу использовать другие параметры запуска:**

- Отредактируйте файл сервиса, как описано в разделе "Настройка".

