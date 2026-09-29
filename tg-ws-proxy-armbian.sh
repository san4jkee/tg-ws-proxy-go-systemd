#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Управление tg-ws-proxy (Go версия) для Armbian / Linux
# Адаптировано из скрипта для OpenWrt
# ============================================================

# --- Конфигурация ---
REPO_OWNER="d0mhate"
REPO_NAME="-tg-ws-proxy-Manager-go"
BINARY_NAME="tg-ws-proxy"
SERVICE_NAME="tg-ws-proxy"
STATE_DIR="/etc/tg-ws-proxy"
BIN_PATH="/usr/local/bin/${BINARY_NAME}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_FILE="${STATE_DIR}/config.env"

# --- Цвета для вывода ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Вспомогательные функции ---
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ask()   { read -r -p "$(echo -e "${BLUE}[?]${NC} $1")" "$2"; }
have()  { command -v "$1" >/dev/null 2>&1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root (sudo)."
    fi
}

check_systemd() {
    have systemctl || error "systemd не найден. Этот скрипт рассчитан на Ubuntu/Debian/Armbian со systemd."
}

# --- Сетевые помощники (curl или wget) ---
fetch() {
    local url="$1"
    if have curl; then
        curl -fsSL "$url"
    elif have wget; then
        wget -qO- "$url"
    else
        error "Не найдены ни curl, ни wget. Установите их и повторите установку."
    fi
}

fetch_head_ok() {
    local url="$1"
    if have curl; then
        curl -fsSIL -o /dev/null "$url" 2>/dev/null
    elif have wget; then
        wget --spider -q "$url" 2>/dev/null
    else
        error "Не найдены ни curl, ни wget. Установите их и повторите установку."
    fi
}

download_to() {
    local url="$1" out="$2"
    if have curl; then
        curl -fL --retry 3 --connect-timeout 15 --progress-bar -o "$out" "$url"
    elif have wget; then
        wget -q --show-progress -O "$out" "$url"
    else
        error "Не найдены ни curl, ни wget. Установите их и повторите установку."
    fi
}

detect_public_ip() {
    local ip=""
    local svc
    for svc in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip=$(fetch "$svc" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# --- Проверка ввода ---
is_ipv4() {
    local ip="$1" octet
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    local IFS=.
    for octet in $ip; do
        if (( 10#$octet > 255 )); then
            return 1
        fi
    done
    return 0
}

is_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] && [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]
}

is_hostname() {
    local h="$1"
    [[ ${#h} -le 253 ]] || return 1
    [[ "$h" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

is_valid_link_host() {
    local v="$1"
    if [[ -z "$v" ]]; then return 0; fi
    if is_ipv4 "$v"; then return 0; fi
    if is_ipv6 "$v"; then return 0; fi
    if is_hostname "$v"; then return 0; fi
    return 1
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

# --- Определение бинарника под архитектуру ---
# В релизах нет linux-amd64/linux-arm64, только openwrt-варианты,
# поэтому для каждой архитектуры перечисляем кандидатов по порядку.
candidate_assets() {
    case "$1" in
        x86_64|amd64)        echo "linux-amd64 openwrt-x86_64" ;;
        aarch64|arm64)       echo "linux-arm64 openwrt-aarch64" ;;
        armv7l|armv7)        echo "linux-armv7 openwrt-armv7 linux-armv6" ;;
        armv6l|armv6)        echo "linux-armv6 openwrt-armv7" ;;
        i386|i486|i586|i686) echo "linux-386" ;;
        riscv64)             echo "linux-riscv64" ;;
        loongarch64|loong64) echo "linux-loong64" ;;
        mipsel*|mips64el*)   echo "openwrt-mipsel_24kc" ;;
        mips*|mips64*)       echo "openwrt-mips_24kc" ;;
        *)                   echo "" ;;
    esac
}

