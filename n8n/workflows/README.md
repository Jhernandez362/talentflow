# Workflows administrativos

Importe los siete archivos `TF-ADMIN-*.json` en n8n. En cada workflow asigne una credencial PostgreSQL con host `postgres`, puerto `5432`, base y usuario configurados mediante `.env`; después active el workflow.

Los nodos PostgreSQL usan placeholders `$1`, `$2` y `queryReplacement`. Ningún valor de la petición se concatena dentro del SQL.

| Workflow | Metodo y endpoint |
|---|---|
| TF-ADMIN-01 | `GET /webhook/admin/vacancies` |
| TF-ADMIN-02 | `GET /webhook/admin/vacancies/:id` |
| TF-ADMIN-03 | `POST /webhook/admin/vacancies` |
| TF-ADMIN-04 | `PUT /webhook/admin/vacancies/:id` |
| TF-ADMIN-05 | `POST /webhook/admin/vacancies/:id/publish` |
| TF-ADMIN-06 | `POST /webhook/admin/vacancies/:id/status` |
| TF-ADMIN-07 | `POST /webhook/admin/vacancies/:id/duplicate` |

Las credenciales se guardan exclusivamente en Credentials de n8n y no en los exports.
