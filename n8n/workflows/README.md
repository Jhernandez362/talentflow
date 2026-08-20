# Workflows administrativos

Importe los archivos `TF-ADMIN-*.json` en n8n. En cada workflow asigne una credencial PostgreSQL con host `postgres`, puerto `5432`, base y usuario configurados mediante `.env`; después active el workflow.

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
| TF-ADMIN-10 | `POST /webhook/tf-admin-change-candidate-status/admin/candidates/:id/status` |
| TF-ADMIN-11 | `POST /webhook/tf-admin-record-hr-review/admin/candidates/:id/reviews` |
| TF-ADMIN-12 | `GET /webhook/admin/document-reviews` |
| TF-ADMIN-13 | `POST /webhook/tf-admin-manual-analysis/admin/document-reviews/:id/manual-analysis` |

Las credenciales se guardan exclusivamente en Credentials de n8n y no en los exports.
Los endpoints con `:id` incluyen el `webhookId` descriptivo porque n8n lo
antepone automaticamente a las rutas dinamicas.

Todos los endpoints de escritura (`TF-ADMIN-03, 04, 05, 06, 07, 10, 11, 13`)
tienen `onError: continueErrorOutput` en cada nodo que puede fallar (validacion
en Code node y/o consulta PostgreSQL) y responden `422` con
`{"error":true,"message":"..."}` cuando la operacion es rechazada por
validacion de payload o por una regla de negocio en PL/pgSQL (por ejemplo
`FINAL_STATUS_CANNOT_TRANSITION`, `INVALID_HR_REVIEW_RESULT`,
`SCORE_ALREADY_EXISTS_FOR_VERSION`). Antes solo devolvian `200` con cuerpo
vacio, sin indicar el motivo del rechazo.
# Validacion antes de importar

Ejecuta desde la raiz del proyecto:

```bash
node n8n/workflows/validate-workflows.mjs
```

## Sincronizacion con n8n local

Los archivos de `n8n/workflows` son la fuente de verdad. Para importarlos o
actualizarlos en `http://localhost:5679`, preservando credenciales, IDs de
carpetas locales y estado de activacion, ejecuta:

```bash
bash n8n/sync/sync-workflows.sh
```

Durante desarrollo puede mantenerse una sincronizacion continua. El watcher
detecta cambios en los JSON, los importa por su ID estable y reinicia n8n para
que los webhooks carguen la nueva version:

```bash
bash n8n/sync/watch-workflows.sh
```

La sincronizacion no exporta secretos: solo conserva las referencias locales a
Credentials que ya existen en la instancia n8n.

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

## Modulo 8 - Panel de candidatos y revision humana

Importar `TF-ADMIN-10-change-candidate-status.json`,
`TF-ADMIN-11-record-hr-review.json`, `TF-ADMIN-12-document-reviews.json` y
`TF-ADMIN-13-manual-analysis.json`, y configurar la misma credencial
PostgreSQL usada por el resto de `TF-ADMIN-*`.

- `TF-ADMIN-10` y `TF-ADMIN-11` envuelven `admin_change_candidate_status` y
  `admin_record_hr_review`; ambas funciones validan al actor contra
  `talentflow.hr_users` (rol activo `ADMIN|RECRUITER|REVIEWER`) y escriben en
  `application_status_history` / `hr_reviews` respectivamente.
- `TF-ADMIN-12` solo lista postulaciones en `REVISION_DOCUMENTO` con
  `revision_manual_autorizada = true`.
- `TF-ADMIN-13` persiste la estructuracion manual del CV con
  `analysis_source = 'MANUAL'` y encadena, en la misma ejecucion, el motor de
  scoring determinista del Modulo 6 (`WF-SCORING-CANDIDATO`) y ambos
  workflows del Modulo 7 (`WF-IA02-RESUMEN`, `WF-IA03-PREGUNTAS`). No vuelve a
  exigir el procesamiento automatico del PDF (IA-01).

Ninguno de los cuatro workflows valida un header de autenticacion: la
identidad del usuario RRHH se recibe como `actorId` en el body y se valida
unicamente a nivel de base de datos. Es el mismo patron ya usado por
`TF-ADMIN-01..09`, no una particularidad del Modulo 8.

`TF-ADMIN-10`, `TF-ADMIN-11` y `TF-ADMIN-13` (nodos `db` y, en el caso de
`TF-ADMIN-13`, tambien el nodo `score` que invoca el motor de scoring)
responden `422` con `{"error":true,"message":"..."}` cuando la funcion
PL/pgSQL o el scoring determinista rechazan la operacion. Ver la nota sobre
manejo de errores mas arriba en este documento.
