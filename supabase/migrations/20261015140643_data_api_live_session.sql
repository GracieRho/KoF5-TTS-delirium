-- Logout must also revoke direct Data API reads/writes before JWT expiry.
CREATE SCHEMA IF NOT EXISTS portal_private;
GRANT USAGE ON SCHEMA portal_private TO anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION portal_private.require_live_session() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.jwt()->>'role' = 'authenticated' AND NOT EXISTS (
    SELECT 1 FROM auth.sessions WHERE user_id=auth.uid()
      AND id::text=auth.jwt()->>'session_id' AND (not_after IS NULL OR not_after>now())
  ) THEN
    RAISE SQLSTATE 'PT401' USING MESSAGE = '로그인이 만료되었습니다. 다시 로그인해주세요.';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION portal_private.require_live_session() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION portal_private.require_live_session() TO anon, authenticated, service_role;
ALTER ROLE authenticator SET pgrst.db_pre_request = 'portal_private.require_live_session';
NOTIFY pgrst, 'reload config';
