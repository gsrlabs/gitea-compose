#!/bin/bash

# ======================================
# КОНФИГУРАЦИЯ И ИНИЦИАЛИЗАЦИЯ
# ======================================

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Определяем путь к фактическому расположению run.sh, даже если это симлинк
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

PROJECT_ROOT="$SCRIPT_DIR/.."
ENV_FILE="$PROJECT_ROOT/.env"

# Загрузка конфигурации из .env
load_config() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        success "Конфигурация загружена из $ENV_FILE"
    else
        echo -e "${RED}❌ Файл .env не найден${NC}"
        echo -e "${YELLOW}Ожидаемый путь: $ENV_FILE${NC}"
        echo -e "${YELLOW}Создайте файл .env на основе .env_example${NC}"
        exit 1
    fi
}

# Функции вывода
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }
info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
header()  { echo -e "${CYAN}════════════════════════════════════════════════════${NC}"; }

# Получение имени проекта
get_project_name() {
    if [ -n "$PROJECT_DISPLAY_NAME" ]; then
        echo "$PROJECT_DISPLAY_NAME"
    elif [ -n "$PROJECT_NAME" ]; then
        echo "$PROJECT_NAME"
    else
        echo "проект"
    fi
}

# ======================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ======================================

# Функция для запуска docker compose в корне проекта
run_compose() {
    cd "$PROJECT_ROOT" && $COMPOSE_CMD "$@"
}

# Проверка зависимостей
check_dependencies() {
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен!"
        exit 1
    fi
    
    if ! $COMPOSE_CMD version &> /dev/null; then
        error "Docker Compose не установлен или не работает!"
        exit 1
    fi
    
    success "Зависимости проверены"
}

# Проверка файла docker-compose.yml
check_compose_file() {
    if [ ! -f "$PROJECT_ROOT/$COMPOSE_FILE" ]; then
        error "Файл $COMPOSE_FILE не найден в $PROJECT_ROOT!"
        exit 1
    fi
    success "Файл $COMPOSE_FILE найден"
}

# Показать статус контейнеров
show_status() {
    header
    info "Статус контейнеров $PROJECT_NAME_DISPLAY:"
    echo ""
    run_compose ps
    echo ""
    
    # Показать использование диска
    if [ -d "$DATA_DIR" ]; then
        echo "📊 Использование диска:"
        echo "  Gitea данные: $(du -sh "$DATA_DIR" | cut -f1)"
    fi
    if [ -d "$POSTGRES_DATA_DIR" ]; then
        echo "  PostgreSQL: $(du -sh "$POSTGRES_DATA_DIR" | cut -f1)"
    fi
    header
}

# Проверка запущенных контейнеров
is_running() {
    run_compose ps --services --filter "status=running" | grep -q "$1"
    return $?
}

# ======================================
# ОСНОВНЫЕ КОМАНДЫ
# ======================================

cmd_start() {
    info "Запуск $PROJECT_NAME_DISPLAY..."
    check_dependencies
    check_compose_file
    
    run_compose up -d
    
    if [ $? -eq 0 ]; then
        sleep 3
        show_status
        success "$PROJECT_NAME_DISPLAY успешно запущен"
        info "  🌐 Веб-интерфейс: https://${DOMAIN_NAME}"
        info "  🔑 SSH: git@${DOMAIN_NAME}:${SSH_PORT}"
    else
        error "Ошибка при запуске $PROJECT_NAME_DISPLAY"
        run_compose logs --tail=20
    fi
}

cmd_stop() {
    info "Остановка $PROJECT_NAME_DISPLAY..."
    run_compose stop
    success "$PROJECT_NAME_DISPLAY остановлен"
}

cmd_restart() {
    info "Перезапуск $PROJECT_NAME_DISPLAY..."
    run_compose restart
    sleep 2
    show_status
    success "$PROJECT_NAME_DISPLAY перезапущен"
}

cmd_down() {
    warning "Полная остановка и удаление контейнеров $PROJECT_NAME_DISPLAY..."
    read -p "Вы уверены? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_compose down
        success "Контейнеры $PROJECT_NAME_DISPLAY удалены"
    else
        info "Операция отменена"
    fi
}

cmd_logs() {
    info "Логи $PROJECT_NAME_DISPLAY (Ctrl+C для выхода)..."
    run_compose logs -f --tail=50
}

cmd_status() {
    check_dependencies
    check_compose_file
    show_status
}

cmd_backup() {
    info "Создание резервной копии $PROJECT_NAME_DISPLAY..."
    
    # Останавливаем сервисы для согласованного бэкапа
    warning "Остановка сервисов для согласованного бэкапа..."
    run_compose stop
    
    # Выполняем бэкап
    $SCRIPT_DIR/backup.sh
    
    # Запускаем сервисы обратно
    success "Запуск сервисов после бэкапа..."
    run_compose start
}

