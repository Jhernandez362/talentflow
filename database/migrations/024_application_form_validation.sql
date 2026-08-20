BEGIN;

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
    phone_digits text := regexp_replace(COALESCE(phone_number, ''), '[^0-9]', '', 'g');
    consent_accepted boolean := COALESCE((payload->>'consentAccepted')::boolean, false);
    experience_years numeric := COALESCE(NULLIF(payload->>'experienceYears', '')::numeric, 0);
    raw_skills jsonb := COALESCE(payload->'skills', '[]'::jsonb);
    skills text[] := CASE
        WHEN jsonb_typeof(raw_skills) = 'array' THEN ARRAY(
            SELECT btrim(value)
            FROM jsonb_array_elements_text(raw_skills) value
            WHERE btrim(value) <> ''
        )
        ELSE ARRAY[]::text[]
    END;
    target_candidate_id uuid;
    target_application talentflow.applications%ROWTYPE;
BEGIN
    IF target_vacancy_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM talentflow.vacancies v
        WHERE v.id = target_vacancy_id AND v.status = 'OPEN'
          AND COALESCE(v.planned_publish_at, v.published_at, now()) <= now()
          AND (v.closes_at IS NULL OR v.closes_at > now())
    ) THEN RAISE EXCEPTION 'La vacante no está abierta para postulaciones'; END IF;

    IF char_length(first_name) NOT BETWEEN 2 AND 80
       OR first_name !~ '^[[:alpha:]áéíóúüñÁÉÍÓÚÜÑ]+([ ''-][[:alpha:]áéíóúüñÁÉÍÓÚÜÑ]+)*$' THEN
        RAISE EXCEPTION 'El nombre no es válido';
    END IF;
    IF char_length(last_name) NOT BETWEEN 2 AND 100
       OR last_name !~ '^[[:alpha:]áéíóúüñÁÉÍÓÚÜÑ]+([ ''-][[:alpha:]áéíóúüñÁÉÍÓÚÜÑ]+)*$' THEN
        RAISE EXCEPTION 'Los apellidos no son válidos';
    END IF;
    IF email_address !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
        RAISE EXCEPTION 'El correo electrónico no es válido';
    END IF;
    IF phone_number IS NULL OR phone_number !~ '^\+?[0-9 ().-]+$'
       OR char_length(phone_digits) NOT BETWEEN 7 AND 15 THEN
        RAISE EXCEPTION 'El teléfono debe contener entre 7 y 15 dígitos válidos';
    END IF;
    IF NOT consent_accepted THEN
        RAISE EXCEPTION 'Debe aceptar el tratamiento de datos para continuar';
    END IF;
    IF experience_years < 0 OR experience_years > 80 OR mod(experience_years * 2, 1) <> 0 THEN
        RAISE EXCEPTION 'Los años de experiencia deben estar entre 0 y 80, en incrementos de medio año';
    END IF;
    IF jsonb_typeof(raw_skills) <> 'array' OR jsonb_array_length(raw_skills) > 30
       OR cardinality(skills) = 0
       OR EXISTS (SELECT 1 FROM unnest(skills) skill WHERE char_length(skill) NOT BETWEEN 2 AND 80) THEN
        RAISE EXCEPTION 'Debe ingresar entre 1 y 30 tecnologías o conocimientos válidos';
    END IF;

    INSERT INTO talentflow.candidates (
        email, full_name, phone, consent_at,
        declared_experience_years, declared_skills
    ) VALUES (
        email_address, first_name || ' ' || last_name, phone_number,
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

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('024', 'Validate public application form fields in the database')
ON CONFLICT (version) DO NOTHING;

COMMIT;
