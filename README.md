# TG WS Proxy (Go) для Armbian / Orange Pi

Это адаптированная версия менеджера [tg-ws-proxy-go](https://github.com/d0mhate/-tg-ws-proxy-Manager-go) для систем на базе Armbian (Debian/Ubuntu), таких как ваш **Orange Pi Zero 2W**.

Вместо OpenWrt-скриптов используется **systemd** для автозапуска, а управление осуществляется через простые команды.

## Особенности

*   **Один бинарный файл**: Не требует Python или других зависимостей.
*   **Лёгкость**: Исполняемый файл весит около 5-7 МБ.
*   **Автозапуск**: Встроенная поддержка systemd.
*   **Поддержка архитектур**: Автоматически определяет arm64, armv7, amd64 и другие.
*   **Поддержка Cloudflare**: Возможность использовать свой домен для обхода блокировок.
*   **Интерактивная настройка**: Скрипт сам спросит порт, секрет, IP и настройки Cloudflare.

## Быстрая установка

Подключитесь к вашему Orange Pi по SSH и выполните:

```bash
wget -O tg-ws-proxy-armbian.sh https://raw.githubusercontent.com/san4jkee/tg-ws-proxy-go-systemd/main/tg-ws-proxy-armbian.sh
chmod +x tg-ws-proxy-armbian.sh
sudo ./tg-ws-proxy-armbian.sh install
```

Скрипт задаст несколько вопросов:

1. **Режим работы** — MTProto (рекомендуется для Telegram) или SOCKS5.
2. **Порт** — по умолчанию 1443 для MTProto или 1080 для SOCKS5.
3. **Секрет** — для MTProto можно сгенерировать случайный или ввести свой (32 hex-символа).
4. **Публичный IP** — если прокси будет доступен из интернета.
5. **Cloudflare** — если у вас есть домен, подключенный к Cloudflare.
6. **Автозапуск** — включить при загрузке системы.

После установки будет доступен systemd-сервис `tg-ws-proxy.service`.

## Управление прокси

Все команды нужно выполнять с `sudo`:

| Команда ↕▾ | Описание ↕▾ |
|---|---|
| −`sudo ./tg-ws-proxy-armbian.sh install` | Интерактивная установка с настройкой |
| `sudo ./tg-ws-proxy-armbian.sh update` | Обновить бинарник (с повторной настройкой) |
| `sudo ./tg-ws-proxy-armbian.sh reconfigure` | Изменить настройки без переустановки |
| `sudo ./tg-ws-proxy-armbian.sh start` | Запустить сервис |
| `sudo ./tg-ws-proxy-armbian.sh stop` | Остановить сервис |
| `sudo ./tg-ws-proxy-armbian.sh restart` | Перезапустить сервис |
| `sudo ./tg-ws-proxy-armbian.sh status` | Показать статус и логи |
| `sudo ./tg-ws-proxy-armbian.sh enable` | Включить автозапуск (создать сервис) |
| `sudo ./tg-ws-proxy-armbian.sh disable` | Отключить автозапуск |
| `sudo ./tg-ws-proxy-armbian.sh remove` | **Полностью удалить** прокси и все файлы |
⚙

**Альтернатива:** после установки можно управлять прокси напрямую через systemd:

```
sudo systemctl start tg-ws-proxy
sudo systemctl stop tg-ws-proxy
sudo systemctl restart tg-ws-proxy
sudo systemctl status tg-ws-proxy
sudo journalctl -u tg-ws-proxy -f  # просмотр логов
```

### Пример полной установки

```
# 1. Скачиваем скрипт
wget -O tg-ws-proxy-armbian.sh https://raw.githubusercontent.com/san4jkee/tg-ws-proxy-go-systemd/main/tg-ws-proxy-armbian.sh
chmod +x tg-ws-proxy-armbian.sh

# 2. Установка с интерактивной настройкой
sudo ./tg-ws-proxy-armbian.sh install

# 3. Готово! Проверяем статус
sudo ./tg-ws-proxy-armbian.sh status
```

## Настройка вручную

Настройки сохраняются в файл `/etc/tg-ws-proxy/config.env`. Вы можете отредактировать его вручную и перезапустить сервис:

```
sudo nano /etc/tg-ws-proxy/config.env
sudo systemctl restart tg-ws-proxy
```

Или использовать команду `reconfigure`:

```
sudo ./tg-ws-proxy-armbian.sh reconfigure
```

### Пример файла конфигурации

```
PROXY_MODE="mtproto"
PORT="1443"
SECRET="ddce44acf471924b64af18cb422e6feb87"
LINK_IP="95.105.72.80"
CF_PROXY="--cf-proxy --cf-proxy-first --cf-balance --cf-domain tochkachat.ru"
```

### Режимы работы

#### SOCKS5

В настройках Telegram (или другого клиента) укажите:

| Параметр | Значение |
|---|---|
| Тип | `SOCKS5` |
| Хост | IP-адрес вашего Orange Pi в локальной сети |
| Порт | `1080` |

Чтобы включить SOCKS5, выполните `reconfigure` и выберите режим 2.

#### MTProto (рекомендуемый)

После запуска прокси вы увидите ссылку для подключения в логах:

```
sudo journalctl -u tg-ws-proxy -f
```

Пример ссылки:

```
tg://proxy?server=ВАШ_IP&port=1443&secret=ВАШ_СЕКРЕТ
```

### Cloudflare-прокси

Для обхода блокировок и стабильной работы рекомендуется использовать Cloudflare. Полная инструкция основана на [официальной документации](https://github.com/Flowseal/tg-ws-proxy/blob/main/docs/CfProxy.md).

#### Зачем настраивать свой домен?

Cloudflare имеет лимиты на одновременное количество WebSocket-подключений. Домен по умолчанию (встроенный в прокси) может перестать работать в любой момент. Использование **собственного домена** гарантирует стабильность.

#### 1. Добавьте домен в Cloudflare

Зарегистрируйте домен в Cloudflare (можно купить напрямую у Cloudflare или изменить NS-серверы существующего домена). Домены стоят примерно 150 рублей в год.

#### 2. Настройте SSL/TLS

В панели Cloudflare перейдите в **SSL/TLS → Overview** и выберите режим **"Flexible"**.

#### 3. Настройте DNS-записи

В разделе **DNS → Records** создайте следующие A-записи через **+ Add Record**:

| Тип | Имя (Name) | IPv4 адрес (Content) |
|---|---|---|
| `A` | `kws1` | `149.154.175.50` |
| `A` | `kws2` | `149.154.167.51` |
| `A` | `kws3` | `149.154.175.100` |
| `A` | `kws4` | `149.154.167.91` |
| `A` | `kws5` | `149.154.171.5` |
| `A` | `kws203` | `91.105.192.100` |

**Важно:** Для каждой записи **включите оранжевое облачко (Proxy status)** — это заставит Cloudflare проксировать трафик.

**Примечание:** Если на основном домене у вас работает сайт (например, GitHub Pages), отключите прокси (серое облачко) для основного домена, оставив оранжевое только для поддоменов `kws1`, `kws2` и т.д.

#### 4. Добавьте домен в исключения (опционально)

Если вы используете ПО для обхода блокировок (например, zapret), добавьте ваш домен в исключения, так как подсеть Cloudflare может быть заблокирована в некоторых странах.

#### 5. Настройте прокси

Запустите `reconfigure` и при вопросе о Cloudflare ответьте **y**, затем введите ваш домен.

Или отредактируйте файл `/etc/tg-ws-proxy/config.env` вручную.

#### 6. Перезапустите прокси

```
sudo systemctl restart tg-ws-proxy
```

В логах должно появиться:

```
cf_proxy=true cf_domain_list=ваш_домен
```

## Решение проблем

### 1. Прокси не запускается

Проверьте логи:

```
sudo journalctl -u tg-ws-proxy -xe
```

Убедитесь, что порт свободен:

```
sudo ss -tulpn | grep 1443
```

### 2. Не удаётся скачать бинарник

- Проверьте интернет-соединение на Orange Pi.
- Возможно, устарел URL. Проверьте последние релизы на [GitHub](https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases).

### 3. Ошибка `./tg-ws-proxy-armbian.sh: строка 8: синтаксическая ошибка`

Вы скачали HTML-страницу вместо скрипта. Убедитесь, что используете **сырую** (raw) ссылку:

```
wget https://raw.githubusercontent.com/san4jkee/tg-ws-proxy-go-systemd/main/tg-ws-proxy-armbian.sh
```

### 4. Cloudflare не включается (`cf_proxy=false`)

Убедитесь, что в файле `/etc/tg-ws-proxy/config.env` есть параметры `CF_PROXY` с правильными флагами.

### 5. Ошибки `i/o timeout` при использовании Cloudflare

Проверьте:

- Домен правильно настроен в Cloudflare.
- Для DNS-записей включено оранжевое облачко.
- В Cloudflare выбран режим SSL/TLS **"Flexible"**.
- Если используете zapret или аналоги, добавьте домен в исключения.

### 6. Медиа не грузятся в Telegram

- Включите Cloudflare-маршрутизацию (см. раздел выше).
- Проверьте, что в логах нет ошибок `i/o timeout`.
- Попробуйте переключиться на SOCKS5-режим.
- Если проблема сохраняется, проверьте, что в настройках прокси указан только `4:149.154.167.220` (это может помочь с загрузкой медиа).

### 7. Хочу изменить настройки после установки

Используйте команду:

```
sudo ./tg-ws-proxy-armbian.sh reconfigure
```

Или отредактируйте файл `/etc/tg-ws-proxy/config.env` вручную.

## Удаление

Полное удаление прокси:

```
sudo ./tg-ws-proxy-armbian.sh remove
```

## Лицензия

MIT License. См. файл LICENSE.

## Благодарности

Оригинальный проект: [d0mhate/-tg-ws-proxy-Manager-go](https://github.com/d0mhate/-tg-ws-proxy-Manager-go)
Инструкция по Cloudflare: [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy/blob/main/docs/CfProxy.md)

