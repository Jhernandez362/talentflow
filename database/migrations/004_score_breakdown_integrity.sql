BEGIN;

CREATE OR REPLACE FUNCTION talentflow.assert_score_breakdown_total()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_evaluation_id uuid;
    stored_total numeric(5,2);
    breakdown_total numeric(7,2);
    expected_count integer;
    actual_count integer;
BEGIN
    IF TG_TABLE_NAME = 'score_evaluations' THEN
        target_evaluation_id := COALESCE(NEW.id, OLD.id);
    ELSE
        target_evaluation_id := COALESCE(NEW.score_evaluation_id, OLD.score_evaluation_id);
    END IF;

    SELECT evaluation.total_score,
           (SELECT count(*) FROM talentflow.scoring_criteria criterion
            WHERE criterion.scoring_config_version_id = evaluation.scoring_config_version_id)
    INTO stored_total, expected_count
    FROM talentflow.score_evaluations evaluation
    WHERE evaluation.id = target_evaluation_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(sum(points_awarded), 0), count(*)
    INTO breakdown_total, actual_count
    FROM talentflow.score_criterion_results
    WHERE score_evaluation_id = target_evaluation_id;

    IF actual_count <> expected_count OR breakdown_total <> stored_total THEN
        RAISE EXCEPTION
            'Score evaluation % requires % criterion results totaling %; found % results totaling %',
            target_evaluation_id, expected_count, stored_total, actual_count, breakdown_total;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER score_evaluation_breakdown_total
AFTER INSERT OR UPDATE ON talentflow.score_evaluations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION talentflow.assert_score_breakdown_total();

CREATE CONSTRAINT TRIGGER score_result_breakdown_total
AFTER INSERT OR UPDATE OR DELETE ON talentflow.score_criterion_results
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION talentflow.assert_score_breakdown_total();

INSERT INTO talentflow.schema_migrations (version, description)
VALUES ('004', 'Require complete score breakdown matching total score');

COMMIT;