# Определяем тег последнего релиза без GitHub API (без rate-limit),
# при неудаче — через API.
latest_release_tag() {
    local tag=""
    if have curl; then
        tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
            "https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest" 2>/dev/null || true)
        tag="${tag##*/}"
    elif have wget; then
        tag=$(wget -q --spider --server-response --max-redirect=0 \
            "https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest" 2>&1 \
            | grep -i '^ *Location:' | tail -n 1 | sed 's#.*/##' | tr -d '\r' || true)
    fi
    if [[ "$tag" =~ ^v?[0-9]+\.[0-9]+ ]]; then
        echo "$tag"
        return 0
    fi

    tag=$(fetch "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" 2>/dev/null \
        | grep -m1 '"tag_name"' | cut -d '"' -f 4 || true)
    if [[ -n "$tag" ]]; then
        echo "$tag"
        return 0
    fi
    return 1
}

resolve_download_url() {
    local tag="$1" arch="$2" names="$3"
    local name url json

    for name in $names; do
        url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${tag}/tg-ws-proxy-${name}"
        if fetch_head_ok "$url"; then
            echo "$url"
            return 0
        fi
    done

    # Запасной путь через GitHub API (может упираться в rate-limit)
    json=$(fetch "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${tag}" 2>/dev/null || true)
    if [[ -n "$json" ]]; then
        for name in $names; do
            url=$(echo "$json" | grep "browser_download_url.*tg-ws-proxy-${name}\"" | cut -d '"' -f 4 | head -n 1 || true)
            if [[ -n "$url" ]]; then
                echo "$url"
                return 0
            fi
        done
    fi
    return 1
}

verify_downloaded_binary() {
    local f="$1"
    if [[ ! -s "$f" ]]; then
        rm -f "$f"
        error "Файл не был загружен (пустой). Проверьте интернет-соединение."
    fi
    if have od && have head; then
        local magic
        magic=$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')
        if [[ "$magic" != "7f454c46" ]]; then
            rm -f "$f"
            error "Скачанный файл не является Linux-бинарником (скорее всего, это страница ошибки)."
        fi
    else
        local size
        size=$(wc -c < "$f")
        if (( size < 1000000 )); then
            rm -f "$f"
            error "Скачанный файл подозрительно мал (${size} байт)."
        fi
    fi
}

load_config() {
    [[ -f "${CONFIG_FILE}" ]] || return 1
    PROXY_MODE=""
    PORT=""
    SECRET=""
    LINK_IP=""
    CF_PROXY=""
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
    return 0
}

