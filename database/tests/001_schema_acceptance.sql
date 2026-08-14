\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    criteria_total integer;
    vacancy_status varchar(30);
BEGIN
    SELECT sum(weight)::integer INTO criteria_total
    FROM talentflow.scoring_criteria
    WHERE scoring_config_version_id = '30000000-0000-4000-8000-000000000001';

    IF criteria_total <> 100 THEN
        RAISE EXCEPTION 'Expected development criteria total 100, got %', criteria_total;
    END IF;

    SELECT status INTO vacancy_status
    FROM talentflow.vacancies
    WHERE id = '20000000-0000-4000-8000-000000000001';

    IF vacancy_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Expected seeded vacancy status DRAFT, got %', vacancy_status;
    END IF;
END;
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO talentflow.scoring_criteria (
            scoring_config_version_id, code, name, criterion_type, weight
        ) VALUES (
            '30000000-0000-4000-8000-000000000001', 'INVALID_NEGATIVE', 'Invalid', 'OTHER', -1
        );
        RAISE EXCEPTION 'Negative weight was unexpectedly accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END;
$$;

DO $$
DECLARE
    test_candidate uuid := gen_random_uuid();
BEGIN
    INSERT INTO talentflow.candidates (id, email, full_name)
    VALUES (test_candidate, 'duplicate.test@example.invalid', 'Candidato Ficticio');

    INSERT INTO talentflow.applications (vacancy_id, candidate_id)
    VALUES ('20000000-0000-4000-8000-000000000001', test_candidate);

    BEGIN
        INSERT INTO talentflow.applications (vacancy_id, candidate_id)
        VALUES ('20000000-0000-4000-8000-000000000001', test_candidate);
        RAISE EXCEPTION 'Duplicate application was unexpectedly accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    DELETE FROM talentflow.applications WHERE candidate_id = test_candidate;
    DELETE FROM talentflow.candidates WHERE id = test_candidate;
END;
$$;

ROLLBACK;

BEGIN;

UPDATE talentflow.scoring_config_versions
SET status = 'PUBLISHED',
    published_by = '10000000-0000-4000-8000-000000000001'
WHERE id = '30000000-0000-4000-8000-000000000001';

SET CONSTRAINTS ALL IMMEDIATE;

DO $$
BEGIN
    BEGIN
        UPDATE talentflow.scoring_criteria
        SET weight = 19
        WHERE id = '40000000-0000-4000-8000-000000000001';
        RAISE EXCEPTION 'Published criteria were unexpectedly mutable';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM LIKE 'Published criteria were unexpectedly mutable%%' THEN
                RAISE;
            END IF;
    END;
END;
$$;

SET CONSTRAINTS ALL DEFERRED;

INSERT INTO talentflow.candidates (id, email, full_name)
VALUES ('50000000-0000-4000-8000-000000000001', 'score.test@example.invalid', 'Candidato Score Ficticio');

INSERT INTO talentflow.applications (id, vacancy_id, candidate_id)
VALUES (
    '60000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001'
);

INSERT INTO talentflow.score_evaluations (
    id, application_id, vacancy_id, scoring_config_version_id, total_score, algorithm_version
) VALUES (
    '70000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    100,
    'test-v1'
);

INSERT INTO talentflow.score_criterion_results (
    score_evaluation_id, scoring_criterion_id, matched, points_awarded
)
SELECT
    '70000000-0000-4000-8000-000000000001', id, true, weight
FROM talentflow.scoring_criteria
WHERE scoring_config_version_id = '30000000-0000-4000-8000-000000000001';

SET CONSTRAINTS ALL IMMEDIATE;

ROLLBACK;

BEGIN;
UPDATE talentflow.scoring_criteria
SET weight = 19
WHERE id = '40000000-0000-4000-8000-000000000001';

DO $$
BEGIN
    BEGIN
        UPDATE talentflow.scoring_config_versions
        SET status = 'PUBLISHED',
            published_by = '10000000-0000-4000-8000-000000000001'
        WHERE id = '30000000-0000-4000-8000-000000000001';
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'A scoring configuration totaling 99 was unexpectedly published';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM LIKE 'A scoring configuration totaling 99%%' THEN
                RAISE;
            END IF;
    END;
END;
$$;
ROLLBACK;

SELECT 'TalentFlow schema acceptance tests passed' AS result;
