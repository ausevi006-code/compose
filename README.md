# TaskApi — CRUD API + PostgreSQL в Docker Compose

Контрольная точка «Compose». API на .NET 8 и база данных PostgreSQL 16 запускаются одной командой через Docker Compose. Данные хранятся в volume `db_data` и сохраняются после перезапуска.

```
docker compose up → API работает → данные сохраняются
```

## Сущность

**Задача** (`tasks`), связана с проектной темой «менеджер задач».

| Поле | Тип | Описание |
|---|---|---|
| `id` | int | первичный ключ, генерируется базой |
| `title` | string | название задачи, обязательно |
| `description` | string? | описание, необязательно |
| `isDone` | bool | выполнена ли задача |
| `createdAt` | datetime | дата создания, ставится базой |

## Структура проекта

```
.
├── Program.cs              # настройка API и CRUD endpoint
├── TaskRepository.cs       # SQL-запросы к PostgreSQL через Npgsql
├── Database.cs             # ожидание готовности БД и создание таблицы
├── TaskItem.cs             # модели задачи и тела запроса
├── TaskApi.csproj
├── Dockerfile              # сборка образа API
├── docker-compose.yml      # сервисы api и db, сеть, volume db_data
├── postman/                # Postman-коллекция с CRUD-запросами
├── scripts/check.sh        # автоматическая проверка (Linux/macOS/Git Bash)
├── scripts/check.ps1       # то же для Windows PowerShell
└── proof/                  # выводы ps, CRUD, перезапуска и логов
```

## Требования

- Docker Desktop или Docker Engine с Docker Compose v2 (`docker compose version`)
- curl или Postman для запросов

.NET SDK на компьютере не нужен: API собирается внутри Docker.

## Запуск

```bash
docker compose up --build
```

В фоне:

```bash
docker compose up -d --build
```

API: http://localhost:8080

## Проверка запуска

```bash
docker compose ps          # должны быть task-api и task-db (healthy)
docker compose logs api    # "Подключение к PostgreSQL установлено, таблица tasks готова"
docker compose logs db     # "database system is ready to accept connections"
```

## CRUD-запросы (curl)

| Метод | Путь | Действие | Ответ |
|---|---|---|---|
| GET | `/tasks` | список задач | 200 |
| GET | `/tasks/{id}` | одна задача | 200 / 404 |
| POST | `/tasks` | создать | 201 / 400 |
| PUT | `/tasks/{id}` | изменить | 200 / 400 / 404 |
| DELETE | `/tasks/{id}` | удалить | 204 / 404 |

**Create**
```bash
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Сдать контрольную точку Compose","description":"API + PostgreSQL","isDone":false}'
```

**Read**
```bash
curl http://localhost:8080/tasks
curl http://localhost:8080/tasks/1
```

**Update**
```bash
curl -X PUT http://localhost:8080/tasks/1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Сдать контрольную точку Compose","description":"Готово","isDone":true}'
```

**Delete**
```bash
curl -X DELETE http://localhost:8080/tasks/1
```

> В Windows PowerShell вызывайте `curl.exe`, а не `curl` (это псевдоним `Invoke-WebRequest`), либо используйте Postman или `scripts/check.ps1`.

Postman: **Import** → `postman/TaskApi.postman_collection.json`, запускать запросы по порядку.

## Проверка сохранения данных после перезапуска

```bash
# 1. создать задачу (см. Create) и запомнить её id
# 2. удалить контейнеры (volume db_data при этом остаётся)
docker compose down
# 3. запустить заново
docker compose up -d
# 4. задача на месте
curl http://localhost:8080/tasks
```

`docker compose down -v` удалит ещё и volume, и тогда данные пропадут. Для проверки сохранения его не использовать.

## Автоматическая проверка и материалы для сдачи

Скрипт поднимает систему, выполняет все CRUD-запросы, перезапускает Compose, проверяет, что данные остались, и сохраняет выводы в `proof/`:

