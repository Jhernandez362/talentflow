# Seeds de desarrollo

El seed `001_development.sql` crea datos ficticios y es idempotente. No contiene informacion personal real.

Desde PowerShell:

```powershell
Get-Content -Raw database/seeds/001_development.sql | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```
