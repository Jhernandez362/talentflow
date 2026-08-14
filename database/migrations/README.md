# Migraciones de base de datos

Las migraciones se ejecutan en orden numerico y una sola vez por entorno. Cada archivo registra su version en `talentflow.schema_migrations`.

Desde PowerShell, con los contenedores activos:

```powershell
Get-ChildItem database/migrations/*.sql | Sort-Object Name | ForEach-Object {
    Get-Content -Raw $_.FullName | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
}
```

Las migraciones no incluyen datos de desarrollo. Estos se encuentran en `database/seeds/`.
