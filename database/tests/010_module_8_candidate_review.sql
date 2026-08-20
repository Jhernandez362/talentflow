BEGIN;
DO $$
DECLARE app_id uuid; actor uuid; result jsonb;
BEGIN
 SELECT id INTO app_id FROM talentflow.applications ORDER BY applied_at DESC LIMIT 1;
 SELECT id INTO actor FROM talentflow.hr_users WHERE is_active ORDER BY created_at LIMIT 1;
 IF app_id IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Module 8 test requires an application and active HR user'; END IF;

 result:=talentflow.admin_list_candidates(jsonb_build_object('search','TF-'));
 IF jsonb_array_length(result)<1 THEN RAISE EXCEPTION 'Candidate filters returned no records'; END IF;
 IF talentflow.admin_get_candidate(app_id) IS NULL THEN RAISE EXCEPTION 'Candidate detail unavailable'; END IF;

 PERFORM talentflow.admin_change_candidate_status(app_id,jsonb_build_object('actorId',actor,'status','EN_REVISION','observation','Prueba M8'));
 IF NOT EXISTS(SELECT 1 FROM talentflow.application_status_history WHERE application_id=app_id AND new_status='EN_REVISION') THEN RAISE EXCEPTION 'Status audit missing'; END IF;
 PERFORM talentflow.admin_record_hr_review(app_id,jsonb_build_object('actorId',actor,'decision','HOLD','notes','Revisión humana de prueba'));
 IF NOT EXISTS(SELECT 1 FROM talentflow.hr_reviews WHERE application_id=app_id AND decision='HOLD') THEN RAISE EXCEPTION 'HR review missing'; END IF;

 UPDATE talentflow.applications SET status='REVISION_DOCUMENTO',revision_manual_autorizada=true WHERE id=app_id;
 IF jsonb_array_length(talentflow.admin_list_document_reviews())<1 THEN RAISE EXCEPTION 'Authorized document review not listed'; END IF;
 result:=talentflow.admin_save_manual_analysis(app_id,jsonb_build_object('actorId',actor,'experienceYears',2,
   'experiences',jsonb_build_array(jsonb_build_object('id','manual_exp_1','empresa','Prueba','cargo','Developer','funciones',jsonb_build_array('Desarrollo Unity'),'tecnologias',jsonb_build_array('Unity'))),
   'skills',jsonb_build_array(jsonb_build_object('nombre','Unity','evidencia_laboral',true,'experiencia_ids',jsonb_build_array('manual_exp_1'))),
   'education','[]'::jsonb,'courses','[]'::jsonb,'certifications','[]'::jsonb));
 IF result->>'analysis_source'<>'MANUAL' THEN RAISE EXCEPTION 'Manual analysis source missing'; END IF;
END $$;
ROLLBACK;
