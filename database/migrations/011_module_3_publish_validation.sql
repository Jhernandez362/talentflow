BEGIN;

CREATE OR REPLACE FUNCTION talentflow.validate_admin_vacancy_payload(payload jsonb, publish_now boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    total integer;
    duplicate_count integer;
BEGIN
    IF btrim(COALESCE(payload->>'title', '')) = ''
       OR btrim(COALESCE(payload->>'code', '')) = '' THEN
        RAISE EXCEPTION 'Title and code are required';
    END IF;

    IF NULLIF(payload->>'salaryMin','')::numeric IS NOT NULL
       AND NULLIF(payload->>'salaryMax','')::numeric IS NOT NULL
       AND NULLIF(payload->>'salaryMin','')::numeric > NULLIF(payload->>'salaryMax','')::numeric THEN
        RAISE EXCEPTION 'Minimum salary cannot exceed maximum salary';
    END IF;

    IF NULLIF(payload->>'closesAt', '')::timestamptz IS NOT NULL
       AND NULLIF(payload->>'plannedPublishAt', '')::timestamptz IS NOT NULL
       AND (payload->>'closesAt')::timestamptz <= (payload->>'plannedPublishAt')::timestamptz THEN
        RAISE EXCEPTION 'Closing date must be after publication date';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(payload->'criteria', '[]'::jsonb)) criterion
        WHERE btrim(COALESCE(criterion->>'name', '')) = ''
    ) THEN
        RAISE EXCEPTION 'Criterion names cannot be blank';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(payload->'criteria', '[]'::jsonb)) criterion
        WHERE (criterion->>'weight')::numeric < 0
           OR (criterion->>'weight')::numeric > 100
    ) THEN
        RAISE EXCEPTION 'Criterion weights must be between 0 and 100';
    END IF;

    SELECT count(*) - count(DISTINCT lower(btrim(value->>'name')))
    INTO duplicate_count
    FROM jsonb_array_elements(COALESCE(payload->'criteria', '[]'::jsonb));

    IF duplicate_count > 0 THEN
        RAISE EXCEPTION 'Duplicate criteria are not allowed';
    END IF;

    SELECT COALESCE(sum((value->>'weight')::integer), 0)
    INTO total
    FROM jsonb_array_elements(COALESCE(payload->'criteria', '[]'::jsonb));

    IF publish_now AND (
        btrim(COALESCE(payload->>'department', '')) = ''
        OR btrim(COALESCE(payload->>'workMode', '')) = ''
        OR btrim(COALESCE(payload->>'seniorityLevel', '')) = ''
        OR NULLIF(payload->>'closesAt', '') IS NULL
        OR COALESCE(NULLIF(payload->>'openings', '')::integer, 0) <= 0
    ) THEN
        RAISE EXCEPTION 'Publishing requires department, work mode, seniority, closing date and positive openings';
    END IF;

    IF publish_now AND (
        jsonb_array_length(COALESCE(payload->'criteria', '[]'::jsonb)) = 0
        OR total <> 100
    ) THEN
        RAISE EXCEPTION 'Publishing requires at least one criterion totaling exactly 100; current total is %', total;
    END IF;
END;
$$;

INSERT INTO talentflow.schema_migrations(version, description)
VALUES ('011', 'Complete Module 3 publication validation');

COMMIT;
