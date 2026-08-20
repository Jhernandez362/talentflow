BEGIN;

ALTER TABLE talentflow.applications DROP CONSTRAINT IF EXISTS applications_status_valid;
ALTER TABLE talentflow.applications ADD CONSTRAINT applications_status_valid CHECK (status IN (
  'RECEIVED','PROCESSING','READY_FOR_REVIEW','IN_REVIEW','ON_HOLD','ADVANCED','REJECTED','WITHDRAWN',
  'RECIBIDO','VALIDANDO_DOCUMENTO','REVISION_DOCUMENTO','PROCESANDO','ANALIZADO','ERROR',
  'PENDIENTE_REVISION','EN_REVISION','ENTREVISTA','FINALIZADO'
));

ALTER TABLE talentflow.ai_analyses
  ADD COLUMN IF NOT EXISTS analysis_source varchar(20) NOT NULL DEFAULT 'IA';
ALTER TABLE talentflow.ai_analyses DROP CONSTRAINT IF EXISTS ai_analysis_source_valid;
ALTER TABLE talentflow.ai_analyses ADD CONSTRAINT ai_analysis_source_valid
  CHECK (analysis_source IN ('IA','MANUAL'));

CREATE TABLE IF NOT EXISTS talentflow.application_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES talentflow.applications(id) ON DELETE CASCADE,
  actor_hr_user_id uuid NOT NULL REFERENCES talentflow.hr_users(id) ON DELETE RESTRICT,
  previous_status varchar(30) NOT NULL,
  new_status varchar(30) NOT NULL,
  observation text,
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS application_status_history_idx
  ON talentflow.application_status_history(application_id, changed_at DESC);

CREATE OR REPLACE FUNCTION talentflow.require_active_hr(actor_id uuid)
RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM talentflow.hr_users WHERE id=actor_id AND is_active
      AND role IN ('ADMIN','RECRUITER','REVIEWER')
  ) THEN RAISE EXCEPTION 'HR_USER_NOT_AUTHORIZED'; END IF;
END; $$;

