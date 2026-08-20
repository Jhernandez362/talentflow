BEGIN;

DO $$
DECLARE
    vacancy_id uuid;
    base_payload jsonb;
    result jsonb;
BEGIN
    SELECT id INTO vacancy_id
    FROM talentflow.vacancies
    WHERE status = 'OPEN'
      AND COALESCE(planned_publish_at, published_at, now()) <= now()
      AND (closes_at IS NULL OR closes_at > now())
    ORDER BY created_at DESC
    LIMIT 1;

    IF vacancy_id IS NULL THEN
        RAISE EXCEPTION 'La prueba necesita una vacante abierta';
    END IF;

    base_payload := jsonb_build_object(
        'vacancyId', vacancy_id,
        'firstName', 'Validación',
        'lastName', 'Formulario',
        'email', 'validation-form-test@example.invalid',
        'phone', '+57 300 123 4567',
        'consentAccepted', true,
        'experienceYears', 2.5,
        'skills', jsonb_build_array('Unity', 'C#')
    );

    BEGIN
        PERFORM talentflow.public_begin_application(base_payload || '{"phone":"312gfdg"}'::jsonb);
        RAISE EXCEPTION 'Se aceptó un teléfono con letras';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'Se aceptó un teléfono con letras' OR SQLERRM NOT ILIKE '%teléfono%' THEN
            RAISE;
        END IF;
    END;

    BEGIN
        PERFORM talentflow.public_begin_application(base_payload || '{"firstName":"Jhohan2"}'::jsonb);
        RAISE EXCEPTION 'Se aceptó un nombre con números';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'Se aceptó un nombre con números' OR SQLERRM NOT ILIKE '%nombre%' THEN
            RAISE;
        END IF;
    END;

    BEGIN
        PERFORM talentflow.public_begin_application(base_payload || '{"experienceYears":0.3}'::jsonb);
        RAISE EXCEPTION 'Se aceptó una fracción de experiencia inválida';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'Se aceptó una fracción de experiencia inválida' OR SQLERRM NOT ILIKE '%experiencia%' THEN
            RAISE;
        END IF;
    END;

    BEGIN
        PERFORM talentflow.public_begin_application(base_payload || '{"skills":[]}'::jsonb);
        RAISE EXCEPTION 'Se aceptó una lista vacía de conocimientos';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'Se aceptó una lista vacía de conocimientos' OR SQLERRM NOT ILIKE '%conocimientos%' THEN
            RAISE;
        END IF;
    END;

    result := talentflow.public_begin_application(base_payload);
    IF NULLIF(result->>'applicationId', '') IS NULL THEN
        RAISE EXCEPTION 'Una postulación válida no devolvió applicationId';
    END IF;
END;
$$;

ROLLBACK;
