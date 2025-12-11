#!/bin/bash

# ======================================
# КОНФИГУРАЦИЯ
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

# Загрузка конфигурации
load_config() {
    if [ -f "../.env" ]; then
        set -a
        source ../.env
        set +a
    else
        error "Файл .env не найден!"
        exit 1
    fi
}

load_config

# Переменные (на основе .env)
BACKUP_PATH="${BACKUP_DIR}"
PROJECT_NAME="${PROJECT_NAME:-gitea}"
DATA_DIR="${DATA_DIR}"
POSTGRES_DATA_DIR="${POSTGRES_DATA_DIR}"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

# ======================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ======================================

# Показать доступные бэкапы
show_available_backups() {
    info "📂 Доступные бэкапы в $BACKUP_DIR:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Директория бэкапов не существует!"
        exit 1
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f 2>/dev/null | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        warning "Нет доступных бэкапов!"
        return 1
    fi
    
    local count=0
    for backup in "${backups[@]}"; do
        ((count++))
        backup_name=$(basename "$backup")
        backup_date=$(echo "$backup_name" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "неизвестно")
        backup_size=$(du -h "$backup" | cut -f1)
        
        if [ -n "$backup_date" ]; then
            formatted_date=$(echo "$backup_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1.\2.\3 \4:\5:\6/')
        else
            formatted_date="неизвестно"
        fi
        
        echo -e "  ${YELLOW}$count.${NC} $backup_name"
        echo -e "     📅 $formatted_date  📏 $backup_size"
        echo ""
        
        if [ $count -ge 10 ]; then
            info "... и ещё $((${#backups[@]} - 10)) бэкапов"
            break
        fi
    done
    
    return 0
}

# Создание резервной копии текущего состояния
create_pre_restore_backup() {
    info "🔄 Создание резервной копии текущего состояния..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local temp_backup_dir="/tmp/${PROJECT_NAME}_pre_restore_${timestamp}"
    
    mkdir -p "$temp_backup_dir"
    
    # Копируем текущие данные Gitea
    if [ -d "$DATA_DIR" ]; then
        cp -rp "$DATA_DIR" "$temp_backup_dir/gitea_data_current" 2>/dev/null || warning "Не удалось скопировать данные Gitea"
    fi
    
    # Копируем текущие данные PostgreSQL
    if [ -d "$POSTGRES_DATA_DIR" ]; then
        cp -rp "$POSTGRES_DATA_DIR" "$temp_backup_dir/postgres_data_current" 2>/dev/null || warning "Не удалось скопировать данные PostgreSQL"
    fi
    
    # Копируем конфигурацию
    cp -p ../docker-compose.yml "$temp_backup_dir/" 2>/dev/null
    cp -p ../.env "$temp_backup_dir/" 2>/dev/null
    
    success "Текущее состояние сохранено в: $temp_backup_dir"
    echo "$temp_backup_dir"
}

# Проверка архива бэкапа
validate_backup_archive() {
    local archive="$1"
    
    info "🔍 Проверка архива $archive..."
    
    if [ ! -f "$archive" ]; then
        error "Файл не найден: $archive"
        return 1
    fi
    
    # Проверяем, что это tar.gz архив
    if ! file "$archive" | grep -q "gzip compressed data"; then
        error "Файл не является gzip архивом: $archive"
        return 1
    fi
    
    # Проверяем содержимое архива
    if ! tar -tzf "$archive" > /dev/null 2>&1; then
        error "Архив поврежден или имеет неверный формат"
        return 1
    fi
    
    # Проверяем наличие необходимых директорий
    local archive_content=$(tar -tzf "$archive" | head -20)
    
    if ! echo "$archive_content" | grep -q "backup.info" && \
       ! echo "$archive_content" | grep -q "gitea_data" && \
       ! echo "$archive_content" | grep -q "postgres_data"; then
        warning "Архив может не содержать всех необходимых данных"
    fi
    
    success "Архив проверен"
    return 0
}

# Извлечение архива
extract_backup() {
    local archive="$1"
    local extract_dir="$2"
    
    info "📦 Извлечение архива..."
    
    # Создаем временную директорию для извлечения
    local temp_dir=$(mktemp -d)
    
    # Извлекаем архив
    if ! tar -xzf "$archive" -C "$temp_dir"; then
        error "Ошибка при извлечении архива"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Проверяем, что извлечение прошло успешно
    local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "${PROJECT_NAME}_backup_*" | head -1)
    
    if [ -z "$extracted_dir" ]; then
        error "Не удалось найти данные в архиве"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Копируем извлеченную директорию в целевую
    cp -rp "$extracted_dir" "$extract_dir"
    
    # Очищаем временную директорию
    rm -rf "$temp_dir"
    
    success "Архив извлечен в: $extract_dir"
    return 0
}

