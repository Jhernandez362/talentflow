\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    vacancy_id uuid; application_data jsonb; analysis_data jsonb; retry integer;
    structured_data jsonb := '{"experiencia_total_anios":2,"experiencias":[{"id":"EXP-1","empresa":"Empresa","cargo":"Desarrollador","fecha_inicio":"2022-01","fecha_fin":"2024-01","duracion_meses":24,"funciones":["Desarrollo"],"tecnologias":["Java"]}],"educacion":[],"cursos":[],"certificaciones":[],"idiomas":[],"habilidades":[{"nombre":"Java","evidencia_laboral":true,"experiencia_ids":["EXP-1"]}],"habilidades_declaradas_no_verificadas":["Docker"],"advertencias":[]}'::jsonb;
BEGIN
    SELECT id INTO vacancy_id FROM talentflow.vacancies
    WHERE status='OPEN' AND (closes_at IS NULL OR closes_at > now()) LIMIT 1;
    IF vacancy_id IS NULL THEN RAISE EXCEPTION 'Se requiere una vacante abierta'; END IF;

    application_data := talentflow.public_begin_application(jsonb_build_object(
        'vacancyId',vacancy_id,'firstName','Modulo','lastName','Cinco',
        'email','module5-success@example.test','experienceYears',2,
        'skills',jsonb_build_array('Java','Docker'),'consentAccepted',true));
    PERFORM talentflow.public_record_document_attempt(jsonb_build_object(
        'applicationId',application_data->>'applicationId','valid',true,
        'driveFileId','drive-module5-success','originalFilename','cv.pdf',
        'mimeType','application/pdf','sizeBytes',2000));
    analysis_data := talentflow.ia01_begin_analysis((application_data->>'applicationId')::uuid);
    PERFORM talentflow.ia01_complete_analysis((analysis_data->>'analysis_id')::uuid, structured_data);
    IF NOT EXISTS (SELECT 1 FROM talentflow.ai_analyses
        WHERE id=(analysis_data->>'analysis_id')::uuid AND status='SUCCEEDED'
          AND prompt_version='PROMPT-IA-01-v1' AND model='gemini-3.6-flash') THEN
        RAISE EXCEPTION 'No persistió metadata IA-01';
    END IF;
    IF EXISTS (SELECT 1 FROM talentflow.score_evaluations
        WHERE application_id=(application_data->>'applicationId')::uuid) THEN
        RAISE EXCEPTION 'IA-01 no debe calcular score';
    END IF;
    BEGIN
        PERFORM talentflow.ia01_complete_analysis((analysis_data->>'analysis_id')::uuid, NULL);
        RAISE EXCEPTION 'IA-01 debió rechazar una salida nula';
    EXCEPTION WHEN others THEN
        IF position('schema permitido' in SQLERRM)=0 THEN RAISE; END IF;
    END;

    application_data := talentflow.public_begin_application(jsonb_build_object(
        'vacancyId',vacancy_id,'firstName','Modulo','lastName','Retry',
        'email','module5-retry@example.test','experienceYears',0,
        'skills','[]'::jsonb,'consentAccepted',true));
    PERFORM talentflow.public_record_document_attempt(jsonb_build_object(
        'applicationId',application_data->>'applicationId','valid',true,
        'driveFileId','drive-module5-retry','originalFilename','cv.pdf',
        'mimeType','application/pdf','sizeBytes',2000));
    FOR retry IN 1..3 LOOP
        analysis_data := talentflow.ia01_begin_analysis((application_data->>'applicationId')::uuid);
        PERFORM talentflow.ia01_fail_analysis((analysis_data->>'analysis_id')::uuid,'JSON inválido de prueba');
    END LOOP;
    BEGIN
        PERFORM talentflow.ia01_begin_analysis((application_data->>'applicationId')::uuid);
        RAISE EXCEPTION 'El cuarto intento IA debió bloquearse';
    EXCEPTION WHEN others THEN
        IF position('3 intentos' in SQLERRM)=0 THEN RAISE; END IF;
    END;
END;
$$;
ROLLBACK;
SELECT 'Module 5 IA-01 persistence and retry test passed and rolled back' AS result;
