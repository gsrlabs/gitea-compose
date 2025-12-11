#!/bin/bash

# ======================================
# СКРИПТ НАСТРОЙКИ GITEA
# Автоматизирует начальную настройку после клонирования репозитория
# ======================================

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции вывода
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }
info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
header()  { echo -e "${CYAN}════════════════════════════════════════════════════${NC}"; }

# Получаем абсолютный путь к директории скрипта
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

# ======================================
# ФУНКЦИИ
# ======================================

# Проверка зависимостей
check_dependencies() {
    info "Проверка зависимостей..."
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен!"
        echo "Установите Docker:"
        echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
        echo "  sudo sh get-docker.sh"
        exit 1
    fi
    
    # Проверка Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose не установлен!"
        echo "Установите Docker Compose:"
        echo "  sudo apt-get install docker-compose-plugin"
        exit 1
    fi
    
    success "Зависимости проверены"
}

# Создание необходимых директорий
create_directories() {
    info "Создание структуры директорий..."
    
    # Основные директории
    DIRS=("scripts" "backups" "data" "postgres_data")
    
    for dir in "${DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            success "  Создана директория: $dir"
        else
            info "  Директория уже существует: $dir"
        fi
    done
    
    # Даем правильные права на scripts
    chmod +x scripts/*.sh 2>/dev/null || true
    
    success "Структура директорий создана"
}

# Копирование .env файла
setup_env_file() {
    info "Настройка файла окружения..."
    
    if [ ! -f ".env" ]; then
        if [ -f ".env_example" ]; then
            cp .env_example .env
            success "Создан файл .env из .env_example"
            
            # Обновляем PROJECT_DIR в .env
            sed -i "s|PROJECT_DIR=.*|PROJECT_DIR=$PROJECT_DIR|g" .env
            
            warning "⚠️  ОБЯЗАТЕЛЬНО отредактируйте файл .env!"
            warning "  nano .env"
            echo ""
            warning "Замените:"
            warning "  - DOMAIN_NAME на ваш домен"
            warning "  - POSTGRES_PASSWORD на надежный пароль"
            warning "  - GITEA_DB_PASSWORD на надежный пароль"
        else
            error "Файл .env_example не найден!"
            exit 1
        fi
    else
        info "Файл .env уже существует"
    fi
}

# Настройка прав доступа
setup_permissions() {
    info "Настройка прав доступа..."
    
    # Права на данные Gitea (UID 1000)
    if [ -d "data" ]; then
        sudo chown -R 1000:1000 data/ 2>/dev/null || {
            warning "Не удалось изменить владельца data/, возможно нужно sudo"
        }
        success "Права установлены для data/ (UID 1000)"
    fi
    
    # Права на данные PostgreSQL (UID 999)
    if [ -d "postgres_data" ]; then
        sudo chown -R 999:999 postgres_data/ 2>/dev/null || {
            warning "Не удалось изменить владельца postgres_data/, возможно нужно sudo"
        }
        success "Права установлены для postgres_data/ (UID 999)"
    fi
    
    # Права на скрипты
    chmod +x scripts/*.sh 2>/dev/null && success "Права на скрипты установлены"
}

# Создание симлинка для удобства
create_symlink() {
    info "Создание симлинка для управления..."
    
    if [ -f "scripts/run.sh" ]; then
        # Пробуем создать симлинк в /usr/local/bin
        sudo ln -sf "$PROJECT_DIR/scripts/run.sh" /usr/local/bin/gitea-manage 2>/dev/null
        
        if [ $? -eq 0 ]; then
            success "Создан симлинк: gitea-manage → scripts/run.sh"
            info "Теперь можно использовать команду: gitea-manage"
        else
            warning "Не удалось создать симлинк в /usr/local/bin"
            info "Можно создать симлинк вручную:"
            info "  sudo ln -s $PROJECT_DIR/scripts/run.sh /usr/local/bin/gitea-manage"
        fi
    fi
}

# Проверка конфигурации Docker Compose
check_compose_config() {
    info "Проверка конфигурации Docker Compose..."
    
    if [ ! -f "docker-compose.yml" ]; then
        error "Файл docker-compose.yml не найден!"
        exit 1
    fi
    
    # Проверяем синтаксис docker-compose.yml
    if command -v docker-compose &> /dev/null; then
        docker-compose config -q && success "Конфигурация Docker Compose валидна"
    elif docker compose version &> /dev/null; then
        docker compose config -q && success "Конфигурация Docker Compose валидна"
    else
        warning "Не удалось проверить конфигурацию Docker Compose"
    fi
}

# Показ итоговой информации
show_summary() {
    header
    echo -e "${GREEN}🎉 НАСТРОЙКА ЗАВЕРШЕНА!${NC}"
    header
    echo ""
    echo -e "${CYAN}Следующие шаги:${NC}"
    echo ""
    echo -e "1. ${YELLOW}Отредактируйте файл .env${NC}"
    echo -e "   nano .env"
    echo ""
    echo -e "2. ${YELLOW}Запустите Gitea${NC}"
    echo -e "   ./scripts/run.sh start"
    echo ""
    echo -e "3. ${YELLOW}Откройте в браузере${NC}"
    echo -e "   https://ваш-домен"
    echo ""
    echo -e "${CYAN}Основные команды управления:${NC}"
    echo -e "  ${GREEN}./scripts/run.sh start${NC}    - Запустить Gitea"
    echo -e "  ${GREEN}./scripts/run.sh stop${NC}     - Остановить Gitea"
    echo -e "  ${GREEN}./scripts/run.sh status${NC}   - Показать статус"
    echo -e "  ${GREEN}./scripts/run.sh backup${NC}   - Создать бэкап"
    echo -e "  ${GREEN}gitea-manage${NC}              - Если создан симлинк"
    echo ""
    echo -e "${CYAN}Директории проекта:${NC}"
    echo -e "  ${BLUE}data/${NC}          - Данные Gitea"
    echo -e "  ${BLUE}postgres_data/${NC} - Данные PostgreSQL"
    echo -e "  ${BLUE}backups/${NC}       - Резервные копии"
    echo -e "  ${BLUE}scripts/${NC}       - Скрипты управления"
    echo ""
    
    # Проверяем, редактировался ли .env
    if [ -f ".env" ] && grep -q "CHANGE_ME" ".env"; then
        echo -e "${RED}⚠️  ВНИМАНИЕ: Нужно изменить пароли в .env!${NC}"
        echo ""
    fi
    
    header
}

# ======================================
# ОСНОВНАЯ ЛОГИКА
# ======================================

main() {
    clear
    header
    echo -e "${CYAN}   СКРИПТ НАСТРОЙКИ GITEA   ${NC}"
    header
    
    echo -e "Директория проекта: ${YELLOW}$PROJECT_DIR${NC}"
    echo ""
    
    # Проверяем, запущен ли скрипт из правильной директории
    if [ ! -f ".env_example" ] && [ ! -f "docker-compose.yml" ]; then
        error "Скрипт должен запускаться из директории с проектом Gitea"
        echo "Перейдите в директорию проекта и запустите снова:"
        echo "  cd /путь/к/gitea"
        echo "  ./setup.sh"
        exit 1
    fi
    
    # Выполняем шаги настройки
    check_dependencies
    echo ""
    
    create_directories
    echo ""
    
    setup_env_file
    echo ""
    
    setup_permissions
    echo ""
    
    check_compose_config
    echo ""
    
    create_symlink
    echo ""
    
    show_summary
    
    # Запись в лог
    echo "$(date): Настройка выполнена в $PROJECT_DIR" >> setup.log
}

# Запуск основной функции
main