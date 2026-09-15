-- A revoked or deleted enrollment cannot become usable again by changing status.
-- A new enrollment needs a new profile_id; external object purging remains separate.
CREATE FUNCTION kof5.prevent_voice_profile_reactivation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF (OLD.status = 'revoked' AND NEW.status NOT IN ('revoked', 'deleted'))
       OR (OLD.status = 'deleted' AND NEW.status <> 'deleted') THEN
        RAISE EXCEPTION 'revoked or deleted voice profile requires a new enrollment'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION kof5.prevent_voice_profile_reactivation()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER voice_profile_terminal_states
    BEFORE UPDATE ON kof5.patient_voice_profile
    FOR EACH ROW EXECUTE FUNCTION kof5.prevent_voice_profile_reactivation();
