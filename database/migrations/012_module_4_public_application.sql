BEGIN;

CREATE SEQUENCE IF NOT EXISTS talentflow.application_ticket_seq;

ALTER TABLE talentflow.candidates
    ADD COLUMN IF NOT EXISTS declared_experience_years numeric(5,2),
    ADD COLUMN IF NOT EXISTS declared_skills text[] NOT NULL DEFAULT '{}';

ALTER TABLE talentflow.applications
    ADD COLUMN IF NOT EXISTS ticket_id varchar(24),
    ADD COLUMN IF NOT EXISTS manual_review_reason text,
    ADD COLUMN IF NOT EXISTS manual_review_requested_at timestamptz;

UPDATE talentflow.applications
SET ticket_id = 'TF-' || to_char(applied_at, 'YYYY') || '-' ||
    lpad(nextval('talentflow.application_ticket_seq')::text, 6, '0')
WHERE ticket_id IS NULL;

ALTER TABLE talentflow.applications
    ALTER COLUMN ticket_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS applications_ticket_id_unique_idx
    ON talentflow.applications (ticket_id);

ALTER TABLE talentflow.applications
    DROP CONSTRAINT IF EXISTS applications_status_valid;

ALTER TABLE talentflow.applications
    ADD CONSTRAINT applications_status_valid CHECK (status IN (
        'RECEIVED', 'PROCESSING', 'READY_FOR_REVIEW', 'IN_REVIEW', 'ON_HOLD',
        'ADVANCED', 'REJECTED', 'WITHDRAWN', 'RECIBIDO',
        'VALIDANDO_DOCUMENTO', 'REVISION_DOCUMENTO', 'PROCESANDO', 'ERROR'
    ));

