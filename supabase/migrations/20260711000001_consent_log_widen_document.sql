-- Only needed if 20260709400000_consent_log.sql already ran before its
-- CHECK constraint was widened to include 'ai_data_sharing'. Safe to skip if
-- you're running the migrations fresh in order — the updated
-- 20260709400000 file already includes this value.

ALTER TABLE consent_log DROP CONSTRAINT IF EXISTS consent_log_document_check;
ALTER TABLE consent_log ADD CONSTRAINT consent_log_document_check
  CHECK (document IN ('terms', 'privacy', 'ai_data_sharing'));
