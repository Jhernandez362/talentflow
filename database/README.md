# Base de datos TalentFlow

El modelo vive en el esquema `talentflow`; PostgreSQL sigue siendo la fuente oficial y las tablas internas de n8n permanecen separadas.

## Aplicar en un entorno nuevo

Con Docker Compose activo, ejecute desde PowerShell:

```powershell
Get-ChildItem database/migrations/*.sql | Sort-Object Name | ForEach-Object {
    Get-Content -Raw $_.FullName | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
}

Get-Content -Raw database/seeds/001_development.sql | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Cada migracion se aplica una sola vez. Para comprobar las versiones aplicadas:

```powershell
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "TABLE talentflow.schema_migrations"'
```

## Pruebas

```powershell
Get-Content -Raw database/tests/001_schema_acceptance.sql | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

La prueba se revierte a si misma y comprueba seed, pesos no negativos, postulaciones duplicadas, publicacion valida con 100 puntos, rechazo con 99, inmutabilidad y consistencia del desglose de score.

El Modulo 3 agrega `002_admin_score_boundaries.sql` para 99/100/101 y `003_admin_vacancy_integration.sql` para creacion, publicacion y duplicacion transaccional.

Consultas manuales utiles:

```powershell
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\\dt talentflow.*"'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT scoring_config_version_id, sum(weight) FROM talentflow.scoring_criteria GROUP BY scoring_config_version_id"'
```

El diagrama textual, las relaciones, reglas e indices se documentan en `docs/data-model.md`.
