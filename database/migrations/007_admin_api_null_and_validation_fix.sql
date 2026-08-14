BEGIN;

CREATE OR REPLACE FUNCTION talentflow.validate_admin_vacancy_payload(payload jsonb, publish_now boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    total integer;
    duplicate_count integer;
BEGIN
    IF btrim(COALESCE(payload->>'title', '')) = '' OR btrim(COALESCE(payload->>'code', '')) = '' THEN
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
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(payload->'criteria','[]')) c WHERE (c->>'weight')::numeric < 0) THEN
        RAISE EXCEPTION 'Criterion weights cannot be negative';
    END IF;
    SELECT count(*)-count(DISTINCT lower(btrim(value->>'name'))) INTO duplicate_count
    FROM jsonb_array_elements(COALESCE(payload->'criteria','[]'));
    IF duplicate_count > 0 THEN RAISE EXCEPTION 'Duplicate criteria are not allowed'; END IF;
    SELECT COALESCE(sum((value->>'weight')::integer),0) INTO total FROM jsonb_array_elements(COALESCE(payload->'criteria','[]'));
    IF publish_now AND (jsonb_array_length(COALESCE(payload->'criteria','[]'))=0 OR total<>100) THEN
        RAISE EXCEPTION 'Publishing requires at least one criterion totaling exactly 100; current total is %', total;
    END IF;
END;
$$;

ALTER FUNCTION talentflow.admin_save_vacancy(jsonb, boolean)
    RENAME TO admin_save_vacancy_impl;

CREATE OR REPLACE FUNCTION talentflow.admin_save_vacancy(payload jsonb, publish_now boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    normalized jsonb;
BEGIN
    PERFORM talentflow.validate_admin_vacancy_payload(payload, publish_now);
    normalized := payload || jsonb_build_object(
        'salaryMin', COALESCE(payload->>'salaryMin', '0'),
        'salaryMax', COALESCE(payload->>'salaryMax', '0')
    );
    IF NULLIF(payload->>'salaryMin','') IS NULL THEN normalized := jsonb_set(normalized, '{salaryMin}', 'null'::jsonb); END IF;
    IF NULLIF(payload->>'salaryMax','') IS NULL THEN normalized := jsonb_set(normalized, '{salaryMax}', 'null'::jsonb); END IF;
    RETURN talentflow.admin_save_vacancy_impl(normalized, publish_now);
END;
$$;

INSERT INTO talentflow.schema_migrations(version,description)
VALUES('007','Shared administrative payload validation');
COMMIT;