# Восстановление данных
restore_data() {
    local backup_dir="$1"
    
    info "🔄 Восстановление данных..."
    
    # 1. Останавливаем контейнеры
    info "Остановка контейнеров..."
    cd "$(dirname "$0")/.." && $COMPOSE_CMD down
    
    # 2. Удаляем текущие данные (с созданием бэкапа)
    if [ -d "$DATA_DIR" ]; then
        info "Резервное копирование текущих данных Gitea..."
        local gitea_backup="${DATA_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$DATA_DIR" "$gitea_backup"
        success "Текущие данные Gitea сохранены в: $gitea_backup"
    fi
    
    if [ -d "$POSTGRES_DATA_DIR" ]; then
        info "Резервное копирование текущих данных PostgreSQL..."
        local postgres_backup="${POSTGRES_DATA_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$POSTGRES_DATA_DIR" "$postgres_backup"
        success "Текущие данные PostgreSQL сохранены в: $postgres_backup"
    fi
    
    # 3. Восстанавливаем данные из бэкапа
    info "Копирование данных из бэкапа..."
    
    # Восстанавливаем данные Gitea
    if [ -d "$backup_dir/gitea_data" ]; then
        cp -rp "$backup_dir/gitea_data" "$DATA_DIR"
        success "Данные Gitea восстановлены"
    else
        warning "В бэкапе отсутствуют данные Gitea"
    fi
    
    # Восстанавливаем данные PostgreSQL
    if [ -d "$backup_dir/postgres_data" ]; then
        cp -rp "$backup_dir/postgres_data" "$POSTGRES_DATA_DIR"
        success "Данные PostgreSQL восстановлены"
    else
        warning "В бэкапе отсутствуют данные PostgreSQL"
    fi
    
    # 4. Устанавливаем правильные права
    info "Установка прав доступа..."
    sudo chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || warning "Не удалось изменить права для Gitea данных"
    sudo chown -R 999:999 "$POSTGRES_DATA_DIR" 2>/dev/null || warning "Не удалось изменить права для PostgreSQL данных"
    
    # 5. Запускаем контейнеры
    info "Запуск контейнеров..."
    $COMPOSE_CMD up -d
    
    success "Данные восстановлены"
    return 0
}

# Проверка восстановления
verify_restoration() {
    info "🔍 Проверка восстановления..."
    
    sleep 10  # Даем время контейнерам запуститься
    
    # Проверяем статус контейнеров
    local status=$($COMPOSE_CMD ps --services --filter "status=running" | wc -l)
    
    if [ "$status" -ge 2 ]; then
        success "Все контейнеры запущены"
    else
        warning "Не все контейнеры запущены"
        $COMPOSE_CMD ps
    fi
    
    # Проверяем доступность Gitea
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; then
        success "Gitea доступен"
    else
        warning "Gitea может быть недоступен"
    fi
}

# ======================================
# ОСНОВНАЯ ЛОГИКА
# ======================================

