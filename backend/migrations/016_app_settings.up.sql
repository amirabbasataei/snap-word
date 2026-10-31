-- Runtime switches an admin can flip without a redeploy (Phase 23).
-- First key: otp_sms_enabled ("true"/"false") — when false, no SMS is sent and
-- the fixed code 1111 is accepted at verify-otp. A missing row = default (true).
CREATE TABLE app_settings (
    key        VARCHAR(64) PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by VARCHAR(64) NOT NULL DEFAULT ''
);
