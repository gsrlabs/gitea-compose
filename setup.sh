#!/bin/bash

# ======================================
# SETUP SCRIPT FOR PROJECT
# Автоматическая первичная настройка
# ======================================

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }
info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
header()  { echo -e "${CYAN}════════════════════════════════════════════════════${NC}"; }

# ======================================
# ОПРЕДЕЛЕНИЕ ПУТЕЙ
# ======================================

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE="$PROJECT_ROOT/.env_example"

# ======================================
# ЗАГРУЗКА ПЕРЕМЕННЫХ ПРОЕКТА
# ======================================

load_env_variables() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    elif [ -f "$ENV_EXAMPLE" ]; then
        source "$ENV_EXAMPLE"
    fi

    # Значения по умолчанию (если не найдены)
    PROJECT_NAME="${PROJECT_NAME:-project}"
    PROJECT_DISPLAY_NAME="${PROJECT_DISPLAY_NAME:-Project}"

    MANAGE_CMD="${PROJECT_NAME}-manage"
}

# ======================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ======================================

check_dependencies() {
    info "Проверка зависимостей..."

    if ! command -v docker >/dev/null; then
        error "Docker не установлен!"
        exit 1
    fi

    if ! command -v docker-compose >/dev/null && ! docker compose version >/dev/null 2>&1; then
        error "Docker Compose не найден!"
        exit 1
    fi

    success "Зависимости проверены"
}

# ======================================
# СОЗДАНИЕ ДИРЕКТОРИЙ
# ======================================

create_directories() {
    info "Создание структуры директорий..."

    DIRS=("scripts" "backups" "data" "postgres_data")

    for dir in "${DIRS[@]}"; do
        mkdir -p "$PROJECT_ROOT/$dir"
        success "Директория создана: $dir"
    done

    chmod +x "$PROJECT_ROOT/scripts/"*.sh 2>/dev/null || true
}

# ======================================
# .ENV ФАЙЛ
# ======================================

setup_env_file() {
    info "Настройка файла .env..."

    if [ ! -f "$ENV_FILE" ]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        sed -i "s|PROJECT_DIR=.*|PROJECT_DIR=\"$PROJECT_ROOT\"|" "$ENV_FILE"
        success "Создан .env"

        warning "Отредактируйте .env перед запуском!"
    else
        sed -i "s|PROJECT_DIR=.*|PROJECT_DIR=\"$PROJECT_ROOT\"|" "$ENV_FILE"
        info "PROJECT_DIR обновлен"
    fi
}

# ======================================
# ПРАВА ДОСТУПА
# ======================================

setup_permissions() {
    info "Настройка прав доступа..."

    sudo chown -R 1000:1000 "$PROJECT_ROOT/data"        2>/dev/null
    sudo chown -R 999:999  "$PROJECT_ROOT/postgres_data" 2>/dev/null

    chmod +x "$PROJECT_ROOT/scripts/"*.sh 2>/dev/null
}

# ======================================
# СОЗДАНИЕ СИМЛИНКА
# ======================================

create_symlink() {
    info "Создание симлинков..."

    local run_script="$PROJECT_ROOT/scripts/run.sh"

    if [ ! -f "$run_script" ]; then
        error "run.sh не найден!"
        return
    fi

    chmod +x "$run_script"

    # 1) /usr/local/bin
    if command -v sudo >/dev/null; then
        if sudo ln -sf "$run_script" "/usr/local/bin/${MANAGE_CMD}"; then
            success "Симлинк создан: /usr/local/bin/${MANAGE_CMD}"
        fi
    fi

    # 2) ~/.local/bin
    mkdir -p "$HOME/.local/bin"
    ln -sf "$run_script" "$HOME/.local/bin/${MANAGE_CMD}"
    success "Симлинк создан: ~/.local/bin/${MANAGE_CMD}"

    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        warning "~/.local/bin нет в PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        info "Строка PATH добавлена в ~/.bashrc"
    fi
}

# ======================================
# ПРОВЕРКА DOCKER COMPOSE
# ======================================

check_compose_config() {
    info "Проверка docker-compose.yml..."

    cd "$PROJECT_ROOT"

    if command -v docker-compose >/dev/null; then
        docker-compose config -q || { error "Ошибка в docker-compose.yml"; exit 1; }
    else
        docker compose config -q || { error "Ошибка в docker-compose.yml"; exit 1; }
    fi

    success "Конфигурация корректна"
}

# ======================================
# ИТОГ
# ======================================

show_summary() {
    header
    echo -e "${GREEN}🎉 Установка завершена!${NC}"
    header

    echo ""
    echo -e "${CYAN}Основные команды управления:${NC}"
    echo -e "  ${GREEN}${MANAGE_CMD} start${NC}"
    echo -e "  ${GREEN}${MANAGE_CMD} stop${NC}"
    echo -e "  ${GREEN}${MANAGE_CMD} status${NC}"
    echo -e "  ${GREEN}${MANAGE_CMD} backup${NC}"

    echo ""
    echo -e "${CYAN}Проект:${NC} ${PROJECT_DISPLAY_NAME}"
    echo -e "${CYAN}Директория:${NC} $PROJECT_ROOT"

    echo ""
}

# ======================================
# MAIN
# ======================================

main() {
    clear
    header
    echo -e "${CYAN}     SETUP: ${PROJECT_DISPLAY_NAME}${NC}"
    header
    echo ""

    load_env_variables
    check_dependencies
    create_directories
    setup_env_file
    setup_permissions
    check_compose_config
    create_symlink
    show_summary
}

main
