#!/usr/bin/env bash
# Полная проверка контрольной точки: запуск, ps, CRUD, перезапуск, логи.
# Все выводы сохраняются в папку proof/ — их и прикладывать к сдаче.
# Запуск из корня проекта:  bash scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

API="http://localhost:8080"
OUT="proof"
mkdir -p "$OUT"

step() { echo; echo "===== $* ====="; }

wait_api() {
  for _ in $(seq 1 60); do
    if curl -sf "$API/" >/dev/null; then return 0; fi
    sleep 2
  done
  echo "API не ответил за 2 минуты, смотрите: docker compose logs api" >&2
  exit 1
}

# req МЕТОД ПУТЬ [JSON] — печатает команду, ответ и HTTP-код
req() {
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    echo "\$ curl -X $method $API$path -H 'Content-Type: application/json' -d '$body'"
    curl -s -X "$method" "$API$path" -H "Content-Type: application/json" -d "$body" -w "\nHTTP %{http_code}\n"
  else
    echo "\$ curl -X $method $API$path"
    curl -s -X "$method" "$API$path" -w "\nHTTP %{http_code}\n"
  fi
  echo
}

extract_id() { sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -n1; }

# 1. Запуск
step "docker compose up -d --build"
docker compose up -d --build
wait_api

# 2. Сервисы
{
  step "docker compose ps"
  docker compose ps
} 2>&1 | tee "$OUT/01-compose-ps.txt"

# 3. CRUD
{
  step "CREATE — POST /tasks"
  created=$(curl -s -X POST "$API/tasks" -H "Content-Type: application/json" \
    -d '{"title":"Сдать контрольную точку Compose","description":"API + PostgreSQL в Docker Compose","isDone":false}')
  echo "\$ curl -X POST $API/tasks -H 'Content-Type: application/json' -d '{\"title\":\"Сдать контрольную точку Compose\",\"description\":\"API + PostgreSQL в Docker Compose\",\"isDone\":false}'"
  echo "$created"
  ID=$(echo "$created" | extract_id)
  echo "$ID" > "$OUT/.task-id"   # блок выполняется в подоболочке, передаём id через файл
  echo "Создана задача с id=$ID"
  echo

  echo "\$ curl -X POST $API/tasks -H 'Content-Type: application/json' -d '{\"title\":\"Временная задача\",\"description\":\"будет удалена\"}'"
  tmp=$(curl -s -X POST "$API/tasks" -H "Content-Type: application/json" \
    -d '{"title":"Временная задача","description":"будет удалена"}')
  echo "$tmp"
  TMP_ID=$(echo "$tmp" | extract_id)
  echo

  step "READ — GET /tasks"
  req GET /tasks

  step "READ — GET /tasks/$ID"
  req GET "/tasks/$ID"

  step "UPDATE — PUT /tasks/$ID"
  req PUT "/tasks/$ID" '{"title":"Сдать контрольную точку Compose","description":"Проверено: CRUD работает","isDone":true}'

  step "DELETE — удаляем временную задачу"
  req DELETE "/tasks/$TMP_ID"

  step "Проверка удаления — GET /tasks/$TMP_ID (ожидается 404)"
  req GET "/tasks/$TMP_ID"

  step "Проверка валидации — POST без title (ожидается 400)"
  req POST /tasks '{"description":"без названия"}'
} 2>&1 | tee "$OUT/02-crud.txt"

ID=$(cat "$OUT/.task-id")
rm -f "$OUT/.task-id"
if [ -z "$ID" ]; then
  echo "Не удалось создать задачу, смотрите $OUT/02-crud.txt и docker compose logs api" >&2
  exit 1
fi

# 4. Сохранение данных после перезапуска
{
  step "Данные ДО перезапуска — GET /tasks/$ID"
  req GET "/tasks/$ID"

  step "docker compose down (контейнеры удаляются, volume db_data остаётся)"
  docker compose down

  step "docker volume ls — volume db_data на месте"
  docker volume ls | grep db_data || true

  step "docker compose up -d"
  docker compose up -d
  wait_api

  step "docker compose ps после перезапуска"
  docker compose ps

  step "Данные ПОСЛЕ перезапуска — GET /tasks/$ID"
  req GET "/tasks/$ID"

  step "Все задачи после перезапуска — GET /tasks"
  req GET /tasks
} 2>&1 | tee "$OUT/03-persistence.txt"

# 5. Логи
docker compose logs --no-color api db > "$OUT/04-logs.txt" 2>&1
step "Логи сохранены в $OUT/04-logs.txt"

echo
echo "Готово. Файлы для сдачи лежат в папке $OUT/"