# --- Интерактивная настройка ---
configure_proxy() {
    info "Настройка параметров прокси..."

    # 1. Режим работы
    echo -e "\n${BLUE}Выберите режим работы:${NC}"
    echo "  1) MTProto (рекомендуется, для Telegram)"
    echo "  2) SOCKS5 (универсальный)"
    local mode_choice="1"
    ask "Ваш выбор [1]: " mode_choice
    mode_choice=${mode_choice:-1}
    if [[ "$mode_choice" == "1" ]]; then
        PROXY_MODE="mtproto"
    else
        PROXY_MODE="socks5"
    fi

    # 2. Порт
    local default_port="1443"
    if [[ "$PROXY_MODE" == "socks5" ]]; then
        default_port="1080"
    fi
    while true; do
        ask "Порт [$default_port]: " PORT
        PORT=${PORT:-$default_port}
        if is_valid_port "$PORT"; then
            break
        fi
        warn "Порт должен быть числом от 1 до 65535. Попробуйте снова."
        PORT=""
    done

    # 3. Секрет (только для MTProto)
    SECRET=""
    if [[ "$PROXY_MODE" == "mtproto" ]]; then
        echo -e "\n${BLUE}Настройка секрета MTProto:${NC}"
        echo "  1) Сгенерировать случайный"
        echo "  2) Ввести свой (32 hex-символа)"
        local secret_choice="1"
        ask "Ваш выбор [1]: " secret_choice
        secret_choice=${secret_choice:-1}
        if [[ "$secret_choice" == "2" ]]; then
            while true; do
                ask "Введите 32-символьный hex-ключ: " SECRET
                if [[ ${#SECRET} -eq 32 ]] && [[ "$SECRET" =~ ^[0-9a-fA-F]{32}$ ]]; then
                    break
                else
                    warn "Секрет должен быть ровно 32 hex-символа (0-9, a-f). Попробуйте снова."
                fi
            done
        else
            if have openssl; then
                SECRET=$(openssl rand -hex 16)
            else
                SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
            fi
            if [[ ! "$SECRET" =~ ^[0-9a-f]{32}$ ]]; then
                error "Не удалось сгенерировать секрет. Установите openssl и повторите установку."
            fi
            ok "Сгенерирован секрет: $SECRET"
        fi
    fi

    # 4. Публичный IP / домен
    echo -e "\n${BLUE}Настройка публичного адреса:${NC}"
    echo "  Укажите внешний IP или домен, по которым прокси будет доступен из интернета."
    echo "  Он попадёт в ссылку подключения tg://proxy?server=..."
    echo "  Если прокси только в локальной сети — введите '-' (пропустить)."
    local detected_ip=""
    detected_ip=$(detect_public_ip || true)
    if [[ -n "$detected_ip" ]]; then
        echo "  Обнаружен внешний IP: ${detected_ip} (Enter — принять его)"
    fi
    LINK_IP=""
    while true; do
        if [[ -n "$detected_ip" ]]; then
            ask "Публичный IP/домен [$detected_ip]: " LINK_IP
            if [[ -z "$LINK_IP" ]]; then
                LINK_IP="$detected_ip"
            fi
        else
            ask "Публичный IP/домен (Enter — пропустить): " LINK_IP
        fi
        if [[ "$LINK_IP" == "-" ]]; then
            LINK_IP=""
            break
        fi
        if is_valid_link_host "$LINK_IP"; then
            break
        fi
        warn "Некорректный адрес. Пример: 1.2.3.4 или proxy.example.com (или '-' чтобы пропустить)."
        LINK_IP=""
    done

    # 5. Cloudflare
    CF_PROXY=""
    echo -e "\n${BLUE}Настройка Cloudflare (опционально):${NC}"
    echo "  Cloudflare помогает обходить блокировки и делает прокси стабильнее."
    local use_cf=""
    while true; do
        ask "Cloudflare: y/n, либо сразу введите домен (Enter = n): " use_cf
        use_cf=${use_cf:-n}
        if [[ "$use_cf" =~ ^[Yy]$ ]] || [[ "$use_cf" == "д" ]] || [[ "$use_cf" == "Д" ]]; then
            CF_PROXY="--cf-proxy --cf-proxy-first --cf-balance"
            break
        fi
        if [[ "$use_cf" =~ ^[Nn]$ ]] || [[ "$use_cf" == "н" ]] || [[ "$use_cf" == "Н" ]]; then
            info "Cloudflare отключён."
            break
        fi
        if is_hostname "$use_cf"; then
            CF_PROXY="--cf-proxy --cf-proxy-first --cf-balance --cf-domain $use_cf"
            ok "Cloudflare будет использован с доменом $use_cf"
            break
        fi
        warn "Ответ должен быть y, n или доменом (например tochkachat.ru)."
    done

    if [[ "$use_cf" =~ ^[Yy]$ ]] || [[ "$use_cf" == "д" ]] || [[ "$use_cf" == "Д" ]]; then
        local cf_domain=""
        while true; do
            ask "Введите ваш домен для Cloudflare (например tochkachat.ru): " cf_domain
            if [[ -z "$cf_domain" ]]; then
                warn "Домен не указан. Cloudflare не будет включён."
                CF_PROXY=""
                break
            fi
            if is_hostname "$cf_domain"; then
                CF_PROXY="--cf-proxy --cf-proxy-first --cf-balance --cf-domain $cf_domain"
                ok "Cloudflare будет использован с доменом $cf_domain"
                break
            fi
            warn "Некорректный домен. Пример: tochkachat.ru"
        done
    fi

    # 6. Сохраняем настройки
    SECRET="${SECRET:-}"
    LINK_IP="${LINK_IP:-}"
    CF_PROXY="${CF_PROXY:-}"
    mkdir -p "${STATE_DIR}"
    cat > "${CONFIG_FILE}" <<EOF
PROXY_MODE="$PROXY_MODE"
PORT="$PORT"
SECRET="$SECRET"
LINK_IP="$LINK_IP"
CF_PROXY="$CF_PROXY"
EOF
    chmod 600 "${CONFIG_FILE}"
    ok "Настройки сохранены в ${CONFIG_FILE}"
}

# --- Вывод ссылки подключения ---
# QR_MODE=auto (по умолчанию: только в терминале), on, off
qr_enabled() {
    case "${QR_MODE:-auto}" in
        on|1|always) return 0 ;;
        off|0|never) return 1 ;;
        *) [[ -t 1 ]] ;;
    esac
}

