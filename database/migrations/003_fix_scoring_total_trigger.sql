BEGIN;

CREATE OR REPLACE FUNCTION talentflow.assert_published_scoring_total()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_config_id uuid;
    target_status varchar(20);
    total_weight integer;
BEGIN
    IF TG_TABLE_NAME = 'scoring_config_versions' THEN
        target_config_id := COALESCE(NEW.id, OLD.id);
    ELSE
        target_config_id := COALESCE(NEW.scoring_config_version_id, OLD.scoring_config_version_id);
    END IF;

    SELECT status INTO target_status
    FROM talentflow.scoring_config_versions
    WHERE id = target_config_id;

    IF target_status = 'PUBLISHED' THEN
        SELECT COALESCE(sum(weight), 0)::integer INTO total_weight
        FROM talentflow.scoring_criteria
        WHERE scoring_config_version_id = target_config_id;

        IF total_weight <> 100 THEN
            RAISE EXCEPTION 'Published scoring configuration % must total exactly 100; current total is %', target_config_id, total_weight;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('003', 'Fix scoring total trigger for multiple row types');

COMMIT;
