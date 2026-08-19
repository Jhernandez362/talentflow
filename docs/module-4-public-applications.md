# Modulo 4: web publica y postulacion

## Alcance implementado

- Catalogo `/vacantes`, detalle `/vacantes/:id` y formulario `/postular/:vacanteId`.
- Envio real `multipart/form-data`; el PDF ya no se representa mediante metadatos ficticios.
- Validacion server-side de presencia, extensión, MIME, limite de 5 MB, firma `%PDF-`,
  integridad/protección mediante parser y mínimo de 100 caracteres extraíbles.
- Ticket concurrente mediante sequence (`TF-AAAA-000000`).
- Duplicado por candidato/correo y vacante.
- Registro de intentos y clasificación `DOCUMENT_ERROR` / `SYSTEM_ERROR`.
- Mensajes diferenciados para intentos 1, 2 y 3.
- Revisión manual únicamente después de tres errores documentales y con autorización explícita.
- CV válido y CV de revisión manual en carpetas privadas separadas de Google Drive.
- PostgreSQL conserva referencia y metadatos; nunca el binario.
- Estados usados en este módulo: `VALIDANDO_DOCUMENTO`, `RECIBIDO`,
  `REVISION_DOCUMENTO` y `ERROR`.

## Endpoints

| Metodo | Endpoint de producción |
|---|---|
| GET | `/webhook/public/vacancies` |
| GET | `/webhook/tf-public-get-vacancy/public/vacancies/:id` |
| POST multipart | `/webhook/public/applications` |
| POST multipart | `/webhook/public/applications/manual-review` |

El campo binario de ambos POST se llama `cv`.

## Configuracion pendiente por entorno

n8n no exporta credenciales. Antes de activar los dos webhooks POST:

1. Crear una credencial Google Drive OAuth2.
2. Crear `TalentFlow/CV` y `TalentFlow/RevisionManual` como carpetas privadas.
3. Configurar la credencial y el ID de `TalentFlow/CV` en `TF-M4-01`.
4. Configurar la credencial y el ID de `TalentFlow/RevisionManual` en `TF-M4-04`.
5. Seleccionar `Postgres account` en los nodos PostgreSQL de `TF-M4-01` y `TF-M4-04`.
6. Activar `TF-M4-01` y `TF-M4-04`.

## Pruebas

```bash
node n8n/workflows/validate-workflows.mjs
docker compose exec -T postgres sh -lc \
  'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/tests/005_module_4_application_flow.sql
docker compose run --rm frontend npm run build
```

Muestra válida disponible en el entorno de desarrollo:
`/usr/share/cups/data/form_english.pdf` (PDF parseable, 234 caracteres sin espacios).
Un archivo de texto renombrado o enviado como PDF falla por MIME/firma antes del parser.

No hay nodos de IA, prompts, scoring, resumen, preguntas ni Telegram en los workflows
`TF-M4-*`. El siguiente procesamiento no forma parte de este módulo.
