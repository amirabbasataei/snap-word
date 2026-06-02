-- 002_friend_challenge_room.up.sql
-- Adds room_id to friend_challenges so both players can join the private WS room
-- before a match record is created.
ALTER TABLE friend_challenges ADD COLUMN IF NOT EXISTS room_id TEXT;
