BEGIN;

INSERT INTO talentflow.hr_users (id, email, display_name, role)
VALUES (
    '10000000-0000-4000-8000-000000000001',
    'rrhh.dev@example.invalid',
    'Usuario RRHH Desarrollo',
    'ADMIN'
)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    display_name = EXCLUDED.display_name,
    role = EXCLUDED.role;

INSERT INTO talentflow.vacancies (
    id, code, title, description, status, priority, created_by, updated_by
)
VALUES (
    '20000000-0000-4000-8000-000000000001',
    'BE-JR-DEV',
    'Backend Developer Junior',
    'Vacante ficticia para validar el modelo de datos en desarrollo.',
    'DRAFT',
    'NORMAL',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    status = EXCLUDED.status,
    priority = EXCLUDED.priority,
    updated_by = EXCLUDED.updated_by;

INSERT INTO talentflow.scoring_config_versions (
    id, vacancy_id, version, status, notes, created_by
)
VALUES (
    '30000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    1,
    'DRAFT',
    'Configuracion ficticia inicial; los criterios suman 100 puntos.',
    '10000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO UPDATE SET
    notes = EXCLUDED.notes;

INSERT INTO talentflow.scoring_criteria (
    id, scoring_config_version_id, code, name, criterion_type, weight, evaluation_order, evaluation_rule
)
VALUES
    ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'JAVA', 'Java', 'TECNOLOGIA', 20, 1, '{"minimum_level":"junior"}'),
    ('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'SPRING_BOOT', 'Spring Boot', 'TECNOLOGIA', 20, 2, '{}'),
    ('40000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', 'SQL', 'SQL', 'CONOCIMIENTO', 15, 3, '{}'),
    ('40000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000001', 'REST_API', 'REST API', 'CONOCIMIENTO', 15, 4, '{}'),
    ('40000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000001', 'GIT', 'Git', 'TECNOLOGIA', 10, 5, '{}'),
    ('40000000-0000-4000-8000-000000000006', '30000000-0000-4000-8000-000000000001', 'EXPERIENCE', 'Experiencia relevante', 'EXPERIENCIA', 20, 6, '{"minimum_months":6}')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    criterion_type = EXCLUDED.criterion_type,
    weight = EXCLUDED.weight,
    evaluation_order = EXCLUDED.evaluation_order,
    evaluation_rule = EXCLUDED.evaluation_rule;

COMMIT;
