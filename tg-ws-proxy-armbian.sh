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
ask()   { read -p "$(echo -e "${BLUE}[?]${NC} $1")" "$2"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root (sudo)."
    fi
}

get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        aarch64)  echo "openwrt-aarch64" ;;
        armv7l)   echo "openwrt-armv7" ;;
        x86_64)   echo "openwrt-x86_64" ;;
        mipsel*|mips64el*) echo "openwrt-mipsel_24kc" ;;
        mips*|mips64*) echo "openwrt-mips_24kc" ;;
        *)        echo "unknown" ;;
    esac
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
    ask "Порт [$default_port]: " PORT
    PORT=${PORT:-$default_port}

    # 3. Секрет (только для MTProto)
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
            SECRET=$(openssl rand -hex 16)
            ok "Сгенерирован секрет: $SECRET"
        fi
    fi

    # 4. Публичный IP
    echo -e "\n${BLUE}Настройка публичного IP:${NC}"
    echo "  Если прокси будет доступен из интернета, укажите ваш внешний IP."
    echo "  Если только в локальной сети, оставьте пустым или укажите IP в сети."
    ask "Публичный IP (или нажмите Enter для пропуска): " LINK_IP

    # 5. Cloudflare
    echo -e "\n${BLUE}Настройка Cloudflare (опционально):${NC}"
    echo "  Cloudflare помогает обходить блокировки и делает прокси стабильнее."
    ask "У вас есть домен, подключенный к Cloudflare? (y/N): " USE_CF
    USE_CF=${USE_CF:-N}
    if [[ "$USE_CF" =~ ^[Yy]$ ]]; then
        CF_PROXY="--cf-proxy --cf-proxy-first --cf-balance"
        ask "Введите ваш домен для Cloudflare: " CF_DOMAIN
        if [[ -n "$CF_DOMAIN" ]]; then
            CF_PROXY="$CF_PROXY --cf-domain $CF_DOMAIN"
            ok "Cloudflare будет использован с доменом $CF_DOMAIN"
        else
            warn "Домен не указан. Cloudflare не будет включён."
            CF_PROXY=""
        fi
    else
        CF_PROXY=""
        info "Cloudflare отключён."
    fi

    # 6. Сохраняем настройки
    mkdir -p "${STATE_DIR}"
    cat > "${CONFIG_FILE}" <<EOF
PROXY_MODE="$PROXY_MODE"
PORT="$PORT"
SECRET="$SECRET"
LINK_IP="$LINK_IP"
CF_PROXY="$CF_PROXY"
EOF
    ok "Настройки сохранены в ${CONFIG_FILE}"
}

# --- Основные функции управления ---

install_binary() {
    check_root
    info "Начинаю установку ${BINARY_NAME}..."

    # Запрашиваем настройки, если конфиг не существует или принудительно
    if [[ ! -f "${CONFIG_FILE}" ]] || [[ "$1" == "--reconfigure" ]]; then
        configure_proxy
    else
        info "Использую существующие настройки из ${CONFIG_FILE}"
        source "${CONFIG_FILE}"
    fi

    local arch=$(get_arch)
    local latest_url=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" | grep "browser_download_url.*${arch}" | cut -d '"' -f 4 | head -n 1)

    if [[ -z "$latest_url" ]]; then
        error "Не удалось найти бинарник для архитектуры '${arch}'. Проверьте релизы на GitHub."
    fi

    info "Скачиваю бинарник для $arch: $latest_url"
    wget -q --show-progress -O "/tmp/${BINARY_NAME}" "$latest_url" || error "Ошибка загрузки."
    chmod +x "/tmp/${BINARY_NAME}"

    mkdir -p "${STATE_DIR}"
    mv "/tmp/${BINARY_NAME}" "${BIN_PATH}"
    ok "Бинарник установлен в ${BIN_PATH}"

    # Если включен автозапуск, пересоздаём сервис
    if systemctl is-enabled "${SERVICE_NAME}" &>/dev/null; then
        info "Автозапуск уже включён, обновляю сервис..."
        create_service
        systemctl restart "${SERVICE_NAME}"
    fi

    # Предлагаем включить автозапуск
    echo -e "\n${BLUE}Хотите включить автозапуск при загрузке системы?${NC}"
    ask "(y/N): " ENABLE_AUTO
    if [[ "$ENABLE_AUTO" =~ ^[Yy]$ ]]; then
        create_service
        systemctl enable "${SERVICE_NAME}"
        systemctl start "${SERVICE_NAME}"
        ok "Автозапуск включён и сервис запущен."
    else
        info "Автозапуск не включён. Для запуска используйте: sudo systemctl start ${SERVICE_NAME}"
    fi

    show_config
}

create_service() {
    source "${CONFIG_FILE}"

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
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "Запускаю сервис ${SERVICE_NAME}..."
        systemctl start "${SERVICE_NAME}"
        sleep 2
    else
        warn "Сервис уже запущен."
    fi
    status_proxy
}

stop_proxy() {
    check_root
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "Останавливаю сервис ${SERVICE_NAME}..."
        systemctl stop "${SERVICE_NAME}"
        ok "Сервис остановлен."
    else
        warn "Сервис уже остановлен."
    fi
}

status_proxy() {
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        ok "Статус: ${GREEN}ЗАПУЩЕН${NC}"
        systemctl status "${SERVICE_NAME}" --no-pager -l
        echo -e "\n${BLUE}Последние логи:${NC}"
        journalctl -u "${SERVICE_NAME}" -n 10 --no-pager
    else
        warn "Статус: ${RED}ОСТАНОВЛЕН${NC}"
    fi
}

enable_autostart() {
    check_root
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        warn "Настройки не найдены. Запустите 'install' для конфигурации."
        return
    fi
    create_service
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
    ok "Автозапуск включён и сервис запущен."
}

disable_autostart() {
    check_root
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
    warn "Вы уверены, что хотите полностью удалить прокси? (y/N)"
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
  $0 {install|update|start|stop|restart|status|enable|disable|remove|reconfigure|help}

Команды:
  install          - Установить бинарник (с интерактивной настройкой)
  install --reconfigure - Переустановить с новой настройкой
  update           - Обновить бинарник
  start            - Запустить сервис
  stop             - Остановить сервис
  restart          - Перезапустить сервис
  status           - Показать статус и логи
  enable           - Включить автозапуск (создать сервис)
  disable          - Отключить автозапуск
  remove           - Полностью удалить
  reconfigure      - Изменить настройки без переустановки
  help             - Эта справка

Примеры:
  sudo $0 install   # Интерактивная установка
  sudo $0 enable    # Включить автозапуск
  $0 status         # Проверить статус
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
            configure_proxy
            if systemctl is-enabled "${SERVICE_NAME}" &>/dev/null; then
                create_service
                systemctl restart "${SERVICE_NAME}"
                ok "Сервис обновлён с новыми настройками."
            fi
            show_config
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
