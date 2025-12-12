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

# Определяем пути
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Загрузка конфигурации
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    error "Файл .env не найден: $ENV_FILE"
    exit 1
fi

# Переменные бэкапа
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${PROJECT_NAME}_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# ======================================
# ОСНОВНАЯ ЛОГИКА
# ======================================

main() {
    header
    info "🔄 СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ $PROJECT_NAME"
    header
    
    # Проверяем директории
    info "Проверка директорий..."
    
    if [ ! -d "$DATA_DIR" ]; then
        error "Директория данных Gitea не найдена: $DATA_DIR"
        return 1
    fi
    
    if [ ! -d "$POSTGRES_DATA_DIR" ]; then
        error "Директория данных PostgreSQL не найдена: $POSTGRES_DATA_DIR"
        return 1
    fi
    
    # Создание директории для бэкапов
    mkdir -p "$BACKUP_DIR"
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Не удалось создать директорию для бэкапов: $BACKUP_DIR"
        return 1
    fi
    
    success "Директории проверены"
    
    # Создаем бэкап
    info "Создание резервной копии в: $BACKUP_PATH"
    
    # Создаем временную директорию для бэкапа
    mkdir -p "$BACKUP_PATH"
    
    # 1. Бэкап данных Gitea
    if [ "$BACKUP_GITEA" = "true" ]; then
        info "Копирование данных Gitea..."
        cp -rp "$DATA_DIR" "$BACKUP_PATH/gitea_data"
        if [ $? -eq 0 ]; then
            success "Данные Gitea скопированы ($(du -sh "$DATA_DIR" | cut -f1))"
        else
            error "Ошибка при копировании данных Gitea"
            return 1
        fi
    fi
    
    # 2. Бэкап данных PostgreSQL
    if [ "$BACKUP_POSTGRES" = "true" ]; then
        info "Копирование данных PostgreSQL..."
        cp -rp "$POSTGRES_DATA_DIR" "$BACKUP_PATH/postgres_data"
        if [ $? -eq 0 ]; then
            success "Данные PostgreSQL скопированы ($(du -sh "$POSTGRES_DATA_DIR" | cut -f1))"
        else
            error "Ошибка при копировании данных PostgreSQL"
            return 1
        fi
    fi
    
    # 3. Бэкап docker-compose.yml и .env
    info "Копирование конфигурации..."
    cp -p "$PROJECT_ROOT/docker-compose.yml" "$BACKUP_PATH/"
    cp -p "$ENV_FILE" "$BACKUP_PATH/" 2>/dev/null || warning "Файл .env не скопирован (отсутствует)"
    
    # 4. Создаем информационный файл
    cat > "$BACKUP_PATH/backup.info" << EOF
Резервная копия $PROJECT_NAME
Дата создания: $(date)
Версия Gitea: $(docker inspect --format='{{.Config.Image}}' gitea 2>/dev/null || echo "неизвестно")
Директории:
  - Gitea данные: $DATA_DIR
  - PostgreSQL: $POSTGRES_DATA_DIR
Размеры:
  - Gitea: $(du -sh "$DATA_DIR" 2>/dev/null | cut -f1 || echo "N/A")
  - PostgreSQL: $(du -sh "$POSTGRES_DATA_DIR" 2>/dev/null | cut -f1 || echo "N/A")
EOF
    
    success "Резервная копия создана"
    
    # Архивирование бэкапа
    info "Архивирование резервной копии..."
    
    cd "$BACKUP_DIR" || {
        error "Не удалось перейти в $BACKUP_DIR"
        return 1
    }
    
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    if [ $? -eq 0 ]; then
        ARCHIVE_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
        success "Архив создан: ${BACKUP_NAME}.tar.gz ($ARCHIVE_SIZE)"
        
        # Удаляем распакованную копию
        rm -rf "$BACKUP_NAME"
    else
        error "Ошибка при создании архива"
        return 1
    fi
    
    cd - > /dev/null || true
    
    # Очистка старых бэкапов
    if [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
        info "Очистка старых бэкапов (старше $BACKUP_RETENTION_DAYS дней)..."
        
        find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f -mtime +$BACKUP_RETENTION_DAYS | while read -r old_backup; do
            info "Удаление старого бэкапа: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
        
        success "Очистка завершена"
    else
        info "Хранение всех бэкапов (BACKUP_RETENTION_DAYS=0)"
    fi
    
    # Отчет о бэкапах
    header
    info "📊 ОТЧЕТ О РЕЗЕРВНОМ КОПИРОВАНИИ"
    header
    
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    
    if [ -f "$BACKUP_FILE" ]; then
        echo -e "  ${GREEN}✓ Создан новый бэкап:${NC}"
        echo -e "    📁 Файл: $(basename "$BACKUP_FILE")"
        echo -e "    📏 Размер: $(du -h "$BACKUP_FILE" | cut -f1)"
        echo -e "    📅 Дата: $(date +"%d.%m.%Y %H:%M:%S")"
        echo -e "    📍 Путь: $BACKUP_FILE"
    else
        error "Бэкап не был создан!"
    fi
    
    echo ""
    
    # Список всех бэкапов
    BACKUP_COUNT=$(find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        echo -e "  ${CYAN}📈 Всего бэкапов в системе: $BACKUP_COUNT${NC}"
        echo ""
        echo -e "  ${YELLOW}Последние 5 бэкапов:${NC}"
        find "$BACKUP_DIR" -name "${PROJECT_NAME}_backup_*.tar.gz" -type f -printf "%T@ %p\n" 2>/dev/null | \
            sort -nr | \
            head -5 | \
            cut -d' ' -f2- | \
            while read -r backup; do
                backup_name=$(basename "$backup")
                backup_date=$(date -r "$backup" +"%d.%m.%Y %H:%M")
                backup_size=$(du -h "$backup" | cut -f1)
                echo -e "    • $backup_name ($backup_size, $backup_date)"
            done
    else
        warning "В системе нет бэкапов!"
    fi
    
    # Использование диска
    echo ""
    if [ -d "$BACKUP_DIR" ]; then
        BACKUP_TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
        echo -e "  ${CYAN}💾 Общий размер бэкапов: $BACKUP_TOTAL_SIZE${NC}"
    fi
    
    header
    success "Резервное копирование завершено успешно!"
    echo ""
}

# Запуск основной функции
main