CREATE OR REPLACE FUNCTION talentflow.admin_list_candidates(filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH rows AS (
  SELECT a.id,a.ticket_id ticket,c.full_name,c.email,v.id vacancy_id,v.title vacancy_title,
    COALESCE(score.total_score,0) score,
    COALESCE(score.compatibility_priority,'BAJA') priority,a.status,a.applied_at,
    COALESCE(score.result_breakdown->>'seniority_fit','SIN_DATOS') seniority_fit,
    COALESCE(score.result_breakdown->'mandatory_missing','[]'::jsonb) mandatory_missing
  FROM talentflow.applications a
  JOIN talentflow.candidates c ON c.id=a.candidate_id
  JOIN talentflow.vacancies v ON v.id=a.vacancy_id
  LEFT JOIN LATERAL (SELECT s.* FROM talentflow.score_evaluations s
    WHERE s.application_id=a.id ORDER BY s.calculated_at DESC LIMIT 1) score ON true
), filtered AS (
  SELECT * FROM rows r WHERE
    (COALESCE(filters->>'vacancyId','')='' OR r.vacancy_id=(filters->>'vacancyId')::uuid)
    AND (COALESCE(filters->>'status','')='' OR r.status=filters->>'status')
    AND (COALESCE(filters->>'priority','')='' OR r.priority=filters->>'priority')
    AND (COALESCE(filters->>'minScore','')='' OR r.score>=(filters->>'minScore')::numeric)
    AND (COALESCE(filters->>'maxScore','')='' OR r.score<=(filters->>'maxScore')::numeric)
    AND (COALESCE(filters->>'fromDate','')='' OR r.applied_at::date>=(filters->>'fromDate')::date)
    AND (COALESCE(filters->>'toDate','')='' OR r.applied_at::date<=(filters->>'toDate')::date)
    AND (COALESCE(filters->>'search','')='' OR concat_ws(' ',r.full_name,r.email,r.ticket) ILIKE '%'||(filters->>'search')||'%')
)
SELECT COALESCE(jsonb_agg(to_jsonb(f) ORDER BY
  CASE WHEN filters->>'orderBy'='score' AND COALESCE(filters->>'orderDir','desc')='asc' THEN f.score END ASC,
  CASE WHEN filters->>'orderBy'='score' AND COALESCE(filters->>'orderDir','desc')<>'asc' THEN f.score END DESC,
  CASE WHEN filters->>'orderBy'='name' THEN f.full_name END ASC,
  CASE WHEN filters->>'orderBy'='status' THEN f.status END ASC,
  CASE WHEN filters->>'orderBy'='date' AND COALESCE(filters->>'orderDir','desc')='asc' THEN f.applied_at END ASC,
  f.applied_at DESC), '[]'::jsonb) FROM filtered f;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_get_candidate(target_id uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
 'id',a.id,'ticket',a.ticket_id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
 'location',c.location,'vacancy_title',v.title,'applied_at',a.applied_at,'status',a.status,
 'score',COALESCE(score.total_score,0),'priority',COALESCE(score.compatibility_priority,'BAJA'),
 'scoring_version',config.version,'seniority_fit',score.result_breakdown->>'seniority_fit',
 'mandatory_missing',COALESCE(score.result_breakdown->'mandatory_missing','[]'::jsonb),
 'experience_years',COALESCE((extraction.structured_output->>'experiencia_total_anios')::numeric,c.declared_experience_years,0),
 'analysis_source',COALESCE(extraction.analysis_source,'IA'),
 'cv',jsonb_build_object('url',cv.drive_web_view_link,'filename',cv.original_filename),
 'habilidades',COALESCE(extraction.structured_output->'habilidades','[]'::jsonb),
 'experiencias',COALESCE(extraction.structured_output->'experiencias','[]'::jsonb),
 'educacion',COALESCE(extraction.structured_output->'educacion','[]'::jsonb),
 'cursos',COALESCE(extraction.structured_output->'cursos','[]'::jsonb),
 'certificaciones',COALESCE(extraction.structured_output->'certificaciones','[]'::jsonb),
 'score_breakdown',COALESCE(score.result_breakdown->'criteria','[]'::jsonb),
 'desirables',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',d.name,'found',score.result_breakdown->'desired_found' ? d.name) ORDER BY d.display_order)
   FROM talentflow.desirable_requirements d WHERE d.scoring_config_version_id=score.scoring_config_version_id),'[]'::jsonb),
 'added_values',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',x.name,'found',score.result_breakdown->'added_value' ? x.name) ORDER BY x.display_order)
   FROM talentflow.added_value_requirements x WHERE x.scoring_config_version_id=score.scoring_config_version_id),'[]'::jsonb),
 'interview_questions',COALESCE(questions.structured_output->'questions','[]'::jsonb),
 'resumen',summary.structured_output->>'summary',
 'reviews',COALESCE((SELECT jsonb_agg(jsonb_build_object('decision',r.decision,'notes',r.notes,'reviewed_at',r.reviewed_at,'reviewer',u.display_name) ORDER BY r.reviewed_at DESC)
   FROM talentflow.hr_reviews r JOIN talentflow.hr_users u ON u.id=r.reviewer_id WHERE r.application_id=a.id),'[]'::jsonb),
 'status_history',COALESCE((SELECT jsonb_agg(jsonb_build_object('previous',h.previous_status,'new',h.new_status,'observation',h.observation,'changed_at',h.changed_at,'actor',u.display_name) ORDER BY h.changed_at DESC)
   FROM talentflow.application_status_history h JOIN talentflow.hr_users u ON u.id=h.actor_hr_user_id WHERE h.application_id=a.id),'[]'::jsonb)
)
FROM talentflow.applications a JOIN talentflow.candidates c ON c.id=a.candidate_id
JOIN talentflow.vacancies v ON v.id=a.vacancy_id
LEFT JOIN LATERAL (SELECT x.* FROM talentflow.ai_analyses x WHERE x.application_id=a.id AND x.analysis_type='CV_EXTRACTION' AND x.status='SUCCEEDED' ORDER BY x.completed_at DESC LIMIT 1) extraction ON true
LEFT JOIN LATERAL (SELECT s.* FROM talentflow.score_evaluations s WHERE s.application_id=a.id ORDER BY s.calculated_at DESC LIMIT 1) score ON true
LEFT JOIN talentflow.scoring_config_versions config ON config.id=score.scoring_config_version_id
LEFT JOIN LATERAL (SELECT x.structured_output FROM talentflow.ai_analyses x WHERE x.application_id=a.id AND x.analysis_type='PROFESSIONAL_SUMMARY' AND x.status='SUCCEEDED' ORDER BY x.completed_at DESC LIMIT 1) summary ON true
LEFT JOIN LATERAL (SELECT x.structured_output FROM talentflow.ai_analyses x WHERE x.application_id=a.id AND x.analysis_type='INTERVIEW_QUESTIONS' AND x.status='SUCCEEDED' ORDER BY x.completed_at DESC LIMIT 1) questions ON true
LEFT JOIN LATERAL (SELECT x.* FROM talentflow.cv_references x WHERE x.application_id=a.id AND x.is_current LIMIT 1) cv ON true
WHERE a.id=target_id;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_change_candidate_status(target_id uuid,payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE actor uuid=(payload->>'actorId')::uuid; old_status text; new_status text=payload->>'status';
BEGIN
 PERFORM talentflow.require_active_hr(actor);
 IF new_status NOT IN ('PENDIENTE_REVISION','EN_REVISION','ENTREVISTA','FINALIZADO','ON_HOLD','WITHDRAWN') THEN RAISE EXCEPTION 'INVALID_APPLICATION_STATUS'; END IF;
 SELECT status INTO old_status FROM talentflow.applications WHERE id=target_id FOR UPDATE;
 IF old_status IS NULL THEN RAISE EXCEPTION 'APPLICATION_NOT_FOUND'; END IF;
 IF old_status='FINALIZADO' AND new_status<>'FINALIZADO' THEN RAISE EXCEPTION 'FINAL_STATUS_CANNOT_TRANSITION'; END IF;
 UPDATE talentflow.applications SET status=new_status,updated_at=now() WHERE id=target_id;
 INSERT INTO talentflow.application_status_history(application_id,actor_hr_user_id,previous_status,new_status,observation)
 VALUES(target_id,actor,old_status,new_status,NULLIF(btrim(payload->>'observation'),''));
 RETURN jsonb_build_object('id',target_id,'previousStatus',old_status,'status',new_status,'changedAt',now());
END; $$;

CREATE OR REPLACE FUNCTION talentflow.admin_record_hr_review(target_id uuid,payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE actor uuid=(payload->>'actorId')::uuid; review_id uuid; decision text=payload->>'decision';
BEGIN
 PERFORM talentflow.require_active_hr(actor);
 IF decision NOT IN ('PENDING','ADVANCE','HOLD','REJECT','REQUEST_INFORMATION') THEN RAISE EXCEPTION 'INVALID_HR_REVIEW_RESULT'; END IF;
 IF btrim(COALESCE(payload->>'notes',''))='' THEN RAISE EXCEPTION 'REVIEW_NOTES_REQUIRED'; END IF;
 INSERT INTO talentflow.hr_reviews(application_id,reviewer_id,decision,notes)
 VALUES(target_id,actor,decision,btrim(payload->>'notes')) RETURNING id INTO review_id;
 RETURN jsonb_build_object('id',review_id,'applicationId',target_id,'decision',decision,'reviewedAt',now());
END; $$;

CREATE OR REPLACE FUNCTION talentflow.admin_list_document_reviews()
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'ticket',a.ticket_id,'candidate',c.full_name,
 'vacancy',v.title,'attempts',COALESCE(attempt.count,0),'reason',a.manual_review_reason,'requested_at',a.manual_review_requested_at,
 'authorized',a.revision_manual_autorizada,'cv_url',cv.drive_web_view_link,'cv_filename',cv.original_filename) ORDER BY a.manual_review_requested_at),'[]'::jsonb)
