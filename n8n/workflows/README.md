# Workflows administrativos

Importe los nueve archivos `TF-ADMIN-*.json` en n8n. En cada workflow asigne una credencial PostgreSQL con host `postgres`, puerto `5432`, base y usuario configurados mediante `.env`; después active el workflow.

Los nodos PostgreSQL usan placeholders `$1`, `$2` y `queryReplacement`. Ningún valor de la petición se concatena dentro del SQL.

| Workflow | Metodo y endpoint |
|---|---|
| TF-ADMIN-01 | `GET /webhook/admin/vacancies` |
| TF-ADMIN-02 | `GET /webhook/tf-admin-get-vacancy/admin/vacancies/:id` |
| TF-ADMIN-03 | `POST /webhook/admin/vacancies` |
| TF-ADMIN-04 | `PUT /webhook/tf-admin-update-vacancy/admin/vacancies/:id` |
| TF-ADMIN-05 | `POST /webhook/tf-admin-publish-vacancy/admin/vacancies/:id/publish` |
| TF-ADMIN-06 | `POST /webhook/tf-admin-status-vacancy/admin/vacancies/:id/status` |
| TF-ADMIN-07 | `POST /webhook/tf-admin-duplicate-vacancy/admin/vacancies/:id/duplicate` |
| TF-ADMIN-08 | `GET /webhook/admin/candidates` |
| TF-ADMIN-09 | `GET /webhook/tf-admin-get-candidate/admin/candidates/:id` |

Las credenciales se guardan exclusivamente en Credentials de n8n y no en los exports.
Los endpoints con `:id` incluyen el `webhookId` descriptivo porque n8n lo
antepone automaticamente a las rutas dinamicas.
# Validacion antes de importar

Ejecuta desde la raiz del proyecto:

```bash
node n8n/workflows/validate-workflows.mjs
```

En n8n 2.31, las consultas PostgreSQL con `$1`, `$2`, etc. deben enviar los
valores mediante `parameters.options.queryReplacement`. La propiedad
`queryParams` no es reconocida al importar y n8n la elimina silenciosamente.

## Modulo 4

Importar en este orden:

1. `TF-M4-01-application-reception.json`
2. `TF-M4-04-cv-manual-review.json`

En los dos workflows se debe seleccionar una credencial OAuth2 de Google Drive
y reemplazar los IDs de carpeta indicados. Las carpetas deben ser privadas:

- `TalentFlow/CV`: `REPLACE_WITH_PRIVATE_CV_FOLDER_ID`
- `TalentFlow/RevisionManual`: `REPLACE_WITH_PRIVATE_MANUAL_REVIEW_FOLDER_ID`

`TF-M4-01` recibe, valida, extrae el texto, almacena el PDF y registra la
postulación dentro de una sola ejecución. No se exportan credenciales ni IDs
reales. Activar los dos webhooks después de configurar Drive y PostgreSQL. El
módulo no contiene nodos de IA.

## Modulo 5 - IA-01

Importar `TF-M5-01-ia01-extractor-cv.json` y configurar PostgreSQL, Google
Drive y una credencial Google Gemini en `Gemini 3.6 Flash`. El workflow se ejecuta
como subworkflow con el input `postulacion_id`, usa `PROMPT-IA-01-v1` y valida
la salida contra `n8n/schemas/IA01-extractor.schema.json`.

Devuelve `analysis_id`, `structured_candidate_data` y `status`. No calcula
score ni genera resumen, preguntas o recomendaciones. Las API keys permanecen
exclusivamente en Credentials de n8n.
