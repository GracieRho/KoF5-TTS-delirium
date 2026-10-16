-- Roles come from verified records, never user-editable metadata.
CREATE FUNCTION kof5.portal_access() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT jsonb_build_object('user_id', auth.uid(), 'guardian',
   EXISTS (SELECT 1 FROM kof5.patient_guardian_link WHERE guardian_user_id=auth.uid()
     AND access_status='verified' AND effective_at<=now() AND (expires_at IS NULL OR expires_at>now())),
   'hospital', EXISTS (SELECT 1 FROM kof5.hospital_staff_membership WHERE auth_user_id=auth.uid()
     AND status='verified' AND effective_at<=now() AND (expires_at IS NULL OR expires_at>now())))
 WHERE EXISTS (SELECT 1 FROM auth.sessions WHERE user_id=auth.uid()
   AND id::text=auth.jwt()->>'session_id' AND (not_after IS NULL OR not_after>now()));
$$;
REVOKE ALL ON FUNCTION kof5.portal_access() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION kof5.portal_access() TO authenticated;
CREATE FUNCTION api.portal_access() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = '' AS $$ SELECT kof5.portal_access(); $$;
REVOKE ALL ON FUNCTION api.portal_access() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION api.portal_access() TO authenticated;
