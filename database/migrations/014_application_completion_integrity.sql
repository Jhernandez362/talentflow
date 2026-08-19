BEGIN;

-- Normaliza registros heredados que nunca completaron el procesamiento del PDF.
UPDATE talentflow.applications application
SET status = 'ERROR', updated_at = now()
WHERE application.status IN ('VALIDANDO_DOCUMENTO', 'RECEIVED')
  AND NOT EXISTS (
      SELECT 1
      FROM talentflow.document_processing_attempts attempt
      WHERE attempt.application_id = application.id
        AND attempt.status = 'SUCCEEDED'
  );

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
        WHERE btrim(value) <> '' LIMIT 30
    );
    target_candidate_id uuid;
    target_application talentflow.applications%ROWTYPE;
BEGIN
    IF target_vacancy_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM talentflow.vacancies v
        WHERE v.id = target_vacancy_id AND v.status = 'OPEN'
          AND COALESCE(v.planned_publish_at, v.published_at, now()) <= now()
          AND (v.closes_at IS NULL OR v.closes_at > now())
    ) THEN RAISE EXCEPTION 'La vacante no está abierta para postulaciones'; END IF;

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

CREATE OR REPLACE FUNCTION talentflow.admin_list_candidates()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id, 'ticket', a.ticket_id, 'full_name', c.full_name,
    'vacancy_title', v.title, 'score', COALESCE(latest_score.total_score, 0),
    'priority', a.priority, 'status', a.status, 'applied_at', a.applied_at
) ORDER BY a.applied_at DESC), '[]'::jsonb)
FROM talentflow.applications a
JOIN talentflow.candidates c ON c.id = a.candidate_id
JOIN talentflow.vacancies v ON v.id = a.vacancy_id
LEFT JOIN LATERAL (
    SELECT se.total_score FROM talentflow.score_evaluations se
    WHERE se.application_id = a.id
    ORDER BY se.calculated_at DESC LIMIT 1
) latest_score ON true
WHERE EXISTS (
    SELECT 1 FROM talentflow.document_processing_attempts attempt
    WHERE attempt.application_id = a.id AND attempt.status = 'SUCCEEDED'
)
AND EXISTS (
    SELECT 1 FROM talentflow.cv_references cv
    WHERE cv.application_id = a.id AND cv.is_current
);
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('014', 'Only completed applications are candidates and incomplete submissions remain retryable')
ON CONFLICT (version) DO NOTHING;

COMMIT;
