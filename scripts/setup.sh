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
PROJECT_ROOT="$SCRIPT_DIR"  # setup.sh находится в корне проекта

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
    
    # Основные директории (относительно корня проекта)
    DIRS=("scripts" "backups" "data" "postgres_data")
    
    for dir in "${DIRS[@]}"; do
        local full_path="$PROJECT_ROOT/$dir"
        if [ ! -d "$full_path" ]; then
            mkdir -p "$full_path"
            success "  Создана директория: $dir"
        else
            info "  Директория уже существует: $dir"
        fi
    done
    
    # Даем правильные права на scripts
    if [ -d "$PROJECT_ROOT/scripts" ]; then
        chmod +x "$PROJECT_ROOT/scripts/"*.sh 2>/dev/null || true
    fi
    
    success "Структура директорий создана"
}

# Копирование .env файла
setup_env_file() {
    info "Настройка файла окружения..."
    
    local env_file="$PROJECT_ROOT/.env"
    local env_example="$PROJECT_ROOT/.env_example"
    
    if [ ! -f "$env_file" ]; then
        if [ -f "$env_example" ]; then
            cp "$env_example" "$env_file"
            success "Создан файл .env из .env_example"
            
            # Обновляем PROJECT_DIR в .env
            sed -i "s|PROJECT_DIR=.*|PROJECT_DIR=\"$PROJECT_ROOT\"|g" "$env_file"
            
            warning "⚠️  ОБЯЗАТЕЛЬНО отредактируйте файл .env!"
            warning "  nano $env_file"
            echo ""
            warning "Замените:"
            warning "  - DOMAIN_NAME на ваш домен"
            warning "  - POSTGRES_PASSWORD на надежный пароль"
            warning "  - GITEA_DB_PASSWORD на надежный пароль"
            echo ""
            info "Текущий PROJECT_DIR установлен в: $PROJECT_ROOT"
        else
            error "Файл .env_example не найден в $PROJECT_ROOT!"
            exit 1
        fi
    else
        info "Файл .env уже существует"
        
        # Обновляем PROJECT_DIR в существующем .env
        if grep -q "PROJECT_DIR=" "$env_file"; then
            sed -i "s|PROJECT_DIR=.*|PROJECT_DIR=\"$PROJECT_ROOT\"|g" "$env_file"
            info "Обновлен PROJECT_DIR в .env: $PROJECT_ROOT"
        fi
    fi
}

# Настройка прав доступа
setup_permissions() {
    info "Настройка прав доступа..."
    
    # Права на данные Gitea (UID 1000)
    local data_dir="$PROJECT_ROOT/data"
    if [ -d "$data_dir" ]; then
        sudo chown -R 1000:1000 "$data_dir" 2>/dev/null && \
            success "Права установлены для data/ (UID 1000)" || \
            warning "Не удалось изменить владельца data/, возможно нужно sudo"
    else
        info "Директория data/ не существует, права не настроены"
    fi
    
    # Права на данные PostgreSQL (UID 999)
    local postgres_dir="$PROJECT_ROOT/postgres_data"
    if [ -d "$postgres_dir" ]; then
        sudo chown -R 999:999 "$postgres_dir" 2>/dev/null && \
            success "Права установлены для postgres_data/ (UID 999)" || \
            warning "Не удалось изменить владельца postgres_data/, возможно нужно sudo"
    else
        info "Директория postgres_data/ не существует, права не настроены"
    fi
    
    # Права на скрипты
    local scripts_dir="$PROJECT_ROOT/scripts"
    if [ -d "$scripts_dir" ]; then
        chmod +x "$scripts_dir/"*.sh 2>/dev/null && success "Права на скрипты установлены"
    fi
}

# Создание симлинка для удобства
create_symlink() {
    info "Создание симлинка для управления..."
    
    local run_script="$PROJECT_ROOT/scripts/run.sh"
    
    if [ -f "$run_script" ]; then
        # Проверяем, существует ли уже симлинк
        if [ -L "/usr/local/bin/gitea-manage" ]; then
            info "Симлинк уже существует"
            local current_target=$(readlink -f "/usr/local/bin/gitea-manage")
            if [ "$current_target" = "$run_script" ]; then
                success "Симлинк уже указывает на правильный файл: $run_script"
            else
                warning "Симлинк указывает на другой файл: $current_target"
                read -p "Заменить? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    sudo rm -f "/usr/local/bin/gitea-manage"
                else
                    info "Симлинк не изменен"
                    return
                fi
            fi
        fi
        
        # Пробуем создать симлинк
        if sudo ln -sf "$run_script" "/usr/local/bin/gitea-manage" 2>/dev/null; then
            success "Создан симлинк: gitea-manage → $run_script"
            info "Теперь можно использовать команду: gitea-manage"
            info "Пример: gitea-manage status"
        else
            warning "Не удалось создать симлинк в /usr/local/bin"
            echo ""
            info "Возможные причины:"
            info "  1. Нет прав sudo"
            info "  2. Директория /usr/local/bin недоступна"
            echo ""
            info "Можно создать симлинк вручную:"
            echo -e "  ${YELLOW}sudo ln -s \"$run_script\" /usr/local/bin/gitea-manage${NC}"
            echo ""
            info "Или использовать альтернативный путь:"
            echo -e "  ${YELLOW}ln -s \"$run_script\" ~/.local/bin/gitea-manage${NC}"
        fi
    else
        warning "Файл run.sh не найден: $run_script"
        warning "Симлинк не создан"
    fi
}

