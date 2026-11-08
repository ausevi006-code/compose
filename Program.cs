using System.Text.Encodings.Web;
using Npgsql;
using TaskApi;

var builder = WebApplication.CreateBuilder(args);

// Строка подключения приходит из переменной окружения CONNECTION_STRING,
// которую задаёт docker-compose.yml. Host=db — имя сервиса базы в Compose.
var connectionString = builder.Configuration["CONNECTION_STRING"]
    ?? throw new InvalidOperationException("Переменная окружения CONNECTION_STRING не задана");

builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));

// Кириллица в JSON-ответах выводится как есть, а не как За...
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping);
builder.Services.AddSingleton<TaskRepository>();

var app = builder.Build();

await Database.InitializeAsync(
    app.Services.GetRequiredService<NpgsqlDataSource>(),
    app.Logger);

app.MapGet("/", () => Results.Ok(new { service = "TaskApi", status = "ok" }));

var tasks = app.MapGroup("/tasks");

// Read: все задачи
tasks.MapGet("/", async (TaskRepository repo) =>
    Results.Ok(await repo.GetAllAsync()));

// Read: одна задача
tasks.MapGet("/{id:int}", async (int id, TaskRepository repo) =>
    await repo.GetByIdAsync(id) is { } task
        ? Results.Ok(task)
        : Results.NotFound(new { error = $"Задача {id} не найдена" }));

// Create
tasks.MapPost("/", async (TaskRequest request, TaskRepository repo) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
        return Results.BadRequest(new { error = "Поле title обязательно" });

    var created = await repo.CreateAsync(request);
    return Results.Created($"/tasks/{created.Id}", created);
});

// Update
tasks.MapPut("/{id:int}", async (int id, TaskRequest request, TaskRepository repo) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
        return Results.BadRequest(new { error = "Поле title обязательно" });

    return await repo.UpdateAsync(id, request) is { } updated
        ? Results.Ok(updated)
        : Results.NotFound(new { error = $"Задача {id} не найдена" });
});

// Delete
tasks.MapDelete("/{id:int}", async (int id, TaskRepository repo) =>
    await repo.DeleteAsync(id)
        ? Results.NoContent()
        : Results.NotFound(new { error = $"Задача {id} не найдена" }));

app.Run();
