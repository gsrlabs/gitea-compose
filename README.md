# 🦊 Gitea Self-Hosted Deployment

Простая и надежная конфигурация для развертывания Gitea на собственном сервере с использованием Docker Compose.

## ✨ Особенности

- ✅ **Простота установки** — одна команда для запуска
- ✅ **PostgreSQL** — надежная база данных вместо SQLite
- ✅ **Автоматические бэкапы** — встроенная система резервного копирования
- ✅ **Reverse Proxy готовность** — предварительно настроена работа через Caddy/Nginx
- ✅ **Управление через CLI** — удобные скрипты для управления
- ✅ **Поддержка обновлений** — простое обновление до новых версий

### Структура

```
gitea/
├── docker-compose.yml    # Docker конфигурация
├── .env                  # Конфигурация (создается из .env_example)
├── .env_example          # Шаблон конфигурации
├── setup.sh              # Скрипт начальной настройки
├── README.md             # Эта документация
├── scripts/              # Скрипты управления
│   ├── run.sh            # Основной скрипт
│   ├── backup.sh         # Резервное копирование
│   └── restore.sh        # Восстановление
├── data/                 # Данные Gitea (создается)
├── postgres_data/        # Данные PostgreSQL (создается)
└── backups/              # Архивы бэкапов (создается)
```

## 🚀 Быстрый старт

### Требования

- Ubuntu/Debian сервер
- Docker и Docker Compose
- Открытые порты: 80, 443, 2224 (SSH)

## Установка и запуск Gitea

```bash
# 1. Клонируем репозиторий
cd /home/your/directory/ # замените на вашу директорию
git clone https://github.com/gsrlabs/gitea-compose.git gitea
cd gitea

# 2. Настраиваем
chmod +x setup.sh
./setup.sh

# 3. Редактируем .env
nano .env
```

Основные настройки хранятся в `.env`:

```bash
# Доменное имя
DOMAIN_NAME="gitea.your-domain.com"

# Пароли
POSTGRES_PASSWORD="STRONG_PASSWORD"
GITEA_DB_PASSWORD="STRONG_PASSWORD"

# Пути к данным
PROJECT_DIR="/home/your/directory/gitea"
```

> Остальные настройки можно не менять!

Запуск Gitea:

```bash
# 4. Запускаем Gitea
./scripts/run.sh start

# 5. Проверяем
./scripts/run.sh status
```

### Сетевая архитектура

```
Интернет → 80/443 → Caddy/Nginx → Gitea:3000
             ↓
          2224 → Gitea SSH → 22
```

**Пример настроки Caddy:**

```nginx
gitea.your-domain.com {
    reverse_proxy 127.0.0.1:3000
}
```

## 📚 Использование

### Управление сервером

```bash
./scripts/run.sh start      # Запустить
./scripts/run.sh stop       # Остановить
./scripts/run.sh restart    # Перезапустить
./scripts/run.sh status     # Статус
./scripts/run.sh logs       # Просмотр логов
./scripts/run.sh update     # Обновить Gitea
./scripts/run.sh backup     # Создать бэкап
./scripts/run.sh restore    # Восстановить данные
```

**Вместо ./scripts/run.sh можно использовать команду (вне директории проекта):**

```
gitea-manage
```

### Резервное копирование

```bash
# Создать бэкап вручную
./scripts/run.sh backup

# Автоматические бэкапы (добавьте в cron)
0 3 * * * cd /home/your/directory/gitea && ./scripts/run.sh backup
```

### Обновление Gitea

```bash
./scripts/run.sh update
```

Скрипт обновит образы Docker и пересоздаст контейнеры с сохранением данных.

## 🏃Gitea Act Runner

Для настройки CI/CD контура необходимо настроить Gitea Act Runner, для этого вам нужно перейти по ссылке ниже:
https://github.com/gsrlabs/gitea-runner

## 📦 Container Registry - Работа с Docker образами

### Аутентификация:

```bash
# Вход в реестр контейнеров Gitea
docker login gitea.your-domain.com

# Используйте:
# - Логин: ваш username в Gitea
# - Пароль: ваш пароль ИЛИ Personal Access Token (если включена 2FA)
```

### Формат образов:

```bash
gitea.your-domain.com/{user}/{image-name}:{teg}
```

Примеры корректных имен:

- gitea.your-domain.com/user/my-app:latest
- gitea.your-domain.com/user/backend-api:v1.2.3
- gitea.your-domain.com/myorg/nginx:stable

### 📤 Push образа в Registry

**Сборка образа с правильным именем:**

```bash
# Из директории с Dockerfile
docker build -t gitea.your-domain.com/user/my-app:latest .

# Или тегирование существующего образа
docker tag my-local-image:latest gitea.your-domain.com/user/my-app:latest
```

**Отправка образа:**

```bash
docker push gitea.your-domain.com/user/my-app:latest
```

### 📥 Pull образа из Registry

```bash
# Загрузка образа
docker pull gitea.your-domain.com/user/my-app:latest

# Использование в docker-compose.yml
# services:
#   app:
#     image: gitea.your-domain.com/user/my-app:latest
```

### 🗑️ Удаление образов

```bash
# Удаление локального образа
docker rmi gitea.your-domain.com/user/my-app:latest

# Удаление из registry (через интерфейс Gitea)
# Перейдите в Package → выберите образ → Delete
```

## 🔐 Безопасность

### Рекомендации после установки

1. **Смените пароль администратора** в веб-интерфейсе
2. **Включите 2FA** для учетных записей администраторов
3. **Настройте firewall**:

```bash
sudo apt install -y nftables

sudo nft add table inet filter
sudo nft 'add chain inet filter input { type filter hook input priority 0; policy drop; }'

sudo nft add rule inet filter input iif lo accept
sudo nft add rule inet filter input ct state established,related accept
sudo nft add rule inet filter input tcp dport 2224 accept
sudo nft add rule inet filter input tcp dport 80 accept
sudo nft add rule inet filter input tcp dport 443 accept

sudo nft list ruleset | sudo tee /etc/nftables.conf

sudo systemctl enable --now nftables
```

Проверить результат:
```bash
sudo nft list ruleset
```
И проверить, что SSH действительно слушает 2224:
```bash
sudo ss -lntp | grep ':2224'
```
Не закрывай текущую SSH-сессию, пока с другого терминала не проверишь, что подключение на 2224 работает.

4. **Регулярно обновляйте** систему и Gitea

### Правка доступа к файлам
```bash
# Данные Gitea
sudo chown -R 1000:1000 data/

# Данные PostgreSQL
sudo chown -R 999:999 postgres_data/
````

## 🔧 Устранение неисправностей

### Gitea не запускается

```bash
# Проверьте логи
./scripts/run.sh logs

# Проверьте права на файлы
sudo chown -R 1000:1000 data/
sudo chown -R 999:999 postgres_data/
```

### Нет доступа по SSH

1. Проверьте, что порт 2224 открыт на роутере
2. Проверьте firewall:
   ```bash
   sudo ufw status
   ```

### Не работает HTTPS

Убедитесь, что reverse proxy (Caddy/Nginx) правильно настроен и сертификаты получены.

## 📄 Лицензия

MIT

## 🤝 Вклад в проект

Pull requests приветствуются! Для серьезных изменений, пожалуйста, откройте issue сначала для обсуждения.

## 📞 Поддержка

- Issues: https://github.com/gsrlabs/gitea-compose/issues
- Документация Gitea: https://docs.gitea.io