FROM talentflow.applications a JOIN talentflow.candidates c ON c.id=a.candidate_id JOIN talentflow.vacancies v ON v.id=a.vacancy_id
LEFT JOIN LATERAL (SELECT count(*) count FROM talentflow.document_processing_attempts x WHERE x.application_id=a.id) attempt ON true
LEFT JOIN LATERAL (SELECT x.* FROM talentflow.cv_references x WHERE x.application_id=a.id AND x.is_current LIMIT 1) cv ON true
WHERE a.status='REVISION_DOCUMENTO' AND a.revision_manual_autorizada=true;
$$;

CREATE OR REPLACE FUNCTION talentflow.admin_save_manual_analysis(target_id uuid,payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE actor uuid=(payload->>'actorId')::uuid; analysis_id uuid; target_vacancy_id uuid; config_version integer; data jsonb;
BEGIN
 PERFORM talentflow.require_active_hr(actor);
 IF NOT EXISTS(SELECT 1 FROM talentflow.applications WHERE id=target_id AND status='REVISION_DOCUMENTO' AND revision_manual_autorizada) THEN RAISE EXCEPTION 'MANUAL_REVIEW_NOT_AUTHORIZED'; END IF;
 data=jsonb_build_object('experiencia_total_anios',COALESCE((payload->>'experienceYears')::numeric,0),
  'experiencias',COALESCE(payload->'experiences','[]'::jsonb),'educacion',COALESCE(payload->'education','[]'::jsonb),
  'cursos',COALESCE(payload->'courses','[]'::jsonb),'certificaciones',COALESCE(payload->'certifications','[]'::jsonb),
  'idiomas','[]'::jsonb,'habilidades',COALESCE(payload->'skills','[]'::jsonb),
  'habilidades_declaradas_no_verificadas','[]'::jsonb,'advertencias',jsonb_build_array('Información estructurada manualmente por RRHH'));
 IF jsonb_typeof(data->'experiencias')<>'array' OR jsonb_typeof(data->'habilidades')<>'array' THEN RAISE EXCEPTION 'INVALID_MANUAL_ANALYSIS'; END IF;
 INSERT INTO talentflow.ai_analyses(application_id,analysis_type,status,provider,model,prompt_code,prompt_version,structured_output,started_at,completed_at,analysis_source)
 VALUES(target_id,'CV_EXTRACTION','SUCCEEDED','MANUAL','MANUAL','MANUAL-HR','MANUAL-v1',data,now(),now(),'MANUAL') RETURNING id INTO analysis_id;
 UPDATE talentflow.applications SET status='ANALIZADO',updated_at=now() WHERE id=target_id RETURNING vacancy_id INTO target_vacancy_id;
 SELECT version INTO config_version FROM talentflow.scoring_config_versions WHERE vacancy_id=target_vacancy_id AND status='PUBLISHED';
 RETURN jsonb_build_object('postulacion_id',target_id,'analysis_id',analysis_id,'vacancy_id',target_vacancy_id,'scoring_version',config_version,'analysis_source','MANUAL');
END; $$;

INSERT INTO talentflow.schema_migrations(version,description)
VALUES('025','Module 8 candidate panel and human review') ON CONFLICT(version) DO NOTHING;
COMMIT;