print_qr() {
    local data="$1"
    qr_enabled || return 0

    if [[ -x "${BIN_PATH}" ]]; then
        echo -e "\n${BLUE}QR-код (сканируйте камерой Telegram):${NC}"
        if "${BIN_PATH}" qr "$data" 2>/dev/null; then
            return 0
        fi
        warn "Бинарник не смог отобразить QR-код."
    fi
    if have qrencode; then
        echo -e "\n${BLUE}QR-код (сканируйте камерой Telegram):${NC}"
        if qrencode -t ANSIUTF8 "$data" 2>/dev/null || qrencode -t UTF8 "$data" 2>/dev/null; then
            return 0
        fi
        warn "Не удалось отобразить QR-код через qrencode."
    fi
    info "QR-код пропущен: установите пакет 'qrencode' или повторите установку бинарника."
    return 0
}

print_proxy_link() {
    if ! load_config; then
        warn "Конфигурация не найдена. Сначала выполните: sudo $0 install"
        return 0
    fi

    local ip="${LINK_IP:-}"
    if [[ -z "$ip" ]]; then
        local detected=""
        detected=$(detect_public_ip || true)
        if [[ -n "$detected" ]]; then
            ip="$detected"
            warn "Публичный IP не задан при установке. Для ссылки использован обнаруженный IP: ${ip}"
        else
            ip="<ВАШ_IP>"
            warn "Публичный IP не задан и не обнаружен. Замените <ВАШ_IP> на свой адрес: sudo $0 reconfigure"
        fi
    fi

    echo -e "\n${BLUE}Ссылка для подключения:${NC}"
    if [[ "${PROXY_MODE:-}" == "mtproto" ]]; then
        if [[ -z "${SECRET:-}" ]]; then
            warn "Секрет не задан. Выполните: sudo $0 reconfigure"
            return 0
        fi
        local secret_link="$SECRET"
        local lower="${secret_link,,}"
        case "$lower" in
            dd*|ee*) ;;
            *) secret_link="dd${secret_link}" ;;
        esac
        local link="tg://proxy?server=${ip}&port=${PORT}&secret=${secret_link}"
        echo "  ${link}"
        local jlink=""
        jlink=$(journalctl -u "${SERVICE_NAME}" -n 200 --no-pager 2>/dev/null \
            | grep -o 'tg://proxy[^[:space:]]*' | tail -n 1 || true)
        if [[ -n "$jlink" && "$jlink" != "$link" ]]; then
            echo "  Ссылка из логов сервиса: ${jlink}"
        fi
        if [[ "$ip" != "<ВАШ_IP>" ]]; then
            print_qr "$link"
        fi
    else
        local link="tg://socks?server=${ip}&port=${PORT}"
        echo "  ${link}"
        echo "  В Telegram: тип SOCKS5, сервер ${ip}, порт ${PORT}"
        if [[ "$ip" != "<ВАШ_IP>" ]]; then
            print_qr "$link"
        fi
    fi
}

# --- Основные функции управления ---

