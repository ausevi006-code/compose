using Npgsql;

namespace TaskApi;

public static class Database
{
    // depends_on запускает контейнер db раньше api, но не гарантирует,
    // что PostgreSQL уже принимает подключения. Поэтому при старте API
    // несколько раз пробуем подключиться и только потом создаём таблицу.
    public static async Task InitializeAsync(NpgsqlDataSource db, ILogger logger)
    {
        const int maxAttempts = 30;

        for (var attempt = 1; ; attempt++)
        {
            try
            {
                await using var cmd = db.CreateCommand(
                    """
                    CREATE TABLE IF NOT EXISTS tasks (
                        id          SERIAL PRIMARY KEY,
                        title       VARCHAR(200) NOT NULL,
                        description TEXT,
                        is_done     BOOLEAN      NOT NULL DEFAULT FALSE,
                        created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
                    )
                    """);
                await cmd.ExecuteNonQueryAsync();

                logger.LogInformation("Подключение к PostgreSQL установлено, таблица tasks готова");
                return;
            }
            catch (Exception ex) when (attempt < maxAttempts && ex is NpgsqlException or System.Net.Sockets.SocketException)
            {
                logger.LogWarning("База данных ещё не готова (попытка {Attempt}/{Max}): {Message}",
                    attempt, maxAttempts, ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(2));
            }
        }
    }
}
