-- Player messages + the signup gift message (Special Subscription, 7 days).
--
-- player_messages stores EVERY message a player sends inside a match: the
-- preset taunts and, for subscribers, free text. The admin panel reads it.
-- match_id has no FK on purpose: the room id is the match id, but a message
-- must be kept (and shown) even if the match row failed to persist or is purged.
CREATE TABLE player_messages (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id   UUID,
    sender_id  UUID         NOT NULL REFERENCES users(id),
    kind       VARCHAR(8)   NOT NULL CHECK (kind IN ('preset', 'custom')),
    taunt_id   VARCHAR(32)  NOT NULL DEFAULT '',  -- catalogue id of a preset, '' for free text
    text       VARCHAR(200) NOT NULL,             -- what the opponent saw
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX player_messages_created_idx ON player_messages (created_at DESC);
CREATE INDEX player_messages_sender_idx  ON player_messages (sender_id, created_at DESC);
CREATE INDEX player_messages_match_idx   ON player_messages (match_id) WHERE match_id IS NOT NULL;

-- The one shared campaign every new account's gift message hangs off (its
-- counters are bumped per signup by UserRepository.GrantWelcomePremium).
INSERT INTO notification_campaigns
    (id, title, body, route, push, inapp, audience_type, audience, created_by, push_status)
VALUES
    ('00000000-0000-4000-8000-0000000000a1',
     'هدیهٔ ثبت‌نام: ۷ روز اشتراک ویژه',
     'خوش اومدی! ۷ روز اشتراک ویژه هدیه گرفتی. تو بازی آنلاین می‌تونی هر پیامی که خواستی برای حریف بنویسی و آواتار انتخاب کنی.',
     '/profile', false, true, 'users', '{"type":"users"}', 'system', 'none');