install_binary() {
    check_root
    check_systemd
    info "Начинаю установку ${BINARY_NAME}..."

    # Запрашиваем настройки, если конфиг не существует или принудительно
    if [[ ! -f "${CONFIG_FILE}" ]] || [[ "${1:-}" == "--reconfigure" ]]; then
        configure_proxy
    else
        info "Использую существующие настройки из ${CONFIG_FILE}"
        load_config
    fi

    local arch names tag url
    arch=$(uname -m)
    names=$(candidate_assets "$arch")
    if [[ -z "$names" ]]; then
        error "Архитектура '${arch}' не поддерживается. Доступны: x86_64, aarch64, armv7, armv6, i386, mips/mipsel, riscv64, loong64."
    fi

    info "Определяю последнюю версию..."
    tag=$(latest_release_tag || true)
    if [[ -z "$tag" ]]; then
        error "Не удалось определить последнюю версию. Релизы: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases"
    fi

    url=$(resolve_download_url "$tag" "$arch" "$names" || true)
    if [[ -z "$url" ]]; then
        error "Не удалось найти бинарник для '${arch}' в релизе ${tag}. Ручная установка: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${tag}"
    fi

    info "Скачиваю бинарник (${tag}, архитектура ${arch}): $url"
    download_to "$url" "/tmp/${BINARY_NAME}" || error "Ошибка загрузки."
    verify_downloaded_binary "/tmp/${BINARY_NAME}"
    chmod +x "/tmp/${BINARY_NAME}"

    mkdir -p "${STATE_DIR}" "$(dirname "${BIN_PATH}")"
    mv "/tmp/${BINARY_NAME}" "${BIN_PATH}"
    ok "Бинарник установлен в ${BIN_PATH}"

    # Предлагаем включить автозапуск
    local enable_now=0
    if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
        info "Автозапуск уже включён — обновляю сервис..."
        enable_now=1
    else
        echo -e "\n${BLUE}Хотите включить автозапуск при загрузке системы?${NC}"
        local ENABLE_AUTO="n"
        ask "(y/N): " ENABLE_AUTO
        if [[ "$ENABLE_AUTO" =~ ^[Yy]$ ]]; then
            enable_now=1
        fi
    fi

    if [[ "$enable_now" -eq 1 ]]; then
        create_service
        systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
        if ! systemctl restart "${SERVICE_NAME}" 2>/dev/null; then
            systemctl start "${SERVICE_NAME}" 2>/dev/null || true
        fi
        sleep 1
        if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
            warn "Сервис не запустился. Последние логи:"
            journalctl -u "${SERVICE_NAME}" -n 30 --no-pager 2>/dev/null || true
            error "Установка не завершена: сервис ${SERVICE_NAME} не работает."
        fi
        ok "Автозапуск включён и сервис запущен."
    else
        info "Автозапуск не включён. Запуск вручную: sudo systemctl start ${SERVICE_NAME}"
    fi

    show_config
    print_proxy_link
}

create_service() {
    load_config || error "Конфигурация не найдена: ${CONFIG_FILE}"

    PROXY_MODE="${PROXY_MODE:-mtproto}"
    PORT="${PORT:-1443}"
    SECRET="${SECRET:-}"
    LINK_IP="${LINK_IP:-}"
    CF_PROXY="${CF_PROXY:-}"

    # Формируем команду запуска
    local cmd="${BIN_PATH} --mode ${PROXY_MODE} --host 0.0.0.0 --port ${PORT}"
    if [[ "$PROXY_MODE" == "mtproto" ]] && [[ -n "$SECRET" ]]; then
        cmd="$cmd --secret ${SECRET}"
    fi
    if [[ -n "$LINK_IP" ]] && [[ "$PROXY_MODE" == "mtproto" ]]; then
        cmd="$cmd --link-ip ${LINK_IP}"
    fi
    if [[ -n "$CF_PROXY" ]]; then
        cmd="$cmd ${CF_PROXY}"
    fi

    info "Создаю systemd-сервис..."
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=TG WS Proxy (Go) - Armbian
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${STATE_DIR}
ExecStart=${cmd}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    ok "Сервис создан: ${SERVICE_FILE}"
}

start_proxy() {
    check_root
    check_systemd
    [[ -f "${SERVICE_FILE}" ]] || error "Сервис не создан. Выполните: sudo $0 install"
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "Запускаю сервис ${SERVICE_NAME}..."
        if ! systemctl start "${SERVICE_NAME}" 2>/dev/null; then
            warn "Не удалось запустить сервис. Последние логи:"
            journalctl -u "${SERVICE_NAME}" -n 30 --no-pager 2>/dev/null || true
            error "Запуск ${SERVICE_NAME} не удался."
        fi
        sleep 2
    else
        warn "Сервис уже запущен."
    fi
    status_proxy
}

stop_proxy() {
    check_root
    check_systemd
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "Останавливаю сервис ${SERVICE_NAME}..."
        systemctl stop "${SERVICE_NAME}"
        ok "Сервис остановлен."
    else
        warn "Сервис уже остановлен."
    fi
}

