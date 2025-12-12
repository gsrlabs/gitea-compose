#!/bin/bash

# ======================================
# КОНФИГУРАЦИЯ
# ======================================

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

# Корректное определение пути, даже если запускается через симлинк
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done

SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Загрузка конфигурации
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    success "Конфигурация загружена из $ENV_FILE"
else
    error "Файл .env не найден: $ENV_FILE"
    exit 1
fi

run_compose() {
    cd "$PROJECT_ROOT" && $COMPOSE_CMD "$@"
}

BACKUP_PATH="${BACKUP_DIR}"
PROJECT_NAME="${PROJECT_NAME:-gitea}"

# ======================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ======================================

show_available_backups() {
    info "📂 Доступные бэкапы в $BACKUP_DIR:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Директория бэкапов не существует!"
        return 1
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        warning "Нет доступных бэкапов!"
        return 1
    fi
    
    local count=0
    for backup in "${backups[@]}"; do
        ((count++))
        backup_name=$(basename "$backup")
        backup_date=$(echo "$backup_name" | grep -oE '[0-9]{8}_[0-9]{6}')
        backup_size=$(du -h "$backup" | cut -f1)

        formatted_date=$(echo "$backup_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1.\2.\3 \4:\5:\6/')

        echo -e "  ${YELLOW}${count}.${NC} $backup_name"
        echo -e "     📅 $formatted_date  📏 $backup_size"
        echo ""
        if [ $count -ge 10 ]; then break; fi
    done

    return 0
}

validate_backup_archive() {
    local archive="$1"

    info "🔍 Проверка архива $archive..."

    if [ ! -f "$archive" ]; then
        error "Файл не найден: $archive"
        return 1
    fi

    if ! file "$archive" | grep -q "gzip compressed data"; then
        error "Файл не является gzip архивом"
        return 1
    fi

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        error "Архив поврежден"
        return 1
    fi

    success "Архив проверен"
    return 0
}

extract_backup() {
    local archive="$1"
    local extract_dir="$2"

    info "📦 Извлечение архива..."

    local temp_dir
    temp_dir=$(mktemp -d)

    if ! tar -xzf "$archive" -C "$temp_dir"; then
        error "Ошибка извлечения архива"
        rm -rf "$temp_dir"
        return 1
    fi

    local extracted_dir
    extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "${PROJECT_NAME}_backup_*" | head -1)

    if [ -z "$extracted_dir" ]; then
        error "Не найдены данные внутри архива"
        rm -rf "$temp_dir"
        return 1
    fi

    # Правильное извлечение (только содержимое!)
    cp -rp "$extracted_dir/"* "$extract_dir/"

    rm -rf "$temp_dir"

    success "Архив извлечен в: $extract_dir"
    return 0
}

restore_data() {
    local backup_dir="$1"

    info "🔄 Восстановление данных..."
    run_compose down

    info "Удаление текущих данных..."
    rm -rf "$DATA_DIR" "$POSTGRES_DATA_DIR"

    info "Копирование данных из бэкапа..."

    if [ -d "$backup_dir/gitea_data" ]; then
        cp -rp "$backup_dir/gitea_data" "$DATA_DIR"
        success "Данные Gitea восстановлены"
    else
        warning "Нет данных Gitea в бэкапе"
    fi

    if [ -d "$backup_dir/postgres_data" ]; then
        cp -rp "$backup_dir/postgres_data" "$POSTGRES_DATA_DIR"
        success "Данные PostgreSQL восстановлены"
    else
        warning "Нет данных PostgreSQL в бэкапе"
    fi

    info "Установка прав доступа..."
    chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || true
    chown -R 999:999 "$POSTGRES_DATA_DIR" 2>/dev/null || true

    run_compose up -d
    success "Данные восстановлены!"
}

verify_restoration() {
    info "🔍 Проверка восстановления..."

    sleep 10

    local running
    running=$(run_compose ps --services --filter "status=running" | wc -l)

    if [ "$running" -ge 2 ]; then
        success "Контейнеры успешно запущены"
    else
        warning "Не все контейнеры запущены"
    fi
}

# ======================================
# ОСНОВНАЯ ЛОГИКА
# ======================================

main() {
    header
    echo -e "${CYAN}   ВОССТАНОВЛЕНИЕ ИЗ БЭКАПА   ${NC}"
    header

    local backup_file="$1"

    if [ -z "$backup_file" ]; then
    error "Не указан файл бэкапа!"
    echo ""

    # Показываем список доступных
        if show_available_backups; then
            echo ""

        # Находим последний бэкап
            LATEST_BACKUP=$(find "$BACKUP_DIR" \
                -name "${PROJECT_NAME}_backup_*.tar.gz" \
                -type f -printf "%T@ %p\n" 2>/dev/null \
                | sort -nr | head -1 | cut -d' ' -f2-)

            if [ -n "$LATEST_BACKUP" ]; then
                info "Пример восстановления последнего бэкапа:"
                echo -e "  ${YELLOW}./restore.sh latest${NC}"
                echo -e "  ${YELLOW}./restore.sh $(basename "$LATEST_BACKUP")${NC}"
            else
                warning "Бэкапы не найдены!"
            fi
        fi

        exit 1
    fi


    if [ "$backup_file" = "latest" ]; then
        backup_file=$(find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2-)
        info "Выбран последний бэкап: $(basename "$backup_file")"
    fi

    if [[ "$backup_file" != /* ]]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi

    if [ ! -f "$backup_file" ]; then
        error "Бэкап не найден: $backup_file"
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        error "Нужны root-права"
        echo "Запустите: sudo ./scripts/restore.sh ..."
        exit 1
    fi

    validate_backup_archive "$backup_file" || exit 1

    local extract_dir
    extract_dir=$(mktemp -d)

    extract_backup "$backup_file" "$extract_dir" || exit 1

    restore_data "$extract_dir"

    rm -rf "$extract_dir"

    verify_restoration

    success "🎉 ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
}

main "$@"
