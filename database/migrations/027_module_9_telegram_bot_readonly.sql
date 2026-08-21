BEGIN;

-- =========================================================================
-- Modulo 9: Bot hibrido de Telegram (solo lectura)
-- =========================================================================
-- Capa 1 (usuario Postgres propio) y Capa 2 (solo SELECT sobre vistas
-- permitidas) de la defensa en profundidad. Las Capas 4-6 (subworkflows,
-- queries parametrizadas y prompt restrictivo) viven en n8n/, no en SQL.
--
-- El rol talentflow_bot_readonly nunca recibe permisos sobre tablas base
-- ni sobre el esquema public (n8n interno): solo sobre las vistas vw_bot_*
-- creadas aqui. La contrasena real se asigna por fuera de este archivo con
-- ALTER ROLE ... PASSWORD (no se versiona ningun secreto).
-- =========================================================================

-- ---------------------------------------------------------------------
-- Autorizacion de usuarios de Telegram (tabla administrada por la app
-- principal; el bot solo la lee a traves de vw_bot_authorized_users).
-- ---------------------------------------------------------------------
CREATE TABLE talentflow.bot_authorized_telegram_users (
    telegram_user_id bigint PRIMARY KEY,
    hr_user_id uuid NOT NULL REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
    telegram_display_name varchar(150),
    is_active boolean NOT NULL DEFAULT true,
    added_at timestamptz NOT NULL DEFAULT now(),
    added_by uuid REFERENCES talentflow.hr_users(id) ON DELETE SET NULL
);

COMMENT ON TABLE talentflow.bot_authorized_telegram_users IS
    'Lista blanca de telegram_user_id habilitados para usar el bot de RRHH. Nunca se valida solo por username porque puede cambiar.';

CREATE TRIGGER bot_authorized_telegram_users_audit
    AFTER INSERT OR DELETE OR UPDATE ON talentflow.bot_authorized_telegram_users
    FOR EACH ROW EXECUTE FUNCTION talentflow.capture_audit_event();

-- ---------------------------------------------------------------------
-- Capa 3: vistas especificas. Cada vista expone unicamente lo necesario
-- para que el bot responda consultas de RRHH; ninguna vista permite
-- identificar credenciales, tokens ni datos de n8n.
-- ---------------------------------------------------------------------

CREATE VIEW talentflow.vw_bot_vacantes AS
SELECT
    v.id AS vacancy_id,
    v.code,
    v.title,
    v.department,
    v.status,
    v.priority,
    v.work_mode,
    v.location,
    v.seniority_level,
    v.openings,
    v.contract_type,
    v.minimum_experience_months,
    v.minimum_education,
    v.education_required,
    v.closes_at,
    v.published_at,
    v.created_at,
    (SELECT count(*) FROM talentflow.applications a WHERE a.vacancy_id = v.id) AS total_postulaciones
FROM talentflow.vacancies v;

COMMENT ON VIEW talentflow.vw_bot_vacantes IS 'Vista de solo lectura para el bot de Telegram: catalogo de vacantes.';

CREATE VIEW talentflow.vw_bot_candidatos AS
SELECT
    a.id AS postulacion_id,
    a.ticket_id,
    c.full_name AS candidato,
    c.email,
    c.phone,
    a.vacancy_id,
    v.title AS vacante,
    v.code AS vacante_codigo,
    a.status AS estado,
    a.priority AS prioridad,
    a.applied_at,
    a.revision_manual_autorizada,
    c.declared_experience_years,
    se.total_score AS score,
    se.compatibility_priority AS prioridad_compatibilidad,
    se.calculated_at AS score_calculado_en
FROM talentflow.applications a
JOIN talentflow.candidates c ON c.id = a.candidate_id
JOIN talentflow.vacancies v ON v.id = a.vacancy_id
LEFT JOIN LATERAL (
    SELECT s.total_score, s.compatibility_priority, s.calculated_at
    FROM talentflow.score_evaluations s
    WHERE s.application_id = a.id
    ORDER BY s.calculated_at DESC
    LIMIT 1
) se ON true;

COMMENT ON VIEW talentflow.vw_bot_candidatos IS 'Vista de solo lectura para el bot de Telegram: postulaciones con su ultimo score.';

CREATE VIEW talentflow.vw_bot_resultados AS
SELECT
    a.id AS postulacion_id,
    a.ticket_id,
    c.full_name AS candidato,
    v.title AS vacante,
    a.status AS estado,
    se.id AS score_evaluation_id,
    se.total_score AS score,
    se.compatibility_priority AS prioridad_compatibilidad,
    se.algorithm_version,
    se.result_breakdown,
    se.calculated_at,
    (
        SELECT ai.structured_output->>'summary'
        FROM talentflow.ai_analyses ai
        WHERE ai.application_id = a.id AND ai.analysis_type = 'PROFESSIONAL_SUMMARY' AND ai.status = 'SUCCEEDED'
        ORDER BY ai.created_at DESC LIMIT 1
    ) AS resumen_profesional,
    (
        SELECT jsonb_agg(jsonb_build_object('question', sq.question, 'rationale', sq.rationale) ORDER BY sq.display_order)
        FROM talentflow.suggested_questions sq
        WHERE sq.application_id = a.id
    ) AS preguntas_sugeridas