status_proxy() {
    check_systemd
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        ok "Статус: ${GREEN}ЗАПУЩЕН${NC}"
        systemctl status "${SERVICE_NAME}" --no-pager -l || true
        echo -e "\n${BLUE}Последние логи:${NC}"
        journalctl -u "${SERVICE_NAME}" -n 10 --no-pager || true
        print_proxy_link
    else
        warn "Статус: ${RED}ОСТАНОВЛЕН${NC}"
        if [[ -f "${CONFIG_FILE}" ]]; then
            print_proxy_link
        fi
    fi
}

enable_autostart() {
    check_root
    check_systemd
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        warn "Настройки не найдены. Запустите 'install' для конфигурации."
        return
    fi
    create_service
    systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl start "${SERVICE_NAME}" 2>/dev/null || true
    sleep 1
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        warn "Сервис не запустился. Последние логи:"
        journalctl -u "${SERVICE_NAME}" -n 30 --no-pager 2>/dev/null || true
        error "Не удалось запустить ${SERVICE_NAME}."
    fi
    ok "Автозапуск включён и сервис запущен."
    print_proxy_link
}

disable_autostart() {
    check_root
    check_systemd
    if [[ -f "${SERVICE_FILE}" ]]; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        rm -f "${SERVICE_FILE}"
        systemctl daemon-reload
        ok "Автозапуск отключён."
    else
        warn "Файл сервиса не найден. Возможно, автозапуск уже отключён."
    fi
}

remove_proxy() {
    check_root
    check_systemd
    warn "Вы уверены, что хотите полностью удалить прокси? (y/N)"
    local confirm=""
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Удаление отменено."
        return
    fi

    info "Удаляю прокси..."
    disable_autostart
    rm -f "${BIN_PATH}"
    rm -rf "${STATE_DIR}"
    ok "Прокси удалён."
}

show_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        echo -e "\n${BLUE}Текущие настройки:${NC}"
        cat "${CONFIG_FILE}"
        echo ""
    fi
}

show_help() {
    cat <<EOF
Управление ${BINARY_NAME} (Go) для Armbian

Использование:
  $0 {install|update|start|stop|restart|status|link|enable|disable|remove|reconfigure|help}

Команды:
  install          - Установить бинарник (с интерактивной настройкой)
  install --reconfigure - Переустановить с новой настройкой
  update           - Обновить бинарник
  start            - Запустить сервис
  stop             - Остановить сервис
  restart          - Перезапустить сервис
  status           - Показать статус, логи, ссылку и QR-код
  link             - Показать ссылку подключения (tg://proxy) и QR-код
  enable           - Включить автозапуск (создать сервис)
  disable          - Отключить автозапуск
  remove           - Полностью удалить
  reconfigure      - Изменить настройки без переустановки
  help             - Эта справка

Примеры:
  sudo $0 install   # Интерактивная установка
  sudo $0 enable    # Включить автозапуск
  $0 status         # Проверить статус
  sudo $0 link      # Получить ссылку для Telegram
EOF
}

# --- Основной обработчик команд ---
main() {
    local cmd="${1:-help}"
    local arg="${2:-}"

    case "$cmd" in
        install)
            install_binary "$arg"
            ;;
        update)
            install_binary "--reconfigure"
            ;;
        start)
            start_proxy
            ;;
        stop)
            stop_proxy
            ;;
        restart)
            stop_proxy
            start_proxy
            ;;
        status)
            status_proxy
            ;;
        link)
            print_proxy_link
            ;;
        enable)
            enable_autostart
            ;;
        disable)
            disable_autostart
            ;;
        remove)
            remove_proxy
            ;;
        reconfigure)
            check_root
            check_systemd
            configure_proxy
            if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
                create_service
                systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
                sleep 1
                if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
                    warn "Сервис не запустился после переконфигурации. Логи:"
                    journalctl -u "${SERVICE_NAME}" -n 30 --no-pager 2>/dev/null || true
                else
                    ok "Сервис обновлён с новыми настройками."
                fi
            fi
            show_config
            print_proxy_link
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Неизвестная команда: $cmd. Используйте 'help' для списка команд."
            ;;
    esac
}

# Запускаем main с переданными аргументами
main "$@"