main() {
    header
    echo -e "${CYAN}   ВОССТАНОВЛЕНИЕ GITEA ИЗ БЭКАПА   ${NC}"
    header
    
    # Определяем файл бэкапа
    local backup_file="$1"
    
    # Если файл не указан, показываем список
    if [ -z "$backup_file" ]; then
        error "Не указан файл бэкапа!"
        echo ""
        info "Использование:"
        echo -e "  ${YELLOW}./restore.sh <файл_бэкапа>${NC}"
        echo -e "  ${YELLOW}./restore.sh latest${NC}          - восстановить последний бэкап"
        echo ""
        
        if show_available_backups; then
            echo ""
            LATEST_BACKUP=$(find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
            if [ -n "$LATEST_BACKUP" ]; then
                info "Пример для восстановления последнего бэкапа:"
                echo -e "  ${YELLOW}./restore.sh latest${NC}"
                echo -e "  ${YELLOW}./restore.sh $(basename "$LATEST_BACKUP")${NC}"
            fi
        fi
        
        exit 1
    fi
    
    # Обработка ключевого слова "latest"
    if [ "$backup_file" = "latest" ]; then
        backup_file=$(find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        
        if [ -z "$backup_file" ]; then
            error "Не найдены бэкапы!"
            exit 1
        fi
        
        info "Выбран последний бэкап: $(basename "$backup_file")"
    fi
    
    # Добавляем путь к директории бэкапов, если указано только имя файла
    if [[ "$backup_file" != /* ]] && [[ "$backup_file" != "$BACKUP_DIR"/* ]]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi
    
    # Проверяем существование файла
    if [ ! -f "$backup_file" ]; then
        error "Файл бэкапа не найден: $backup_file"
        
        # Показываем похожие файлы
        local similar_files=$(find "$BACKUP_DIR" -name "*$(basename "$backup_file")*" -type f 2>/dev/null | head -5)
        if [ -n "$similar_files" ]; then
            info "Возможно, вы имели в виду:"
            echo "$similar_files"
        fi
        
        exit 1
    fi
    
    # Предупреждение о опасности
    echo ""
    warning "╔══════════════════════════════════════════════════════════╗"
    warning "║                     ВНИМАНИЕ! ОПАСНО!                   ║"
    warning "║   Все текущие данные Gitea и PostgreSQL будут заменены! ║"
    warning "║       Убедитесь, что у вас есть свежий бэкап!           ║"
    warning "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    echo -e "${YELLOW}Бэкап для восстановления:${NC} $(basename "$backup_file")"
    echo -e "${YELLOW}Размер:${NC} $(du -h "$backup_file" | cut -f1)"
    echo ""
    
    read -p "Вы уверены, что хотите продолжить? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Восстановление отменено"
        exit 0
    fi
    
    # Проверяем права
    if [ "$EUID" -ne 0 ]; then
        warning "Для восстановления требуются права root"
        info "Перезапустите скрипт с sudo:"
        echo -e "  ${YELLOW}sudo ./restore.sh $(basename "$backup_file")${NC}"
        exit 1
    fi
    
    # Начинаем процесс восстановления
    local start_time=$(date +%s)
    
    # 1. Проверяем архив
    if ! validate_backup_archive "$backup_file"; then
        exit 1
    fi
    
    # 2. Создаем бэкап текущего состояния
    local pre_restore_backup=$(create_pre_restore_backup)
    
    # 3. Создаем временную директорию для извлечения
    local extract_dir=$(mktemp -d)
    
    # 4. Извлекаем архив
    if ! extract_backup "$backup_file" "$extract_dir"; then
        error "Ошибка при извлечении архива"
        rm -rf "$extract_dir"
        exit 1
    fi
    
    # 5. Восстанавливаем данные
    if ! restore_data "$extract_dir"; then
        error "Ошибка при восстановлении данных"
        
        # Пытаемся восстановить из pre-restore бэкапа
        warning "Попытка восстановления из резервной копии..."
        if [ -n "$pre_restore_backup" ] && [ -d "$pre_restore_backup" ]; then
            restore_data "$pre_restore_backup"
        fi
        
        rm -rf "$extract_dir"
        exit 1
    fi
    
    # 6. Очищаем временные файлы
    rm -rf "$extract_dir"
    
    # 7. Проверяем восстановление
    verify_restoration
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Итоговый отчет
    header
    success "🎉 ВОССТАНОВЛЕНИЕ УСПЕШНО ЗАВЕРШЕНО!"
    header
    echo ""
    echo -e "${GREEN}📊 Статистика восстановления:${NC}"
    echo -e "  📁 Бэкап: $(basename "$backup_file")"
    echo -e "  📏 Размер: $(du -h "$backup_file" | cut -f1)"
    echo -e "  ⏱️  Время: ${duration} секунд"
    echo -e "  💾 Pre-restore backup: $pre_restore_backup"
    echo ""
    echo -e "${YELLOW}🔗 Gitea должен быть доступен по адресу:${NC}"
    echo -e "  🌐 https://${DOMAIN_NAME}"
    echo -e "  🔑 SSH: git@${DOMAIN_NAME}:${SSH_PORT}"
    echo ""
    echo -e "${BLUE}📋 Рекомендуется:${NC}"
    echo -e "  1. Проверить доступность Gitea в браузере"
    echo -e "  2. Проверить SSH подключение"
    echo -e "  3. Удалить старые резервные копии через 24 часа"
    echo ""
    
    # Показываем статус контейнеров
    info "Текущий статус контейнеров:"
    $COMPOSE_CMD ps
    echo ""
}

# Запуск основной функции
main "$@"