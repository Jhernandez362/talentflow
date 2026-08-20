\set ON_ERROR_STOP on

SELECT CASE
    WHEN EXISTS (
        SELECT 1 FROM talentflow.vacancies
        WHERE code = 'TF-M6-TEST-20260820'
    ) THEN talentflow.admin_get_vacancy((
        SELECT id FROM talentflow.vacancies
        WHERE code = 'TF-M6-TEST-20260820'
    ))
    ELSE talentflow.admin_save_vacancy(
        jsonb_build_object(
            'code', 'TF-M6-TEST-20260820',
            'title', 'Desarrollador Full Stack - Prueba Motor de Compatibilidad',
            'department', 'Tecnologia',
            'description', 'Vacante controlada para validar el motor deterministico del Modulo 6.',
            'workMode', 'HYBRID',
            'location', 'Bogota, Colombia',
            'contractType', 'Termino indefinido',
            'seniorityLevel', 'MID',
            'openings', 1,
            'workday', 'Tiempo completo',
            'schedule', 'Lunes a viernes',
            'salaryCurrency', 'COP',
            'showSalaryPublicly', false,
            'plannedPublishAt', '2026-08-20T00:00:00-05:00',
            'closesAt', '2026-09-19T23:59:59-05:00',
            'expectedStartDate', '2026-10-01',
            'responsibleHrUserId', '10000000-0000-4000-8000-000000000001',
            'minimumExperienceMonths', 24,
            'expectedExperienceMinMonths', 24,
            'expectedExperienceMaxMonths', 48,
            'minimumEducation', 'TECHNICAL',
            'relatedAcademicArea', 'Sistemas, software o areas relacionadas',
            'educationRequired', true,
            'educationAffectsScore', true,
            'benefits', jsonb_build_array(
                jsonb_build_object('name', 'Horario flexible', 'order', 1),
                jsonb_build_object('name', 'Modalidad hibrida', 'order', 2),
                jsonb_build_object('name', 'Plan de formacion', 'order', 3)
            ),
            'criteria', jsonb_build_array(
                jsonb_build_object(
                    'name', 'React', 'type', 'TECNOLOGIA', 'weight', 30,
                    'required', true, 'aliases', jsonb_build_array('React.js', 'ReactJS'), 'order', 1
                ),
                jsonb_build_object(
                    'name', 'SQL', 'type', 'CONOCIMIENTO', 'weight', 20,
                    'required', true, 'aliases', jsonb_build_array('Structured Query Language'), 'order', 2
                ),
                jsonb_build_object(
                    'name', 'Experiencia relevante', 'type', 'EXPERIENCIA', 'weight', 25,
                    'required', true, 'aliases', '[]'::jsonb, 'order', 3
                ),
                jsonb_build_object(
                    'name', 'Educacion', 'type', 'EDUCACION', 'weight', 25,
                    'required', true, 'aliases', '[]'::jsonb, 'order', 4
                )
            ),
            'desirables', jsonb_build_array(
                jsonb_build_object('name', 'Docker', 'description', 'Contenedores', 'relevance', 'HIGH', 'order', 1),
                jsonb_build_object('name', 'Kubernetes', 'description', 'Orquestacion', 'relevance', 'MEDIUM', 'order', 2)
            ),
            'addedValues', jsonb_build_array(
                jsonb_build_object('name', 'AWS', 'description', 'Conocimiento cloud', 'type', 'CERTIFICATION', 'relevance', 'HIGH', 'order', 1),
                jsonb_build_object('name', 'Ingles', 'description', 'Idioma adicional', 'type', 'ADDITIONAL_LANGUAGE', 'relevance', 'MEDIUM', 'order', 2)
            )
        ),
        true
    )
END AS vacancy;
