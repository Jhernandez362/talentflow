BEGIN;

CREATE OR REPLACE FUNCTION talentflow.public_list_open_vacancies()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(
    jsonb_agg(to_jsonb(item) ORDER BY item.published_at DESC NULLS LAST),
    '[]'::jsonb
)
FROM (
    SELECT
        v.id,
        v.code,
        v.title,
        v.department,
        v.location,
        v.description,
        v.work_mode,
        v.contract_type,
        v.seniority_level,
        v.openings,
        v.salary_min,
        v.salary_max,
        v.salary_currency,
        v.salary_period,
        v.show_salary_publicly,
        v.planned_publish_at,
        v.closes_at,
        v.published_at
    FROM talentflow.vacancies v
    WHERE v.status = 'OPEN'
      AND (v.published_at IS NOT NULL OR v.planned_publish_at IS NOT NULL)
      AND (v.closes_at IS NULL OR v.closes_at > now())
) item;
$$;

CREATE OR REPLACE FUNCTION talentflow.public_get_vacancy(target_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'id', v.id,
    'code', v.code,
    'title', v.title,
    'description', v.description,
    'department', v.department,
    'location', v.location,
    'workMode', v.work_mode,
    'contractType', v.contract_type,
    'seniorityLevel', v.seniority_level,
    'openings', v.openings,
    'workday', v.workday,
    'schedule', v.schedule,
    'salaryMin', v.salary_min,
    'salaryMax', v.salary_max,
    'salaryCurrency', v.salary_currency,
    'salaryPeriod', v.salary_period,
    'showSalaryPublicly', v.show_salary_publicly,
    'plannedPublishAt', v.planned_publish_at,
    'closesAt', v.closes_at,
    'expectedStartDate', v.expected_start_date,
    'minimumExperienceMonths', v.minimum_experience_months,
    'minimumEducation', v.minimum_education,
    'relatedAcademicArea', v.related_academic_area,
    'benefits', COALESCE((
        SELECT jsonb_agg(to_jsonb(b) ORDER BY b.display_order)
        FROM talentflow.vacancy_benefits b
        WHERE b.vacancy_id = v.id
    ), '[]'::jsonb)
)
FROM talentflow.vacancies v
WHERE v.id = target_id AND v.status = 'OPEN';
$$;

CREATE OR REPLACE FUNCTION talentflow.public_apply_to_vacancy(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    target_vacancy_id uuid := NULLIF(payload->>'vacancyId', '')::uuid;
    full_name text := btrim(COALESCE(payload->>'fullName', ''));
    email_address text := lower(btrim(COALESCE(payload->>'email', '')));
    phone text := NULLIF(btrim(COALESCE(payload->>'phone', '')), '');
    location text := NULLIF(btrim(COALESCE(payload->>'location', '')), '');
    consent_accepted boolean := COALESCE((payload->>'consentAccepted')::boolean, false);
    source text := COALESCE(NULLIF(btrim(COALESCE(payload->>'source', 'WEB')), ''), 'WEB');
    cv_file_name text := NULLIF(btrim(COALESCE(payload->>'cvFileName', '')), '');
    cv_mime_type text := lower(COALESCE(payload->>'cvMimeType', 'application/pdf'));
    cv_size_bytes bigint := COALESCE((payload->>'cvSizeBytes')::bigint, 0);
    new_candidate_id uuid;
    new_application_id uuid;
    new_cv_reference_id uuid;
BEGIN
    IF target_vacancy_id IS NULL THEN
        RAISE EXCEPTION 'Debe indicar una vacante válida';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM talentflow.vacancies v
        WHERE v.id = target_vacancy_id AND v.status = 'OPEN'
    ) THEN
        RAISE EXCEPTION 'La vacante no está abierta para postulaciones';
    END IF;

    IF full_name = '' THEN
        RAISE EXCEPTION 'El nombre completo es obligatorio';
    END IF;

    IF email_address = '' THEN
        RAISE EXCEPTION 'El correo es obligatorio';
    END IF;

    IF consent_accepted = false THEN
        RAISE EXCEPTION 'Debe aceptar el tratamiento de datos para continuar';
    END IF;

    IF cv_file_name IS NULL OR lower(right(cv_file_name, 4)) <> '.pdf' THEN
        RAISE EXCEPTION 'El CV debe ser un archivo PDF';
    END IF;

    IF cv_mime_type <> '' AND cv_mime_type <> 'application/pdf' THEN
        RAISE EXCEPTION 'El CV debe estar en formato PDF';
    END IF;

    IF cv_size_bytes <= 0 OR cv_size_bytes > 5242880 THEN
        RAISE EXCEPTION 'El archivo debe pesar entre 1 byte y 5 MB';
    END IF;

    INSERT INTO talentflow.candidates (email, full_name, phone, location, consent_at)
    VALUES (email_address, full_name, phone, location, now())
    ON CONFLICT (email)
    DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone = EXCLUDED.phone,
        location = EXCLUDED.location,
        consent_at = COALESCE(talentflow.candidates.consent_at, now()),
        updated_at = now()
    RETURNING id INTO new_candidate_id;

    IF EXISTS (
        SELECT 1
        FROM talentflow.applications a
        WHERE a.vacancy_id = target_vacancy_id AND a.candidate_id = new_candidate_id
    ) THEN
        RAISE EXCEPTION 'Ya existe una postulación para esta vacante';
    END IF;

    new_application_id := gen_random_uuid();

    INSERT INTO talentflow.applications (
        id,
        vacancy_id,
        candidate_id,
        status,
        priority,
        source,
        revision_manual_autorizada,
        applied_at
    )
    VALUES (
        new_application_id,
        target_vacancy_id,
        new_candidate_id,
        'RECEIVED',
        'NORMAL',
        source,
        false,
        now()
    );

    INSERT INTO talentflow.cv_references (
        candidate_id,
        application_id,
        drive_file_id,
        original_filename,
        mime_type,
        size_bytes,
        is_current,
        uploaded_at
    )
    VALUES (
        new_candidate_id,
        new_application_id,
        'LOCAL_UPLOAD_' || gen_random_uuid(),
        cv_file_name,
        cv_mime_type,
        cv_size_bytes,
        true,
        now()
    )
    RETURNING id INTO new_cv_reference_id;

    INSERT INTO talentflow.document_processing_attempts (
        cv_reference_id,
        attempt_number,
        status,
        processor,
        started_at,
        finished_at
    )
    VALUES (
        new_cv_reference_id,
        1,
        'SUCCEEDED',
        'CLIENT_VALIDATION',
        now(),
        now()
    );

    RETURN jsonb_build_object(
        'status', 'created',
        'application', jsonb_build_object(
            'id', new_application_id,
            'status', 'RECEIVED'
        ),
        'candidate', jsonb_build_object(
            'id', new_candidate_id,
            'email', email_address
        ),
        'cv', jsonb_build_object(
            'filename', cv_file_name,
            'mimeType', cv_mime_type,
            'sizeBytes', cv_size_bytes,
            'validatedPdf', true
        )
    );
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('010', 'Public vacancy listing and application flow')
ON CONFLICT (version) DO NOTHING;

COMMIT;
