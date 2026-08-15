\set ON_ERROR_STOP on

BEGIN;

SELECT talentflow.admin_save_vacancy(
    jsonb_build_object(
        'title', 'Desarrollador Backend Público',
        'code', 'TF-PUBLIC-OPEN-01',
        'department', 'Tecnologia',
        'description', 'Vacante de prueba para el flujo público.',
        'workMode', 'REMOTE',
        'location', 'Bogotá, Colombia',
        'contractType', 'Tiempo completo',
        'seniorityLevel', 'JUNIOR',
        'openings', 2,
        'salaryMin', '2500000',
        'salaryMax', '3500000',
        'salaryCurrency', 'COP',
        'salaryPeriod', 'MONTH',
        'showSalaryPublicly', true,
        'plannedPublishAt', (now() - interval '1 day')::text,
        'closesAt', (now() + interval '30 days')::text,
        'responsibleHrUserId', '10000000-0000-4000-8000-000000000001',
        'benefits', jsonb_build_array(
            jsonb_build_object('name', 'Horario flexible', 'order', 0),
            jsonb_build_object('name', 'Seguro médico', 'order', 1)
        ),
        'criteria', jsonb_build_array(
            jsonb_build_object('name', 'Java', 'type', 'TECNOLOGIA', 'weight', 60, 'required', true, 'aliases', jsonb_build_array('Java SE'), 'order', 0),
            jsonb_build_object('name', 'SQL', 'type', 'CONOCIMIENTO', 'weight', 40, 'required', false, 'aliases', jsonb_build_array('PostgreSQL'), 'order', 1)
        ),
        'desirables', jsonb_build_array(
            jsonb_build_object('name', 'Docker', 'description', 'Contenedores', 'relevance', 'MEDIUM', 'order', 0)
        ),
        'addedValues', jsonb_build_array(
            jsonb_build_object('name', 'Metodología Scrum', 'description', 'Trabajo en equipo', 'type', 'SCRUM', 'relevance', 'MEDIUM', 'order', 0)
        )
    ),
    true
) AS published_vacancy;

DO $$
DECLARE
    target_vacancy_id uuid;
    application_status text;
    open_count integer;
BEGIN
    SELECT id INTO target_vacancy_id FROM talentflow.vacancies WHERE code = 'TF-PUBLIC-OPEN-01';
    IF target_vacancy_id IS NULL THEN
        RAISE EXCEPTION 'Vacancy did not exist after publication';
    END IF;

    SELECT jsonb_array_length(talentflow.public_list_open_vacancies()) INTO open_count;
    IF open_count < 1 THEN
        RAISE EXCEPTION 'Expected at least one public vacancy';
    END IF;

    IF talentflow.public_get_vacancy(target_vacancy_id)->>'title' IS NULL THEN
        RAISE EXCEPTION 'Public vacancy detail should include title';
    END IF;

    SELECT talentflow.public_apply_to_vacancy(jsonb_build_object(
        'vacancyId', target_vacancy_id,
        'fullName', 'Ana Candidata',
        'email', 'ana.candidata@example.com',
        'phone', '3001234567',
        'location', 'Bogotá',
        'consentAccepted', true,
        'cvFileName', 'ana-cv.pdf',
        'cvMimeType', 'application/pdf',
        'cvSizeBytes', 120000,
        'source', 'WEB'
    ))->>'status' INTO application_status;

    IF application_status IS NULL OR application_status <> 'created' THEN
        RAISE EXCEPTION 'Application record was not created';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM talentflow.applications a
        JOIN talentflow.candidates c ON c.id = a.candidate_id
        WHERE a.vacancy_id = target_vacancy_id AND c.email = 'ana.candidata@example.com'
    ) = false THEN
        RAISE EXCEPTION 'Application row not linked to candidate';
    END IF;
END;
$$;

DO $$
BEGIN
    PERFORM talentflow.public_apply_to_vacancy(jsonb_build_object(
        'vacancyId', (SELECT id FROM talentflow.vacancies WHERE code = 'TF-PUBLIC-OPEN-01'),
        'fullName', 'Ana Candidata',
        'email', 'ana.candidata@example.com',
        'phone', '3001234567',
        'location', 'Bogotá',
        'consentAccepted', true,
        'cvFileName', 'duplicate.pdf',
        'cvMimeType', 'application/pdf',
        'cvSizeBytes', 130000,
        'source', 'WEB'
    ));

    RAISE EXCEPTION 'La aplicación duplicada debería haber sido rechazada';
EXCEPTION
    WHEN others THEN
        IF position('Ya existe una postulación para esta vacante' in SQLERRM) = 0 THEN
            RAISE;
        END IF;
END $$;

ROLLBACK;
SELECT 'Public vacancy flow test passed and rolled back' AS result;
