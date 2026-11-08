namespace TaskApi;

// Задача, как она хранится в таблице tasks и возвращается из API.
public record TaskItem(
    int Id,
    string Title,
    string? Description,
    bool IsDone,
    DateTime CreatedAt);

// Тело запроса для POST /tasks и PUT /tasks/{id}.
public record TaskRequest(
    string? Title,
    string? Description,
    bool IsDone = false);