FROM talentflow.applications a
JOIN talentflow.candidates c ON c.id = a.candidate_id
JOIN talentflow.vacancies v ON v.id = a.vacancy_id
LEFT JOIN LATERAL (
    SELECT s.*
    FROM talentflow.score_evaluations s
    WHERE s.application_id = a.id
    ORDER BY s.calculated_at DESC
    LIMIT 1
) se ON true;

COMMENT ON VIEW talentflow.vw_bot_resultados IS 'Vista de solo lectura para el bot de Telegram: detalle de resultado (score, resumen, preguntas) por postulacion.';

CREATE VIEW talentflow.vw_bot_pendientes AS
SELECT
    a.id AS postulacion_id,
    a.ticket_id,
    c.full_name AS candidato,
    v.title AS vacante,
    a.status AS estado,
    a.priority AS prioridad,
    a.revision_manual_autorizada,
    a.manual_review_reason,
    a.applied_at,
    a.updated_at
FROM talentflow.applications a
JOIN talentflow.candidates c ON c.id = a.candidate_id
JOIN talentflow.vacancies v ON v.id = a.vacancy_id
WHERE a.status IN ('PENDIENTE_REVISION', 'EN_REVISION', 'REVISION_DOCUMENTO', 'RECIBIDO', 'VALIDANDO_DOCUMENTO', 'PROCESANDO')
   OR (a.status = 'ERROR');

COMMENT ON VIEW talentflow.vw_bot_pendientes IS 'Vista de solo lectura para el bot de Telegram: postulaciones que aun requieren atencion de RRHH.';

CREATE VIEW talentflow.vw_bot_metricas AS
SELECT
    v.id AS vacancy_id,
    v.code,
    v.title,
    v.status AS vacante_estado,
    count(a.id) AS total_postulaciones,
    count(a.id) FILTER (WHERE a.status IN ('PENDIENTE_REVISION', 'EN_REVISION', 'REVISION_DOCUMENTO', 'RECIBIDO', 'VALIDANDO_DOCUMENTO', 'PROCESANDO')) AS pendientes,
    count(a.id) FILTER (WHERE a.status = 'ENTREVISTA') AS en_entrevista,
    count(a.id) FILTER (WHERE a.status = 'FINALIZADO') AS finalizados,
    count(a.id) FILTER (WHERE a.status = 'ERROR') AS con_error,
    round(avg(se.total_score), 2) AS score_promedio,
    max(se.total_score) AS score_maximo
FROM talentflow.vacancies v
LEFT JOIN talentflow.applications a ON a.vacancy_id = v.id
LEFT JOIN LATERAL (
    SELECT s.total_score
    FROM talentflow.score_evaluations s
    WHERE s.application_id = a.id
    ORDER BY s.calculated_at DESC
    LIMIT 1
) se ON a.id IS NOT NULL
GROUP BY v.id, v.code, v.title, v.status;

COMMENT ON VIEW talentflow.vw_bot_metricas IS 'Vista de solo lectura para el bot de Telegram: metricas agregadas por vacante.';

CREATE VIEW talentflow.vw_bot_authorized_users AS
SELECT
    telegram_user_id,
    hr_user_id,
    telegram_display_name,
    is_active
FROM talentflow.bot_authorized_telegram_users;

COMMENT ON VIEW talentflow.vw_bot_authorized_users IS 'Vista de solo lectura para el bot de Telegram: lista blanca de telegram_user_id autorizados.';

-- ---------------------------------------------------------------------
-- Capa 1: rol Postgres propio, sin atributos de superusuario/creacion,
-- con transacciones forzadas a solo lectura como respaldo adicional a
-- los GRANT explicitos.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'talentflow_bot_readonly') THEN
        CREATE ROLE talentflow_bot_readonly
            LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            CONNECTION LIMIT 5
            PASSWORD 'REPLACE_WITH_BOT_READONLY_PASSWORD';
    END IF;
END
$$;

ALTER ROLE talentflow_bot_readonly SET default_transaction_read_only = on;
ALTER ROLE talentflow_bot_readonly SET statement_timeout = '5s';

COMMENT ON ROLE talentflow_bot_readonly IS
    'Modulo 9: usuario exclusivo del bot de Telegram. Solo SELECT sobre vistas vw_bot_*. Nunca usar para la app principal.';

-- Linea de base explicita: sin privilegios sobre nada por defecto.
REVOKE ALL ON SCHEMA public FROM talentflow_bot_readonly;
REVOKE ALL ON ALL TABLES IN SCHEMA talentflow FROM talentflow_bot_readonly;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM talentflow_bot_readonly;

-- Capa 2: unicamente USAGE sobre el esquema y SELECT sobre las vistas vw_bot_*.
GRANT USAGE ON SCHEMA talentflow TO talentflow_bot_readonly;
GRANT SELECT ON
    talentflow.vw_bot_vacantes,
    talentflow.vw_bot_candidatos,
    talentflow.vw_bot_resultados,
    talentflow.vw_bot_pendientes,
    talentflow.vw_bot_metricas,
    talentflow.vw_bot_authorized_users
TO talentflow_bot_readonly;

-- Ninguna vista futura debe otorgarse automaticamente: sin ALTER DEFAULT
-- PRIVILEGES para este rol, cada vista nueva requiere un GRANT explicito.

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('027', 'Module 9 Telegram bot read-only role, views and Telegram authorization whitelist');

COMMIT;
