-- Safety-event storage boundary only. No clinical logging flow or retention policy exists yet.
-- Keep speech, audio and free-text details out of this table.
CREATE TABLE kof5.safety_audit_event (
    event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid REFERENCES kof5.hospital_patient (patient_id) ON DELETE SET NULL,
    event_type text NOT NULL CHECK (event_type IN (
        'patient_dissent', 'identity_question', 'ambient_audio_discarded',
        'high_risk_utterance_detected', 'alert_created', 'alert_delivered',
        'alert_acknowledged', 'alert_failed', 'conversation_force_stopped'
    )),
    occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX safety_audit_event_patient_time_idx
    ON kof5.safety_audit_event (patient_id, occurred_at);

ALTER TABLE kof5.safety_audit_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE kof5.safety_audit_event FORCE ROW LEVEL SECURITY;
REVOKE ALL ON kof5.safety_audit_event FROM PUBLIC, anon, authenticated, service_role;
-- No client or service policy: institution-approved writer, readers and retention are pending.
