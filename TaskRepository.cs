using System.Data.Common;
using Npgsql;

namespace TaskApi;

// Вся работа с PostgreSQL: обычные SQL-запросы через Npgsql.
public class TaskRepository(NpgsqlDataSource db)
{
    private const string Columns = "id, title, description, is_done, created_at";

    public async Task<List<TaskItem>> GetAllAsync()
    {
        await using var cmd = db.CreateCommand($"SELECT {Columns} FROM tasks ORDER BY id");
        await using var reader = await cmd.ExecuteReaderAsync();

        var result = new List<TaskItem>();
        while (await reader.ReadAsync())
            result.Add(Read(reader));
        return result;
    }

    public async Task<TaskItem?> GetByIdAsync(int id)
    {
        await using var cmd = db.CreateCommand($"SELECT {Columns} FROM tasks WHERE id = @id");
        cmd.Parameters.AddWithValue("id", id);
        return await ReadOneAsync(cmd);
    }

    public async Task<TaskItem> CreateAsync(TaskRequest request)
    {
        await using var cmd = db.CreateCommand(
            $"""
            INSERT INTO tasks (title, description, is_done)
            VALUES (@title, @description, @is_done)
            RETURNING {Columns}
            """);
        AddParameters(cmd, request);
        return (await ReadOneAsync(cmd))!;
    }

    public async Task<TaskItem?> UpdateAsync(int id, TaskRequest request)
    {
        await using var cmd = db.CreateCommand(
            $"""
            UPDATE tasks
            SET title = @title, description = @description, is_done = @is_done
            WHERE id = @id
            RETURNING {Columns}
            """);
        cmd.Parameters.AddWithValue("id", id);
        AddParameters(cmd, request);
        return await ReadOneAsync(cmd);
    }

    public async Task<bool> DeleteAsync(int id)
    {
        await using var cmd = db.CreateCommand("DELETE FROM tasks WHERE id = @id");
        cmd.Parameters.AddWithValue("id", id);
        return await cmd.ExecuteNonQueryAsync() > 0;
    }

    private static void AddParameters(NpgsqlCommand cmd, TaskRequest request)
    {
        cmd.Parameters.AddWithValue("title", request.Title!.Trim());
        cmd.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
        cmd.Parameters.AddWithValue("is_done", request.IsDone);
    }

    private static async Task<TaskItem?> ReadOneAsync(NpgsqlCommand cmd)
    {
        await using var reader = await cmd.ExecuteReaderAsync();
        return await reader.ReadAsync() ? Read(reader) : null;
    }

    private static TaskItem Read(DbDataReader r) => new(
        r.GetInt32(0),
        r.GetString(1),
        r.IsDBNull(2) ? null : r.GetString(2),
        r.GetBoolean(3),
        r.GetDateTime(4));
}
