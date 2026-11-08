# Полная проверка контрольной точки для Windows (PowerShell).
# Запуск из корня проекта:  powershell -ExecutionPolicy Bypass -File scripts\check.ps1
# Continue: в Windows PowerShell 5.1 вывод docker в stderr при "Stop" считается ошибкой
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Api = "http://localhost:8080"
$Out = "proof"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Step($text) { ""; "===== $text =====" }

function Wait-Api {
    for ($i = 0; $i -lt 60; $i++) {
        try { Invoke-WebRequest -Uri "$Api/" -UseBasicParsing -ErrorAction Stop | Out-Null; return } catch { Start-Sleep 2 }
    }
    throw "API не ответил за 2 минуты, смотрите: docker compose logs api"
}

function Req($Method, $Path, $Body) {
    "> $Method $Api$Path $Body"
    $params = @{ Uri = "$Api$Path"; Method = $Method; UseBasicParsing = $true; ErrorAction = "Stop" }
    if ($Body) {
        $params.Body = [Text.Encoding]::UTF8.GetBytes($Body)
        $params.ContentType = "application/json; charset=utf-8"
    }
    try {
        $r = Invoke-WebRequest @params
        $r.Content
        "HTTP $($r.StatusCode)"
    } catch {
        $code = [int]$_.Exception.Response.StatusCode
        if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message }
        "HTTP $code"
    }
    ""
}

function Save($file, [scriptblock]$block) {
    $text = & $block 2>&1 | Out-String
    $text | Out-File -FilePath (Join-Path $Out $file) -Encoding utf8
    $text
}

Step "docker compose up -d --build"
docker compose up -d --build
Wait-Api

Save "01-compose-ps.txt" { Step "docker compose ps"; docker compose ps }

$created = Invoke-RestMethod -ErrorAction Stop -Uri "$Api/tasks" -Method Post -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes('{"title":"Сдать контрольную точку Compose","description":"API + PostgreSQL в Docker Compose","isDone":false}'))
$Id = $created.id
$tmp = Invoke-RestMethod -ErrorAction Stop -Uri "$Api/tasks" -Method Post -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes('{"title":"Временная задача","description":"будет удалена"}'))
$TmpId = $tmp.id

Save "02-crud.txt" {
    Step "CREATE — POST /tasks"
    "Созданы задачи: id=$Id и временная id=$TmpId"
    $created | ConvertTo-Json
    Step "READ — GET /tasks";               Req GET "/tasks"
    Step "READ — GET /tasks/$Id";           Req GET "/tasks/$Id"
    Step "UPDATE — PUT /tasks/$Id";         Req PUT "/tasks/$Id" '{"title":"Сдать контрольную точку Compose","description":"Проверено: CRUD работает","isDone":true}'
    Step "DELETE — DELETE /tasks/$TmpId";   Req DELETE "/tasks/$TmpId"
    Step "Проверка удаления (ожидается 404)"; Req GET "/tasks/$TmpId"
    Step "Валидация: POST без title (ожидается 400)"; Req POST "/tasks" '{"description":"без названия"}'
}

Save "03-persistence.txt" {
    Step "Данные ДО перезапуска";  Req GET "/tasks/$Id"
    Step "docker compose down";    docker compose down
    Step "docker volume ls";       docker volume ls | Select-String db_data
    Step "docker compose up -d";   docker compose up -d; Wait-Api
    Step "docker compose ps";      docker compose ps
    Step "Данные ПОСЛЕ перезапуска"; Req GET "/tasks/$Id"
    Step "Все задачи";             Req GET "/tasks"
}

docker compose logs --no-color api db 2>&1 | Out-File -FilePath (Join-Path $Out "04-logs.txt") -Encoding utf8
""
"Готово. Файлы для сдачи лежат в папке $Out\"
