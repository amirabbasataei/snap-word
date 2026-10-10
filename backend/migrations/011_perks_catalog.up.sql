-- Premium perk catalogues, managed through the admin API instead of being
-- compiled into the server and bundled in the app. Taunts are preset Persian
-- messages (the client only ever sends an id); avatars hold the image itself,
-- served by GET /api/v1/avatars/:id/image. Avatar rows are seeded by
-- scripts/seed_perks_catalog.sh (binary data does not belong in a migration).
CREATE TABLE taunts (
    id         VARCHAR(32) PRIMARY KEY,
    text       TEXT        NOT NULL,
    sort_order INTEGER     NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE avatars (
    id           VARCHAR(24) PRIMARY KEY,
    image        BYTEA       NOT NULL,
    content_type VARCHAR(32) NOT NULL,
    sort_order   INTEGER     NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO taunts (id, text, sort_order) VALUES
    ('what_happened', 'چی شد؟ نفست تموم شد؟', 1),
    ('hurry_up', 'زود باش!', 2),
    ('your_turn', 'نوبت توئه، بجنب!', 3),
    ('thinking', 'داری فکر می‌کنی یا خوابیدی؟', 4),
    ('too_easy', 'این که خیلی راحت بود 😎', 5),
    ('lucky', 'شانس آوردی!', 6),
    ('nice_one', 'آفرین، کلمهٔ خوبی بود 👏', 7),
    ('good_game', 'بازی خوبی بود 🤝', 8),
    ('oops', 'ای وای! 😅', 9);