```bash
bash scripts/check.sh                                          # Linux, macOS, Git Bash
powershell -ExecutionPolicy Bypass -File scripts\check.ps1     # Windows
```

| Файл | Что подтверждает |
|---|---|
| `proof/01-compose-ps.txt` | сервисы api и db запущены (`docker compose ps`) |
| `proof/02-crud.txt` | Create, Read, Update, Delete работают |
| `proof/03-persistence.txt` | данные сохранились после `down` → `up` |
| `proof/04-logs.txt` | `docker compose logs`: API подключился к базе |

## Как это устроено (для защиты)

**Сервисы в docker-compose.yml.** Их два: `api` собирается из `Dockerfile` в текущей папке (`build: .`), `db` берётся из готового образа `postgres:16`. API и база — разные сервисы, как требует задание.

**Почему PostgreSQL.** База запускается отдельным сервисом в Compose, у неё свой контейнер и свой volume. SQLite не подходит: это файл внутри контейнера API, а не отдельный сервис.

**Как API подключается к базе.** Compose создаёт сеть `app-network`, и оба сервиса в неё входят. Внутри сети сервисы видят друг друга по имени, поэтому в строке подключения `Host=db`. `localhost` не подойдёт: внутри контейнера API он означает сам контейнер API.

**Переменные окружения.**
- у `api`: `CONNECTION_STRING=Host=db;Port=5432;Database=app;Username=postgres;Password=123`, API читает её при старте;
- у `db`: `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=123`, `POSTGRES_DB=app`. При первом запуске образ PostgreSQL создаёт пользователя и базу.

**Порты.** `"8080:8080"`: слева порт компьютера, справа порт внутри контейнера. Порт базы наружу не проброшен, API ходит к ней по внутренней сети.

**depends_on и готовность базы.** Обычный `depends_on` только запускает контейнер db раньше api, но база ещё несколько секунд инициализируется. Поэтому:
1. у `db` есть `healthcheck` с `pg_isready`, а у `api` — `depends_on: db: condition: service_healthy`. API стартует, когда база реально принимает подключения;
2. дополнительно API при старте до 30 раз пробует подключиться (`Database.cs`) и только потом создаёт таблицу `tasks` (`CREATE TABLE IF NOT EXISTS`).

**Volume db_data.**
- `db_data:/var/lib/postgresql/data` внутри сервиса db отвечает на вопрос, куда подключить хранилище в контейнере: в папку, где PostgreSQL хранит данные;
- блок `volumes: db_data:` внизу файла объявляет named volume, который создаёт Docker.

Контейнер можно удалить (`docker compose down`), а данные останутся в `db_data`. Удаляет их только `docker compose down -v`.

**Как проверялось.** CRUD-запросами через curl и Postman, затем `docker compose down` → `docker compose up -d` и повторный `GET`: созданная задача осталась. Выводы лежат в `proof/`.

## Частые проблемы

| Симптом | Решение |
|---|---|
| `port is already allocated` на 8080 | занять другой порт: `"8081:8080"` и обращаться на `localhost:8081` |
| `password authentication failed` после смены пароля | старый volume хранит старого пользователя: `docker compose down -v` и снова `up` |
| API перезапускается | `docker compose logs api`: обычно ошибка в `CONNECTION_STRING` |
| `check.sh: $'\r': command not found` | файл получил переводы строк Windows: `git config core.autocrlf false` и заново склонировать, либо `dos2unix scripts/check.sh` |

## Команды Docker Compose

| Команда | Назначение |
|---|---|
| `docker compose up --build` | пересобрать и запустить |
| `docker compose up -d` | запустить в фоне |
| `docker compose ps` | показать сервисы |
| `docker compose logs api` | логи API |
| `docker compose restart api` | перезапустить API |
| `docker compose stop` | остановить |
| `docker compose down` | остановить и удалить контейнеры |
| `docker compose down -v` | удалить контейнеры и volumes |
