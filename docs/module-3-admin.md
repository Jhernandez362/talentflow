# Modulo 3: panel administrativo

## Rutas

- `/admin` y `/admin/dashboard`: resumen provisional.
- `/admin/vacantes`: listado y acciones de estado.
- `/admin/vacantes/nueva`: wizard de seis pasos.
- `/admin/vacantes/:id`: edicion y versionado.
- Candidatos, revision documental, metricas y configuracion son placeholders.

## Preparar n8n

Los siete workflows ya pueden importarse desde `n8n/workflows`. En n8n cree una credencial PostgreSQL:

```text
Host: postgres
Port: 5432
Database: valor POSTGRES_DB de .env
User: valor POSTGRES_USER de .env
Password: valor POSTGRES_PASSWORD de .env
SSL: desactivado para el entorno Docker local
```

Asigne esa credencial al nodo `PostgreSQL` de cada workflow y active los siete. Las credenciales permanecen cifradas en n8n y nunca se exportan al repositorio.

## Endpoints

```text
GET  /webhook/admin/vacancies
GET  /webhook/admin/vacancies/:id
POST /webhook/admin/vacancies
PUT  /webhook/admin/vacancies/:id
POST /webhook/admin/vacancies/:id/publish
POST /webhook/admin/vacancies/:id/status
POST /webhook/admin/vacancies/:id/duplicate
```

## Prueba manual

1. Abra `http://localhost:5174/admin/vacantes` con los puertos locales actuales.
2. Seleccione **Nueva vacante** y complete informacion general y perfil.
3. Agregue criterios. Compruebe el feedback con totales 99, 100 y 101.
4. Agregue deseables y valores agregados; el total no debe cambiar.
5. Guarde el borrador con cualquier total valido numericamente.
6. En Publicacion, el boton solo se habilita con datos minimos y total 100.
7. Publique, vuelva al listado y pruebe editar, duplicar, pausar, reabrir y cerrar.

PostgreSQL vuelve a validar las reglas aunque se manipule la peticion. Una edicion de criterios publicados crea una version borrador y conserva la version activa hasta publicar la nueva.

## Pruebas SQL

```powershell
Get-Content -Raw database/tests/002_admin_score_boundaries.sql | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
Get-Content -Raw database/tests/003_admin_vacancy_integration.sql | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

La prueba integral crea, publica y duplica datos ficticios dentro de una transaccion y hace `ROLLBACK` al finalizar.
