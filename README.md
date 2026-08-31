# TG WS Proxy (Go) для Armbian / Orange Pi

Это адаптированная версия менеджера [tg-ws-proxy-go](https://github.com/d0mhate/-tg-ws-proxy-Manager-go) для систем на базе Armbian (Debian/Ubuntu), таких как ваш **Orange Pi Zero 2W**.

Вместо OpenWrt-скриптов используется **systemd** для автозапуска, а управление осуществляется через простые команды.

## Особенности

*   **Один бинарный файл**: Не требует Python или других зависимостей.
*   **Лёгкость**: Исполняемый файл весит около 5-7 МБ.
*   **Автозапуск**: Встроенная поддержка systemd.
*   **Поддержка архитектур**: Автоматически определяет arm64, armv7, amd64 и другие.

## Быстрая установка

Подключитесь к вашему Orange Pi по SSH и выполните:

```bash
wget -O tg-ws-proxy-armbian.sh https://raw.githubusercontent.com/san4jkee/tg-ws-proxy-go-systemd/main/tg-ws-proxy-armbian.sh
chmod +x tg-ws-proxy-armbian.sh
sudo ./tg-ws-proxy-armbian.sh install
sudo ./tg-ws-proxy-armbian.sh enable
```

**Важно:** Команды `install` и `enable` нужно выполнять **по отдельности**:

1. `install` — скачивает и устанавливает бинарник.
2. `enable` — создаёт systemd-сервис и включает автозапуск.

## Управление прокси

Все команды нужно выполнять с `sudo`:

| Команда ↕▾ | Описание ↕▾ |
|---|---|
| −`sudo ./tg-ws-proxy-armbian.sh install` | Скачать и установить последнюю версию бинарника |
| `sudo ./tg-ws-proxy-armbian.sh update` | Обновить бинарник до последней версии |
| `sudo ./tg-ws-proxy-armbian.sh start` | Запустить прокси-сервис |
| `sudo ./tg-ws-proxy-armbian.sh stop` | Остановить прокси-сервис |
| `sudo ./tg-ws-proxy-armbian.sh restart` | Перезапустить прокси-сервис |
| `sudo ./tg-ws-proxy-armbian.sh status` | Показать статус и логи сервиса |
| `sudo ./tg-ws-proxy-armbian.sh enable` | Включить автозапуск при загрузке системы |
| `sudo ./tg-ws-proxy-armbian.sh disable` | Отключить автозапуск |
| `sudo ./tg-ws-proxy-armbian.sh remove` | **Полностью удалить** прокси и все его файлы |
⚙

**Альтернатива:** после установки можно управлять прокси напрямую через systemd:

```
sudo systemctl start tg-ws-proxy
sudo systemctl stop tg-ws-proxy
sudo systemctl restart tg-ws-proxy
sudo systemctl status tg-ws-proxy
sudo journalctl -u tg-ws-proxy -f  # просмотр логов
```

### Пример полной настройки

```
# 1. Установка бинарника
sudo ./tg-ws-proxy-armbian.sh install

# 2. Создание сервиса и автозапуск
sudo ./tg-ws-proxy-armbian.sh enable

# 3. Проверка статуса
sudo ./tg-ws-proxy-armbian.sh status

# 4. Если нужно остановить
sudo ./tg-ws-proxy-armbian.sh stop
```

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
sudo ./tg-ws-proxy-armbian.sh restart
```

### SOCKS5

В настройках Telegram (или другого клиента) укажите:

| Параметр | Значение |
|---|---|
| Тип | `SOCKS5` |
| Хост | IP-адрес вашего Orange Pi в локальной сети |
| Порт | `1080` |

### MTProto

Если вы включили режим MTProto, после запуска прокси вы увидите ссылку для подключения в логах:

```
sudo journalctl -u tg-ws-proxy -f
```

Или сгенерируйте ссылку вручную:

```
tg://proxy?server=ВАШ_IP&port=1080&secret=ВАШ_СЕКРЕТ
```

### Cloudflare-прокси

Включите Cloudflare-маршрутизацию, добавив параметры в `ExecStart`:

```
ExecStart=/usr/local/bin/tg-ws-proxy --mode socks5 --host 0.0.0.0 --port 1080 --cf-proxy --cf-domain ваш_домен.com
```

## Решение проблем

### 1. Прокси не запускается

Проверьте логи:

```
sudo journalctl -u tg-ws-proxy -xe
```

Убедитесь, что порт 1080 свободен:

```
sudo ss -tulpn | grep 1080
```

### 2. Не удаётся скачать бинарник

- Проверьте интернет-соединение на Orange Pi.
- Возможно, устарел URL. Проверьте последние релизы на [GitHub](https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases).

### 3. Ошибка `./tg-ws-proxy-armbian.sh: строка 8: синтаксическая ошибка`

Вы скачали HTML-страницу вместо скрипта. Убедитесь, что используете **сырую** (raw) ссылку:

```
wget https://raw.githubusercontent.com/san4jkee/tg-ws-proxy-go-systemd/main/tg-ws-proxy-armbian.sh
```

### 4. Хочу использовать другие параметры запуска

Отредактируйте файл сервиса, как описано в разделе "Настройка", затем перезапустите:

```
sudo systemctl daemon-reload
sudo ./tg-ws-proxy-armbian.sh restart
```

### 5. После `install` сервис не создался

Это нормально. Выполните:

```
sudo ./tg-ws-proxy-armbian.sh enable
```

## Удаление

Полное удаление прокси:

```
sudo ./tg-ws-proxy-armbian.sh remove
```

## Лицензия

MIT License. См. файл LICENSE.

## Благодарности

Оригинальный проект: [d0mhate/-tg-ws-proxy-Manager-go](https://github.com/d0mhate/-tg-ws-proxy-Manager-go)
