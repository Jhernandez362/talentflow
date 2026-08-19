# Migraciones de base de datos

Las migraciones se ejecutan en orden numerico y una sola vez por entorno. Cada archivo registra su version en `talentflow.schema_migrations`.

Desde PowerShell, con los contenedores activos:

```powershell
Get-ChildItem database/migrations/*.sql | Sort-Object Name | ForEach-Object {
    Get-Content -Raw $_.FullName | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
}
```

Las migraciones no incluyen datos de desarrollo. Estos se encuentran en `database/seeds/`.
## 012 - Modulo 4

`012_module_4_public_application.sql` incorpora tickets humanos basados en
sequence, datos declarados por el candidato, estados documentales, intentos de
CV y funciones para recepción, resultado de validación y revisión manual.

## 015 - Modulo 5

`015_module_5_ia01_extractor.sql` incorpora el estado `ANALIZADO`, persistencia
de modelo/versión del prompt y un máximo de tres intentos de extracción IA-01.

`016_ia01_non_null_output.sql` impide marcar como exitoso un análisis cuya
salida estructurada sea nula.

`017_ia01_gemini_defaults.sql` cambia el proveedor predeterminado de IA-01 a
Google Gemini. `018_ia01_gemini_36_default.sql` actualiza el modelo a
`gemini-3.6-flash`, disponible para cuentas nuevas.
