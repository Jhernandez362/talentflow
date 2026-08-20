\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    vacancy_id uuid;
    first_app jsonb;
    valid_app jsonb;
    attempt_result jsonb;
    attempt integer;
BEGIN
    SELECT id INTO vacancy_id
    FROM talentflow.vacancies
    WHERE status = 'OPEN' AND (closes_at IS NULL OR closes_at > now())
    ORDER BY created_at
    LIMIT 1;
    IF vacancy_id IS NULL THEN RAISE EXCEPTION 'Se requiere una vacante abierta'; END IF;

    first_app := talentflow.public_begin_application(jsonb_build_object(
        'vacancyId', vacancy_id, 'firstName', 'Prueba', 'lastName', 'Tres Intentos',
        'email', 'module4-three-attempts@example.test', 'phone', '3001234567',
        'experienceYears', 2.5, 'skills', jsonb_build_array('PostgreSQL', 'React'),
        'consentAccepted', true
    ));
    IF first_app->>'ticketId' !~ '^TF-[0-9]{4}-[0-9]{6}$' THEN
        RAISE EXCEPTION 'Ticket inválido: %', first_app->>'ticketId';
    END IF;

    FOR attempt IN 1..3 LOOP
        attempt_result := talentflow.public_record_document_attempt(jsonb_build_object(
            'applicationId', first_app->>'applicationId', 'valid', false,
            'errorType', 'DOCUMENT_ERROR', 'errorCode', 'INSUFFICIENT_TEXT',
            'errorMessage', 'PDF de prueba sin texto', 'originalFilename', 'scan.pdf',
            'mimeType', 'application/pdf', 'sizeBytes', 1200
        ));
        IF (attempt_result->>'attemptNumber')::integer <> attempt THEN
            RAISE EXCEPTION 'Número de intento incorrecto';
        END IF;
    END LOOP;
    IF COALESCE((attempt_result->>'canRequestManualReview')::boolean, false) = false THEN
        RAISE EXCEPTION 'El tercer intento debe habilitar revisión manual';
    END IF;

    BEGIN
        PERFORM talentflow.public_request_manual_review(jsonb_build_object(
            'applicationId', first_app->>'applicationId', 'authorized', false,
            'driveFileId', 'should-not-be-used'
        ));
        RAISE EXCEPTION 'La revisión sin autorización debió fallar';
    EXCEPTION WHEN others THEN
        IF position('autorización explícita' in SQLERRM) = 0 THEN RAISE; END IF;
    END;

    PERFORM talentflow.public_request_manual_review(jsonb_build_object(
        'applicationId', first_app->>'applicationId', 'authorized', true,
        'reason', 'Tres intentos sin texto', 'driveFileId', 'drive-manual-module4-test',
        'originalFilename', 'scan.pdf', 'mimeType', 'application/pdf', 'sizeBytes', 1200
    ));

    IF NOT EXISTS (
        SELECT 1 FROM talentflow.applications
        WHERE id = (first_app->>'applicationId')::uuid
          AND status = 'REVISION_DOCUMENTO' AND revision_manual_autorizada
    ) THEN RAISE EXCEPTION 'No quedó en revisión manual'; END IF;

    valid_app := talentflow.public_begin_application(jsonb_build_object(
        'vacancyId', vacancy_id, 'firstName', 'Prueba', 'lastName', 'PDF Valido',
        'email', 'module4-valid@example.test', 'phone', '3002223344', 'experienceYears', 1,
        'skills', jsonb_build_array('Java'), 'consentAccepted', true
    ));
    attempt_result := talentflow.public_record_document_attempt(jsonb_build_object(
        'applicationId', valid_app->>'applicationId', 'valid', true,
        'driveFileId', 'drive-valid-module4-test', 'driveReference', 'private-reference',
        'originalFilename', 'valid.pdf', 'mimeType', 'application/pdf', 'sizeBytes', 2400
    ));
    IF attempt_result->>'status' <> 'RECIBIDO' THEN
        RAISE EXCEPTION 'El PDF válido no terminó en RECIBIDO';
    END IF;

    BEGIN
        PERFORM talentflow.public_begin_application(jsonb_build_object(
            'vacancyId', vacancy_id, 'firstName', 'Prueba', 'lastName', 'PDF Valido',
            'email', 'module4-valid@example.test', 'phone', '3002223344', 'experienceYears', 1,
            'skills', jsonb_build_array('Java'), 'consentAccepted', true
        ));
        RAISE EXCEPTION 'El duplicado debió fallar';
    EXCEPTION WHEN others THEN
        IF position('postulación activa' in SQLERRM) = 0 THEN RAISE; END IF;
    END;

    IF EXISTS (SELECT 1 FROM talentflow.ai_analyses WHERE application_id IN (
        (first_app->>'applicationId')::uuid, (valid_app->>'applicationId')::uuid
    )) THEN RAISE EXCEPTION 'El módulo 4 no debe ejecutar IA'; END IF;
END;
$$;

ROLLBACK;

SELECT 'Module 4 application flow test passed and rolled back' AS result;
