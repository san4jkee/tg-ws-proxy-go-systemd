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
SCRIPT_PATH="/usr/local/bin/tgm" # Симлинк на этот скрипт

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root (sudo)."
    fi
}

get_arch() {
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    # Для Linux и macOS бинарники имеют разные префиксы
    case "$arch" in
        x86_64)   echo "${os}-amd64" ;;
        aarch64)  echo "${os}-arm64" ;;
        armv7l)   echo "${os}-armv7" ;;
        armv6l)   echo "${os}-armv6" ;;
        i386|i686) echo "${os}-386" ;;
        *)        echo "unknown" ;;
    esac
}

# --- Основные функции управления ---

install_binary() {
    check_root
    info "Начинаю установку ${BINARY_NAME}..."

    local arch=$(get_arch)
    local latest_url=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" | grep "browser_download_url.*${arch}" | cut -d '"' -f 4 | head -n 1)

    if [[ -z "$latest_url" ]]; then
        error "Не удалось найти бинарник для архитектуры '${arch}'. Проверьте релизы на GitHub."
    fi

    info "Скачиваю бинарник для $arch: $latest_url"
    wget -q --show-progress -O "/tmp/${BINARY_NAME}" "$latest_url" || error "Ошибка загрузки."
    chmod +x "/tmp/${BINARY_NAME}"

    info "Устанавливаю в ${BIN_PATH}"
    mv "/tmp/${BINARY_NAME}" "${BIN_PATH}"

    # Создаем директорию для состояния
    mkdir -p "${STATE_DIR}"

    ok "Бинарник успешно установлен в ${BIN_PATH}"
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
    else
        warn "Статус: ${RED}ОСТАНОВЛЕН${NC}"
    fi
}

enable_autostart() {
    check_root
    info "Создаю systemd-сервис для автозапуска..."

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=TG WS Proxy (Go)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${STATE_DIR}
ExecStart=${BIN_PATH} --mode socks5 --host 0.0.0.0 --port 1080
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    ok "Автозапуск включен. Сервис: ${SERVICE_FILE}"
}

disable_autostart() {
    check_root
    if [[ -f "${SERVICE_FILE}" ]]; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        rm -f "${SERVICE_FILE}"
        systemctl daemon-reload
        ok "Автозапуск отключен."
    else
        warn "Файл сервиса не найден. Возможно, автозапуск уже отключен."
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
    rm -f "/usr/local/bin/tgm"
    rm -rf "${STATE_DIR}"
    ok "Прокси удален."
}

# --- CLI команды ---
show_help() {
    cat <<EOF
Управление ${BINARY_NAME} (Go версия) для Armbian

Использование:
  $0 {install|update|start|stop|restart|status|enable|disable|remove|help}

Команды:
  install    - Скачать и установить бинарник последней версии
  update     - То же, что и install (обновить бинарник)
  start      - Запустить сервис (systemd)
  stop       - Остановить сервис
  restart    - Перезапустить сервис
  status     - Показать статус сервиса
  enable     - Включить автозапуск при загрузке системы
  disable    - Отключить автозапуск
  remove     - Полностью удалить прокси, сервис и файлы
  help       - Показать эту справку

Примеры:
  sudo $0 install   # Первоначальная установка
  sudo $0 start     # Запуск прокси
  sudo $0 enable    # Добавить в автозагрузку
  sudo $0 status    # Проверить статус
  $0 help           # Эта справка

После установки будет доступна команда: tgm {start|stop|status|...}
EOF
}

# --- Основной обработчик команд ---
main() {
    # Если скрипт вызван как 'tgm', используем первый аргумент как команду
    local cmd="${1:-help}"

    # Создаем симлинк, если скрипт запущен не по полному пути
    if [[ "$0" != "/usr/local/bin/tgm" ]] && [[ "$0" != "./tg-ws-proxy-armbian.sh" ]]; then
        if [[ -f "$0" ]]; then
            ln -sf "$(realpath "$0")" "/usr/local/bin/tgm" 2>/dev/null || true
        fi
    fi

    case "$cmd" in
        install|update)
            install_binary
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
