-- Only the server can access provider metadata; browsers use the authenticated studio API.
CREATE TABLE kof5.guardian_workspace (
 guardian_user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
 body jsonb NOT NULL CHECK ((jsonb_typeof(body->'profile')='object'
   AND jsonb_typeof(body->'memories')='array' AND jsonb_typeof(body->'voice')='object'
   AND octet_length(body::text)<=200000) IS TRUE),
 revision bigint NOT NULL CHECK (revision>0),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE kof5.guardian_workspace ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.guardian_workspace FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.guardian_workspace FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA kof5, api TO service_role;
GRANT SELECT, INSERT, UPDATE ON kof5.guardian_workspace TO service_role;

CREATE FUNCTION api.load_guardian_workspace(_guardian uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('body',body,'revision',revision)
 FROM kof5.guardian_workspace WHERE guardian_user_id=_guardian;
$$;

CREATE FUNCTION api.save_guardian_workspace(_guardian uuid, _expected bigint, _body jsonb) RETURNS bigint
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE saved bigint;
BEGIN
 IF _expected=0 THEN
  INSERT INTO kof5.guardian_workspace(guardian_user_id,body,revision) VALUES(_guardian,_body,1)
   ON CONFLICT DO NOTHING RETURNING revision INTO saved;
 ELSE
  UPDATE kof5.guardian_workspace SET body=_body, revision=revision+1, updated_at=now()
   WHERE guardian_user_id=_guardian AND revision=_expected RETURNING revision INTO saved;
 END IF;
 IF saved IS NULL THEN RAISE SQLSTATE 'PT409' USING MESSAGE='workspace changed'; END IF;
 RETURN saved;
END;
$$;
REVOKE ALL ON FUNCTION api.load_guardian_workspace(uuid), api.save_guardian_workspace(uuid,bigint,jsonb)
 FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION api.load_guardian_workspace(uuid), api.save_guardian_workspace(uuid,bigint,jsonb)
 TO service_role;
NOTIFY pgrst, 'reload schema';
