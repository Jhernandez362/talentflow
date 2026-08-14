BEGIN;

CREATE OR REPLACE FUNCTION talentflow.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.prepare_scoring_config_publication()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status = 'PUBLISHED' THEN
        IF NEW.status NOT IN ('PUBLISHED', 'ARCHIVED')
           OR NEW.vacancy_id IS DISTINCT FROM OLD.vacancy_id
           OR NEW.version IS DISTINCT FROM OLD.version
           OR NEW.notes IS DISTINCT FROM OLD.notes
           OR NEW.created_by IS DISTINCT FROM OLD.created_by
           OR NEW.published_by IS DISTINCT FROM OLD.published_by
           OR NEW.published_at IS DISTINCT FROM OLD.published_at THEN
            RAISE EXCEPTION 'Published scoring configuration % is immutable', OLD.id;
        END IF;
    END IF;

    IF OLD.status = 'DRAFT' AND NEW.status = 'PUBLISHED' THEN
        NEW.published_at := COALESCE(NEW.published_at, now());
        IF NEW.published_by IS NULL THEN
            RAISE EXCEPTION 'published_by is required when publishing scoring configuration %', NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.prevent_published_config_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status IN ('PUBLISHED', 'ARCHIVED') THEN
        RAISE EXCEPTION 'Published or archived scoring configuration % cannot be deleted', OLD.id;
    END IF;
    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.prevent_published_config_item_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_config_id uuid := COALESCE(NEW.scoring_config_version_id, OLD.scoring_config_version_id);
    target_status varchar(20);
BEGIN
    SELECT status INTO target_status
    FROM talentflow.scoring_config_versions
    WHERE id = target_config_id;

    IF target_status IN ('PUBLISHED', 'ARCHIVED') THEN
        RAISE EXCEPTION 'Items of published or archived scoring configuration % are immutable', target_config_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.assert_published_scoring_total()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_config_id uuid;
    target_status varchar(20);
    total_weight integer;
BEGIN
    target_config_id := CASE
        WHEN TG_TABLE_NAME = 'scoring_config_versions' THEN COALESCE(NEW.id, OLD.id)
        ELSE COALESCE(NEW.scoring_config_version_id, OLD.scoring_config_version_id)
    END;

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

CREATE OR REPLACE FUNCTION talentflow.validate_score_evaluation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    config_status varchar(20);
BEGIN
    SELECT status INTO config_status
    FROM talentflow.scoring_config_versions
    WHERE id = NEW.scoring_config_version_id;

    IF config_status <> 'PUBLISHED' THEN
        RAISE EXCEPTION 'Scores require a published scoring configuration; configuration % is %', NEW.scoring_config_version_id, config_status;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.validate_score_criterion_result()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    evaluation_config_id uuid;
    criterion_config_id uuid;
    criterion_weight smallint;
BEGIN
    SELECT scoring_config_version_id INTO evaluation_config_id
    FROM talentflow.score_evaluations
    WHERE id = NEW.score_evaluation_id;

    SELECT scoring_config_version_id, weight
    INTO criterion_config_id, criterion_weight
    FROM talentflow.scoring_criteria
    WHERE id = NEW.scoring_criterion_id;

    IF evaluation_config_id IS DISTINCT FROM criterion_config_id THEN
        RAISE EXCEPTION 'Criterion % does not belong to evaluation configuration', NEW.scoring_criterion_id;
    END IF;
    IF NEW.points_awarded > criterion_weight THEN
        RAISE EXCEPTION 'Awarded points % exceed criterion weight %', NEW.points_awarded, criterion_weight;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION talentflow.capture_audit_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, talentflow
AS $$
DECLARE
    row_before jsonb;
    row_after jsonb;
    audit_record_id uuid;
    actor_setting text;
BEGIN
    row_before := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END;
    row_after := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END;
    audit_record_id := COALESCE((row_after ->> 'id')::uuid, (row_before ->> 'id')::uuid);
    actor_setting := nullif(current_setting('app.current_hr_user_id', true), '');

    INSERT INTO talentflow.audit_events (
        actor_hr_user_id, action, schema_name, table_name, record_id,
        old_data, new_data, source, request_id
    ) VALUES (
        actor_setting::uuid, TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME, audit_record_id,
        row_before, row_after,
        nullif(current_setting('app.source', true), ''),
        nullif(current_setting('app.request_id', true), '')
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER scoring_config_prepare_publication
BEFORE UPDATE ON talentflow.scoring_config_versions
FOR EACH ROW EXECUTE FUNCTION talentflow.prepare_scoring_config_publication();

CREATE TRIGGER scoring_config_prevent_delete
BEFORE DELETE ON talentflow.scoring_config_versions
FOR EACH ROW EXECUTE FUNCTION talentflow.prevent_published_config_delete();

CREATE CONSTRAINT TRIGGER scoring_config_total_on_publish
AFTER INSERT OR UPDATE ON talentflow.scoring_config_versions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION talentflow.assert_published_scoring_total();

CREATE CONSTRAINT TRIGGER scoring_criteria_total_after_change
AFTER INSERT OR UPDATE OR DELETE ON talentflow.scoring_criteria
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION talentflow.assert_published_scoring_total();

CREATE TRIGGER scoring_criteria_prevent_published_change
BEFORE INSERT OR UPDATE OR DELETE ON talentflow.scoring_criteria
FOR EACH ROW EXECUTE FUNCTION talentflow.prevent_published_config_item_change();

CREATE TRIGGER desirable_prevent_published_change
BEFORE INSERT OR UPDATE OR DELETE ON talentflow.desirable_requirements
FOR EACH ROW EXECUTE FUNCTION talentflow.prevent_published_config_item_change();

CREATE TRIGGER added_value_prevent_published_change
BEFORE INSERT OR UPDATE OR DELETE ON talentflow.added_value_requirements
FOR EACH ROW EXECUTE FUNCTION talentflow.prevent_published_config_item_change();

CREATE TRIGGER score_evaluation_validate
BEFORE INSERT OR UPDATE ON talentflow.score_evaluations
FOR EACH ROW EXECUTE FUNCTION talentflow.validate_score_evaluation();

CREATE TRIGGER score_criterion_result_validate
BEFORE INSERT OR UPDATE ON talentflow.score_criterion_results
FOR EACH ROW EXECUTE FUNCTION talentflow.validate_score_criterion_result();

DO $$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'hr_users', 'vacancies', 'scoring_config_versions', 'scoring_criteria',
        'desirable_requirements', 'added_value_requirements', 'candidates',
        'applications', 'cv_references', 'document_processing_attempts',
        'ai_analyses', 'hr_reviews'
    ]
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I_set_updated_at BEFORE UPDATE ON talentflow.%I FOR EACH ROW EXECUTE FUNCTION talentflow.set_updated_at()',
            table_name, table_name
        );
    END LOOP;

    FOREACH table_name IN ARRAY ARRAY[
        'hr_users', 'vacancies', 'scoring_config_versions', 'scoring_criteria',
        'desirable_requirements', 'added_value_requirements', 'candidates',
        'applications', 'cv_references', 'document_processing_attempts',
        'ai_analyses', 'score_evaluations', 'score_criterion_results',
        'suggested_questions', 'hr_reviews'
    ]
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I_audit AFTER INSERT OR UPDATE OR DELETE ON talentflow.%I FOR EACH ROW EXECUTE FUNCTION talentflow.capture_audit_event()',
            table_name, table_name
        );
    END LOOP;
END;
$$;

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('002', 'Scoring integrity, timestamps and audit triggers');

COMMIT;