# Проверка конфигурации Docker Compose
check_compose_config() {
    info "Проверка конфигурации Docker Compose..."
    
    local compose_file="$PROJECT_ROOT/docker-compose.yml"
    
    if [ ! -f "$compose_file" ]; then
        error "Файл docker-compose.yml не найден: $compose_file"
        exit 1
    fi
    
    # Проверяем синтаксис docker-compose.yml
    cd "$PROJECT_ROOT"
    
    if command -v docker-compose &> /dev/null; then
        if docker-compose config -q; then
            success "Конфигурация Docker Compose валидна"
        else
            error "Ошибка в конфигурации Docker Compose"
            exit 1
        fi
    elif docker compose version &> /dev/null; then
        if docker compose config -q; then
            success "Конфигурация Docker Compose валидна"
        else
            error "Ошибка в конфигурации Docker Compose"
            exit 1
        fi
    else
        warning "Не удалось проверить конфигурацию Docker Compose (команда не найдена)"
    fi
    
    cd - > /dev/null
}

# Показ итоговой информации
show_summary() {
    # Загружаем .env для отображения актуальных данных
    local env_file="$PROJECT_ROOT/.env"
    local domain_name="не установлен"
    local ssh_port="2224"
    
    if [ -f "$env_file" ]; then
        if grep -q "DOMAIN_NAME=" "$env_file"; then
            domain_name=$(grep "DOMAIN_NAME=" "$env_file" | cut -d'=' -f2 | tr -d '"')
        fi
        if grep -q "SSH_PORT=" "$env_file"; then
            ssh_port=$(grep "SSH_PORT=" "$env_file" | cut -d'=' -f2 | tr -d '"')
        fi
    fi
    
    header
    echo -e "${GREEN}🎉 НАСТРОЙКА ЗАВЕРШЕНА!${NC}"
    header
    echo ""
    echo -e "${CYAN}Следующие шаги:${NC}"
    echo ""
    
    # Проверяем, редактировался ли .env
    if [ -f "$env_file" ] && (grep -q "CHANGE_ME" "$env_file" || grep -q "your-domain" "$env_file"); then
        echo -e "1. ${YELLOW}ОБЯЗАТЕЛЬНО отредактируйте файл .env${NC}"
        echo -e "   nano $env_file"
        echo -e "   Замените CHANGE_ME и your-domain на реальные значения!"
        echo ""
    fi
    
    echo -e "2. ${YELLOW}Запустите Gitea${NC}"
    echo -e "   ./scripts/run.sh start"
    echo ""
    echo -e "3. ${YELLOW}Откройте в браузере${NC}"
    echo -e "   https://${domain_name}"
    echo -e "   SSH: git@${domain_name}:${ssh_port}"
    echo ""
    echo -e "${CYAN}Основные команды управления:${NC}"
    echo -e "  ${GREEN}./scripts/run.sh start${NC}    - Запустить Gitea"
    echo -e "  ${GREEN}./scripts/run.sh stop${NC}     - Остановить Gitea"
    echo -e "  ${GREEN}./scripts/run.sh status${NC}   - Показать статус"
    echo -e "  ${GREEN}./scripts/run.sh backup${NC}   - Создать бэкап"
    
    if [ -L "/usr/local/bin/gitea-manage" ] || [ -f "/usr/local/bin/gitea-manage" ]; then
        echo -e "  ${GREEN}gitea-manage${NC}              - Команда управления (симлинк)"
    fi
    
    echo ""
    echo -e "${CYAN}Директории проекта:${NC}"
    echo -e "  ${BLUE}$PROJECT_ROOT/${NC}"
    echo -e "    ├── data/          - Данные Gitea"
    echo -e "    ├── postgres_data/ - Данные PostgreSQL"
    echo -e "    ├── backups/       - Резервные копии"
    echo -e "    ├── scripts/       - Скрипты управления"
    echo -e "    ├── .env           - Конфигурация"
    echo -e "    └── docker-compose.yml"
    echo ""
    
    # Предупреждение о незаполненном .env
    if [ -f "$env_file" ] && (grep -q "CHANGE_ME" "$env_file" || grep -q "your-domain" "$env_file"); then
        echo -e "${RED}════════════════════════════════════════════════════${NC}"
        echo -e "${RED}⚠️  ВНИМАНИЕ: Нужно изменить пароли в .env!${NC}"
        echo -e "${RED}════════════════════════════════════════════════════${NC}"
        echo ""
    fi
    
    # Проверяем, доступны ли команды
    echo -e "${CYAN}Проверка доступности:${NC}"
    if command -v docker &> /dev/null; then
        echo -e "  ${GREEN}✓ Docker установлен${NC}"
    else
        echo -e "  ${RED}✗ Docker не установлен${NC}"
    fi
    
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        echo -e "  ${GREEN}✓ Docker Compose доступен${NC}"
    else
        echo -e "  ${RED}✗ Docker Compose не доступен${NC}"
    fi
    
    if [ -L "/usr/local/bin/gitea-manage" ]; then
        echo -e "  ${GREEN}✓ Симлинк создан${NC}"
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
    
    echo -e "Директория проекта: ${YELLOW}$PROJECT_ROOT${NC}"
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
    echo "$(date): Настройка выполнена в $PROJECT_ROOT" >> "$PROJECT_ROOT/setup.log"
}

# Запуск основной функции
main