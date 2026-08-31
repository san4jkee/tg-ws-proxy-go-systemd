# TG WS Proxy (Go) для Armbian / Orange Pi

Это адаптированная версия менеджера [tg-ws-proxy-go](https://github.com/d0mhate/-tg-ws-proxy-Manager-go) для систем на базе Armbian (Debian/Ubuntu), таких как ваш **Orange Pi Zero 2W**.

Вместо OpenWrt-скриптов используется **systemd** для автозапуска, а управление осуществляется через простые команды.

## Особенности

*   **Один бинарный файл**: Не требует Python или других зависимостей.
*   **Лёгкость**: Исполняемый файл весит около 5-7 МБ.
*   **Автозапуск**: Встроенная поддержка systemd.
*   **Поддержка архитектур**: Автоматически определяет arm64, armv7, amd64 и другие.
*   **Поддержка Cloudflare**: Возможность использовать свой домен для обхода блокировок.

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

| Команда | Описание |
|---|---|
| `sudo ./tg-ws-proxy-armbian.sh install` | Скачать и установить последнюю версию бинарника |
| `sudo ./tg-ws-proxy-armbian.sh update` | Обновить бинарник до последней версии |
| `sudo ./tg-ws-proxy-armbian.sh start` | Запустить прокси-сервис |
| `sudo ./tg-ws-proxy-armbian.sh stop` | Остановить прокси-сервис |
| `sudo ./tg-ws-proxy-armbian.sh restart` | Перезапустить прокси-сервис |
| `sudo ./tg-ws-proxy-armbian.sh status` | Показать статус и логи сервиса |
| `sudo ./tg-ws-proxy-armbian.sh enable` | Включить автозапуск при загрузке системы |
| `sudo ./tg-ws-proxy-armbian.sh disable` | Отключить автозапуск |
| `sudo ./tg-ws-proxy-armbian.sh remove` | **Полностью удалить** прокси и все его файлы |

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

По умолчанию прокси запускается в режиме **MTProto** на порту **1443** и слушает все интерфейсы (`0.0.0.0`).

**Чтобы изменить настройки** (порт, режим, включить Cloudflare), отредактируйте файл сервиса:

```
sudo nano /etc/systemd/system/tg-ws-proxy.service
```

Найдите строку `ExecStart` и измените аргументы. Например, для запуска с Cloudflare:

```
ExecStart=/usr/local/bin/tg-ws-proxy --mode mtproto --secret ВАШ_32_СИМВОЛЬНЫЙ_HEX --host 0.0.0.0 --port 1443 --link-ip ВАШ_ПУБЛИЧНЫЙ_IP --cf-proxy --cf-domain ВАШ_ДОМЕН --cf-proxy-first --cf-balance
```

После изменения настроек выполните:

```
sudo systemctl daemon-reload
sudo ./tg-ws-proxy-armbian.sh restart
```

### Режимы работы

#### SOCKS5

В настройках Telegram (или другого клиента) укажите:

| Параметр | Значение |
|---|---|
| Тип | `SOCKS5` |
| Хост | IP-адрес вашего Orange Pi в локальной сети |
| Порт | `1080` |

Чтобы включить SOCKS5, измените в файле сервиса:

```
ExecStart=/usr/local/bin/tg-ws-proxy --mode socks5 --host 0.0.0.0 --port 1080
```

#### MTProto (рекомендуемый)

После запуска прокси вы увидите ссылку для подключения в логах:

```
sudo journalctl -u tg-ws-proxy -f
```

Пример ссылки:

```
tg://proxy?server=ВАШ_IP&port=1443&secret=ВАШ_СЕКРЕТ
```

Секрет генерируется автоматически при первом запуске или задаётся через `--secret`.

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

#### 4. Добавьте домен в исключения (опционально)

Если вы используете ПО для обхода блокировок (например, zapret), добавьте ваш домен в исключения, так как подсеть Cloudflare может быть заблокирована в некоторых странах.

#### 5. Настройте прокси

Отредактируйте файл сервиса и добавьте параметры Cloudflare:

```
ExecStart=/usr/local/bin/tg-ws-proxy --mode mtproto --secret ВАШ_СЕКРЕТ --host 0.0.0.0 --port 1443 --link-ip ВАШ_IP --cf-proxy --cf-domain ВАШ_ДОМЕН --cf-proxy-first --cf-balance
```

Где:

- `--cf-proxy` — **обязательно** включает Cloudflare-маршрутизацию.
- `--cf-domain` — ваш домен, подключённый к Cloudflare.
- `--cf-proxy-first` — сначала пробовать Cloudflare, потом прямой маршрут (рекомендуется).
- `--cf-balance` — балансировать трафик между несколькими поддоменами (рекомендуется).

#### 6. Перезапустите прокси

```
sudo systemctl daemon-reload
sudo ./tg-ws-proxy-armbian.sh restart
```

В логах должно появиться:

```
cf_proxy=true cf_domain_list=ваш_домен
```

#### 7. Проверка работы

Если Cloudflare настроен правильно, ошибки `i/o timeout` должны исчезнуть, а медиа в Telegram начнут загружаться.

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

### 6. Cloudflare не включается (`cf_proxy=false`)

Убедитесь, что в файле сервиса есть **оба** параметра:

- `--cf-proxy` (включает Cloudflare)
- `--cf-domain ваш_домен` (указывает домен)

### 7. Ошибки `i/o timeout` при использовании Cloudflare

Проверьте:

- Домен правильно настроен в Cloudflare.
- Для DNS-записей включено оранжевое облачко.
- В Cloudflare выбран режим SSL/TLS **"Flexible"**.
- Попробуйте добавить `--cf-proxy-first` и `--cf-balance`.
- Если используете zapret или аналоги, добавьте домен в исключения.

### 8. Медиа не грузятся в Telegram

- Включите Cloudflare-маршрутизацию (см. раздел выше).
- Проверьте, что в логах нет ошибок `i/o timeout`.
- Попробуйте переключиться на SOCKS5-режим.
- Если проблема сохраняется, проверьте, что в настройках прокси указан только `4:149.154.167.220` (это может помочь с загрузкой медиа).

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