cmd_restore() {
    info "Восстановление $PROJECT_NAME_DISPLAY из бэкапа..."
    
    if [ -z "$2" ]; then
        $SCRIPT_DIR/restore.sh
    else
        sudo $SCRIPT_DIR/restore.sh "$2"
    fi
}

cmd_update() {
    info "Обновление $PROJECT_NAME_DISPLAY..."
    
    # Останавливаем сервисы
    run_compose stop
    
    # Обновляем образы
    info "Загрузка новых образов..."
    run_compose pull
    
    # Пересоздаем контейнеры
    info "Пересоздание контейнеров..."
    run_compose up -d --remove-orphans
    
    # Очищаем старые образы
    info "Очистка старых образов..."
    docker image prune -f
    
    show_status
    success "$PROJECT_NAME_DISPLAY обновлен"
}

cmd_shell() {
    info "Вход в контейнер $PROJECT_NAME_DISPLAY..."
    run_compose exec server /bin/bash || \
    run_compose exec server /bin/sh
}

cmd_db_shell() {
    info "Вход в контейнер PostgreSQL..."
    run_compose exec db psql -U gitea
}

# ======================================
# СПРАВОЧНАЯ ИНФОРМАЦИЯ
# ======================================

show_help() {
    header
    echo -e "${CYAN}    УПРАВЛЕНИЕ СЕРВЕРОМ $PROJECT_NAME_DISPLAY ${NC}"
    header
    echo ""
    echo -e "  ${YELLOW}Основные команды:${NC}"
    echo -e "    ${GREEN}start${NC}     — Запустить сервер"
    echo -e "    ${GREEN}stop${NC}      — Остановить сервер"
    echo -e "    ${GREEN}restart${NC}   — Перезапустить сервер"
    echo -e "    ${GREEN}down${NC}      — Остановить и удалить контейнеры"
    echo -e "    ${GREEN}status${NC}    — Показать статус"
    echo ""
    echo -e "  ${YELLOW}Логи и отладка:${NC}"
    echo -e "    ${GREEN}logs${NC}      — Показать логи (реальный времени)"
    echo -e "    ${GREEN}shell${NC}     — Войти в контейнер Gitea"
    echo -e "    ${GREEN}db-shell${NC}  — Войти в контейнер PostgreSQL"
    echo ""
    echo -e "  ${YELLOW}Обслуживание:${NC}"
    echo -e "    ${GREEN}backup${NC}    — Создать резервную копию"
    echo -e "    ${GREEN}restore${NC}   — Восстановить из бэкапа"
    echo -e "    ${GREEN}update${NC}    — Обновить до последней версии"
    echo ""
    echo -e "  ${YELLOW}Дополнительно:${NC}"
    echo -e "    ${GREEN}help${NC}      — Показать эту справку"
    echo -e "    ${GREEN}config${NC}    — Показать текущую конфигурацию"
    echo ""
    header
    echo -e "${BLUE}Использование: ./scripts/run.sh [команда]${NC}"
    echo -e "${BLUE}Использование: $PROJECT_NAME-manаge [команда]${NC}"
    echo ""
}

show_config() {
    header
    info "Текущая конфигурация:"
    echo ""
    echo -e "  ${CYAN}Проект:${NC} $PROJECT_NAME_DISPLAY ($PROJECT_NAME)"
    echo -e "  ${CYAN}Домен:${NC} $DOMAIN_NAME"
    echo -e "  ${CYAN}Порт SSH:${NC} $SSH_PORT"
    echo -e "  ${CYAN}Данные Gitea:${NC} $DATA_DIR"
    echo -e "  ${CYAN}Данные PostgreSQL:${NC} $POSTGRES_DATA_DIR"
    echo -e "  ${CYAN}Бэкапы:${NC} $BACKUP_DIR"
    echo -e "  ${CYAN}Retention:${NC} $BACKUP_RETENTION_DAYS дней"
    echo ""
    echo -e "  ${CYAN}Команда Docker:${NC} $COMPOSE_CMD"
    echo -e "  ${CYAN}Файл compose:${NC} $COMPOSE_FILE"
    header
}

# ======================================
# ОСНОВНАЯ ЛОГИКА
# ======================================

# Загружаем конфигурацию
load_config

# Определяем отображаемое имя проекта ПОСЛЕ загрузки конфигурации
PROJECT_NAME_DISPLAY=$(get_project_name)

# Обработка команд
case "$1" in
    "start")
        cmd_start
        ;;
    "stop")
        cmd_stop
        ;;
    "restart")
        cmd_restart
        ;;
    "down")
        cmd_down
        ;;
    "logs")
        cmd_logs
        ;;
    "status")
        cmd_status
        ;;
    "backup")
        cmd_backup
        ;;
    "restore")
        cmd_restore "$2"
        ;;
    "update")
        cmd_update
        ;;
    "shell")
        cmd_shell
        ;;
    "db-shell"|"db")
        cmd_db_shell
        ;;
    "config")
        show_config
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        error "Неизвестная команда: $1"
        show_help
        exit 1
        ;;
esac

exit 0