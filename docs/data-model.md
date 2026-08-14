# Modelo de datos TalentFlow

## Relaciones

```text
hr_users 1---N vacancies
vacancies 1---N scoring_config_versions 1---N scoring_criteria
                                      1---N desirable_requirements
                                      1---N added_value_requirements
candidates 1---N applications N---1 vacancies
candidates 1---N cv_references N---0..1 applications
cv_references 1---N document_processing_attempts
applications 1---N ai_analyses 1---N suggested_questions
applications 1---N score_evaluations N---1 scoring_config_versions
score_evaluations 1---N score_criterion_results N---1 scoring_criteria
applications 1---N hr_reviews N---1 hr_users
hr_users 0..1---N audit_events
```

## Reglas principales

- Los identificadores de dominio son UUID; auditoria usa identidad `bigint` ordenable.
- `candidates.email` usa `citext` y es unico sin distinguir mayusculas. La unicidad `(vacancy_id, candidate_id)` impide repetir una postulacion; como cada email identifica un unico candidato, esto aplica la regla email + vacante.
- `status` y `priority` son columnas independientes tanto en vacantes como en postulaciones.
- Los pesos aceptan valores entre 0 y 100. Un constraint trigger diferido impide publicar una version cuya suma no sea exactamente 100.
- Solo puede existir una version `PUBLISHED` por vacante. Versiones publicadas o archivadas y sus criterios, deseables y valores agregados son inmutables.
- Los deseables y valores agregados no tienen peso y no forman parte del total de scoring.
- `cv_references` guarda identificadores, enlaces y metadatos de Google Drive; nunca almacena el binario.
- Un score solo puede usar la version publicada de la misma vacante. Debe incluir todos sus criterios, el desglose debe sumar el total almacenado y ningun resultado puede superar el peso del criterio.
- `applications.revision_manual_autorizada` registra explicitamente la autorizacion de revision humana.
- Triggers mantienen `updated_at` y escriben cambios de dominio en `audit_events`. La aplicacion puede establecer `app.current_hr_user_id`, `app.source` y `app.request_id` por transaccion para enriquecer la auditoria.

## Tablas

`schema_migrations`, `hr_users`, `vacancies`, `scoring_config_versions`, `scoring_criteria`, `desirable_requirements`, `added_value_requirements`, `candidates`, `applications`, `cv_references`, `document_processing_attempts`, `ai_analyses`, `score_evaluations`, `score_criterion_results`, `suggested_questions`, `hr_reviews`, `audit_events`.

## Indices destacados

- Configuracion publicada unica por vacante.
- CV vigente unico por postulacion.
- Busqueda de vacantes y postulaciones por estado, prioridad y fecha.
- Analisis, scores y revisiones por postulacion.
- Auditoria por registro, actor y fecha.

## Ejemplo de contexto de auditoria

```sql
BEGIN;
SET LOCAL app.current_hr_user_id = '10000000-0000-4000-8000-000000000001';
SET LOCAL app.source = 'admin-web';
SET LOCAL app.request_id = 'request-id-generado-por-la-aplicacion';
-- Operaciones de dominio.
COMMIT;
```
