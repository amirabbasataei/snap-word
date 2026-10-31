DROP TABLE IF EXISTS inbox_messages;
DROP TABLE IF EXISTS notification_campaigns;
ALTER TABLE device_tokens DROP COLUMN IF EXISTS permission;
