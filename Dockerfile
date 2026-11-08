# Этап 1: сборка API в образе с .NET SDK
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Сначала только csproj — так слой с зависимостями кэшируется
COPY TaskApi.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish TaskApi.csproj -c Release -o /app --no-restore

# Этап 2: лёгкий образ только с runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app .

# API слушает порт 8080 внутри контейнера
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "TaskApi.dll"]