ALTER TABLE talentflow.document_processing_attempts
    ADD COLUMN IF NOT EXISTS application_id uuid REFERENCES talentflow.applications(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS error_type varchar(30),
    ADD COLUMN IF NOT EXISTS original_filename varchar(255),
    ADD COLUMN IF NOT EXISTS mime_type varchar(100),
    ADD COLUMN IF NOT EXISTS size_bytes bigint,
    ADD COLUMN IF NOT EXISTS sha256 char(64);

ALTER TABLE talentflow.document_processing_attempts
    ALTER COLUMN cv_reference_id DROP NOT NULL;

ALTER TABLE talentflow.document_processing_attempts
    DROP CONSTRAINT IF EXISTS processing_error_type_valid,
    DROP CONSTRAINT IF EXISTS processing_attempt_file_size_valid;

ALTER TABLE talentflow.document_processing_attempts
    ADD CONSTRAINT processing_error_type_valid
        CHECK (error_type IS NULL OR error_type IN ('DOCUMENT_ERROR', 'SYSTEM_ERROR')),
    ADD CONSTRAINT processing_attempt_file_size_valid
        CHECK (size_bytes IS NULL OR size_bytes >= 0);

CREATE UNIQUE INDEX IF NOT EXISTS processing_application_attempt_unique_idx
    ON talentflow.document_processing_attempts (application_id, attempt_number)
    WHERE application_id IS NOT NULL;

CREATE OR REPLACE FUNCTION talentflow.next_application_ticket()
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
    SELECT 'TF-' || to_char(current_date, 'YYYY') || '-' ||
           lpad(nextval('talentflow.application_ticket_seq')::text, 6, '0');
$$;

CREATE OR REPLACE FUNCTION talentflow.public_begin_application(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    target_vacancy_id uuid := NULLIF(payload->>'vacancyId', '')::uuid;
    first_name text := btrim(COALESCE(payload->>'firstName', ''));
    last_name text := btrim(COALESCE(payload->>'lastName', ''));
    email_address text := lower(btrim(COALESCE(payload->>'email', '')));
    phone_number text := NULLIF(btrim(COALESCE(payload->>'phone', '')), '');
    consent_accepted boolean := COALESCE((payload->>'consentAccepted')::boolean, false);
    experience_years numeric := COALESCE(NULLIF(payload->>'experienceYears', '')::numeric, 0);
    skills text[] := ARRAY(
        SELECT left(btrim(value), 80)
        FROM jsonb_array_elements_text(COALESCE(payload->'skills', '[]'::jsonb)) value
        WHERE btrim(value) <> ''
        LIMIT 30
    );
    target_candidate_id uuid;
    target_application talentflow.applications%ROWTYPE;
BEGIN
    IF target_vacancy_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM talentflow.vacancies v
        WHERE v.id = target_vacancy_id
          AND v.status = 'OPEN'
          AND COALESCE(v.planned_publish_at, v.published_at, now()) <= now()
          AND (v.closes_at IS NULL OR v.closes_at > now())
    ) THEN
        RAISE EXCEPTION 'La vacante no está abierta para postulaciones';
    END IF;

    IF first_name = '' OR last_name = '' THEN
        RAISE EXCEPTION 'Nombre y apellidos son obligatorios';
    END IF;
    IF email_address !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
        RAISE EXCEPTION 'El correo electrónico no es válido';
    END IF;
    IF NOT consent_accepted THEN
        RAISE EXCEPTION 'Debe aceptar el tratamiento de datos para continuar';
    END IF;
    IF experience_years < 0 OR experience_years > 80 THEN
        RAISE EXCEPTION 'Los años de experiencia no son válidos';
    END IF;

    INSERT INTO talentflow.candidates (
        email, full_name, phone, consent_at,
        declared_experience_years, declared_skills
    ) VALUES (
        email_address, left(first_name || ' ' || last_name, 180), phone_number,
        now(), experience_years, skills
    )
    ON CONFLICT (email) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone = EXCLUDED.phone,
        consent_at = COALESCE(talentflow.candidates.consent_at, now()),
        declared_experience_years = EXCLUDED.declared_experience_years,
        declared_skills = EXCLUDED.declared_skills,
        updated_at = now()
    RETURNING id INTO target_candidate_id;

    SELECT a.* INTO target_application
    FROM talentflow.applications a
    WHERE a.vacancy_id = target_vacancy_id
      AND a.candidate_id = target_candidate_id;

    IF FOUND
       AND target_application.status NOT IN ('ERROR', 'VALIDANDO_DOCUMENTO', 'RECEIVED') THEN
        RAISE EXCEPTION 'Ya existe una postulación activa para esta vacante';
    END IF;

    IF NOT FOUND THEN
        INSERT INTO talentflow.applications (
            vacancy_id, candidate_id, ticket_id, status, priority, source,
            revision_manual_autorizada
        ) VALUES (
            target_vacancy_id, target_candidate_id,
            talentflow.next_application_ticket(), 'VALIDANDO_DOCUMENTO',
            'NORMAL', 'WEB', false
        ) RETURNING * INTO target_application;
    ELSE
        UPDATE talentflow.applications
        SET status = 'VALIDANDO_DOCUMENTO', updated_at = now()
        WHERE id = target_application.id
        RETURNING * INTO target_application;
    END IF;

    RETURN jsonb_build_object(
        'applicationId', target_application.id,
        'ticketId', target_application.ticket_id,
        'attemptNumber', 1 + (
            SELECT count(*) FROM talentflow.document_processing_attempts d
            WHERE d.application_id = target_application.id
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.public_record_document_attempt(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    target_application_id uuid := NULLIF(payload->>'applicationId', '')::uuid;
    is_valid boolean := COALESCE((payload->>'valid')::boolean, false);
    attempt_no integer;
    target_cv_id uuid;
    target_ticket text;
    result_status text;
    document_error_count integer;
BEGIN
    SELECT a.ticket_id INTO target_ticket
    FROM talentflow.applications a
    WHERE a.id = target_application_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Postulación no encontrada'; END IF;

    SELECT count(*) + 1 INTO attempt_no
    FROM talentflow.document_processing_attempts d
    WHERE d.application_id = target_application_id;

    IF is_valid THEN
        IF NULLIF(payload->>'driveFileId', '') IS NULL THEN
            RAISE EXCEPTION 'No se recibió la referencia privada del CV';
        END IF;

        UPDATE talentflow.cv_references
        SET is_current = false, updated_at = now()
        WHERE application_id = target_application_id AND is_current;

        INSERT INTO talentflow.cv_references (
            candidate_id, application_id, drive_file_id, drive_web_view_link,
            original_filename, mime_type, size_bytes, sha256, is_current
        )
        SELECT a.candidate_id, a.id, payload->>'driveFileId',
               NULLIF(payload->>'driveReference', ''),
               left(COALESCE(NULLIF(payload->>'originalFilename', ''), 'cv.pdf'), 255),
               COALESCE(NULLIF(payload->>'mimeType', ''), 'application/pdf'),
               NULLIF(payload->>'sizeBytes', '')::bigint,
               NULLIF(payload->>'sha256', ''), true
        FROM talentflow.applications a WHERE a.id = target_application_id
        RETURNING id INTO target_cv_id;
        result_status := 'RECIBIDO';
    ELSE
        result_status := 'ERROR';
    END IF;

    INSERT INTO talentflow.document_processing_attempts (
        cv_reference_id, application_id, attempt_number, status, processor,
        error_type, error_code, error_message, original_filename, mime_type,
        size_bytes, sha256, started_at, finished_at
    ) VALUES (
        target_cv_id, target_application_id, attempt_no,
        CASE WHEN is_valid THEN 'SUCCEEDED' ELSE 'FAILED' END,
        'N8N_PDF_VALIDATION', NULLIF(payload->>'errorType', ''),
        NULLIF(payload->>'errorCode', ''), NULLIF(payload->>'errorMessage', ''),
        left(NULLIF(payload->>'originalFilename', ''), 255),
        NULLIF(payload->>'mimeType', ''), NULLIF(payload->>'sizeBytes', '')::bigint,
        NULLIF(payload->>'sha256', ''), now(), now()
    );

    UPDATE talentflow.applications
    SET status = result_status, updated_at = now()
    WHERE id = target_application_id;

    SELECT count(*) INTO document_error_count
    FROM talentflow.document_processing_attempts d
    WHERE d.application_id = target_application_id
      AND d.status = 'FAILED'
      AND d.error_type = 'DOCUMENT_ERROR';

    RETURN jsonb_build_object(
        'ticketId', target_ticket,
        'applicationId', target_application_id,
        'status', result_status,
        'attemptNumber', CASE WHEN is_valid THEN attempt_no ELSE document_error_count END,
        'canRequestManualReview', (NOT is_valid AND NULLIF(payload->>'errorType', '') = 'DOCUMENT_ERROR' AND document_error_count >= 3),
        'errorType', NULLIF(payload->>'errorType', ''),
        'errorCode', NULLIF(payload->>'errorCode', '')
    );
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.public_request_manual_review(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    target_application_id uuid := NULLIF(payload->>'applicationId', '')::uuid;
    authorized boolean := COALESCE((payload->>'authorized')::boolean, false);
    attempt_count integer;
    target_ticket text;
BEGIN
    IF NOT authorized THEN
        RAISE EXCEPTION 'La revisión manual requiere autorización explícita';
    END IF;

    SELECT a.ticket_id,
           (SELECT count(*) FROM talentflow.document_processing_attempts d
           WHERE d.application_id = a.id AND d.status = 'FAILED'
             AND d.error_type = 'DOCUMENT_ERROR')
    INTO target_ticket, attempt_count
    FROM talentflow.applications a
    WHERE a.id = target_application_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Postulación no encontrada'; END IF;
    IF attempt_count < 3 THEN
        RAISE EXCEPTION 'La revisión manual está disponible después de tres intentos fallidos';
    END IF;
    IF NULLIF(payload->>'driveFileId', '') IS NULL THEN
        RAISE EXCEPTION 'No se recibió la referencia privada del documento';
    END IF;

    UPDATE talentflow.cv_references SET is_current = false, updated_at = now()
    WHERE application_id = target_application_id AND is_current;

    INSERT INTO talentflow.cv_references (
        candidate_id, application_id, drive_file_id, drive_web_view_link,
        original_filename, mime_type, size_bytes, sha256, is_current
    )
    SELECT a.candidate_id, a.id, payload->>'driveFileId',
           NULLIF(payload->>'driveReference', ''),
           left(COALESCE(NULLIF(payload->>'originalFilename', ''), 'cv.pdf'), 255),
           COALESCE(NULLIF(payload->>'mimeType', ''), 'application/pdf'),
           NULLIF(payload->>'sizeBytes', '')::bigint,
           NULLIF(payload->>'sha256', ''), true
    FROM talentflow.applications a WHERE a.id = target_application_id;

    UPDATE talentflow.applications
    SET revision_manual_autorizada = true,
        manual_review_reason = left(COALESCE(NULLIF(payload->>'reason', ''), 'PDF sin texto extraíble'), 500),
        manual_review_requested_at = now(), status = 'REVISION_DOCUMENTO', updated_at = now()
    WHERE id = target_application_id;

    RETURN jsonb_build_object(
        'ticketId', target_ticket,
        'applicationId', target_application_id,
        'status', 'REVISION_DOCUMENTO',
        'attempts', attempt_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.public_list_open_vacancies()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.published_at DESC NULLS LAST), '[]'::jsonb)
FROM (
    SELECT v.id, v.code, v.title, v.department, v.location, v.description,
           v.work_mode, v.contract_type, v.seniority_level, v.openings,
           v.salary_min, v.salary_max, v.salary_currency, v.salary_period,
           v.show_salary_publicly, v.planned_publish_at, v.closes_at, v.published_at,
           COALESCE((SELECT jsonb_agg(jsonb_build_object('name', b.name)
                    ORDER BY b.display_order)
                     FROM talentflow.vacancy_benefits b WHERE b.vacancy_id = v.id), '[]'::jsonb) benefits
    FROM talentflow.vacancies v
    WHERE v.status = 'OPEN'
      AND COALESCE(v.planned_publish_at, v.published_at, now()) <= now()
      AND (v.closes_at IS NULL OR v.closes_at > now())
) item;
$$;

CREATE OR REPLACE FUNCTION talentflow.public_get_vacancy(target_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'id', v.id, 'code', v.code, 'title', v.title, 'description', v.description,
    'department', v.department, 'location', v.location, 'workMode', v.work_mode,
    'contractType', v.contract_type, 'seniorityLevel', v.seniority_level,
    'openings', v.openings, 'workday', v.workday, 'schedule', v.schedule,
    'salaryMin', v.salary_min, 'salaryMax', v.salary_max,
    'salaryCurrency', v.salary_currency, 'salaryPeriod', v.salary_period,
    'showSalaryPublicly', v.show_salary_publicly, 'closesAt', v.closes_at,
    'minimumExperienceMonths', v.minimum_experience_months,
    'minimumEducation', v.minimum_education, 'educationRequired', v.education_required,
    'relatedAcademicArea', v.related_academic_area,
    'requirements', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'name', c.name, 'description', c.description, 'required', c.is_required,
            'type', c.criterion_type
        ) ORDER BY c.evaluation_order)
        FROM talentflow.scoring_config_versions scv
        JOIN talentflow.scoring_criteria c ON c.scoring_config_version_id = scv.id
        WHERE scv.vacancy_id = v.id AND scv.status = 'ACTIVE'
    ), '[]'::jsonb),
    'desirables', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', d.name, 'description', d.description)
                         ORDER BY d.display_order)
        FROM talentflow.scoring_config_versions scv
        JOIN talentflow.desirable_requirements d ON d.scoring_config_version_id = scv.id
        WHERE scv.vacancy_id = v.id AND scv.status = 'ACTIVE'
    ), '[]'::jsonb),
    'benefits', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', b.name)
                         ORDER BY b.display_order)
        FROM talentflow.vacancy_benefits b WHERE b.vacancy_id = v.id
    ), '[]'::jsonb)
)
FROM talentflow.vacancies v
WHERE v.id = target_id AND v.status = 'OPEN'
  AND COALESCE(v.planned_publish_at, v.published_at, now()) <= now()
  AND (v.closes_at IS NULL OR v.closes_at > now());
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('012', 'Module 4 public applications, document attempts and manual review')
ON CONFLICT (version) DO NOTHING;

COMMIT;
