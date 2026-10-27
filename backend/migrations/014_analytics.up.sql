-- Product analytics (behaviour events + retention). Raw events are append-only
-- and partitioned by month on `ts` (the clamped event time) so old months can be
-- dropped cheaply; the admin panel reads the rollup tables, which are kept
-- forever. `ts` (not server_ts) is the partition key because a unique index on a
-- partitioned table must contain it, and (client_event_id, ts) is the only pair
-- that is identical on a client retry — that is what makes ingest idempotent.
CREATE TABLE analytics_events (
    id              BIGSERIAL,
    client_event_id UUID        NOT NULL,
    install_id      UUID        NOT NULL,
    user_id         UUID,
    session_id      UUID,
    name            TEXT        NOT NULL,
    screen          TEXT,
    props           JSONB,
    ts              TIMESTAMPTZ NOT NULL,
    server_ts       TIMESTAMPTZ NOT NULL DEFAULT now(),
    app_version     TEXT,
    platform        TEXT
) PARTITION BY RANGE (ts);

CREATE UNIQUE INDEX idx_analytics_events_dedup ON analytics_events (client_event_id, ts);
CREATE INDEX idx_analytics_events_ts_brin ON analytics_events USING BRIN (ts);
CREATE INDEX idx_analytics_events_install ON analytics_events (install_id, ts);
CREATE INDEX idx_analytics_events_user ON analytics_events (user_id, ts) WHERE user_id IS NOT NULL;
CREATE INDEX idx_analytics_events_name ON analytics_events (name, ts);

-- Last month, this month and next month; the scheduler keeps creating the
-- following ones (repository.EnsureAnalyticsPartitions).
DO $$
DECLARE
    m DATE;
BEGIN
    FOR m IN SELECT generate_series(
        date_trunc('month', now() AT TIME ZONE 'UTC')::date - interval '1 month',
        date_trunc('month', now() AT TIME ZONE 'UTC')::date + interval '1 month',
        interval '1 month')::date
    LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS analytics_events_%s PARTITION OF analytics_events FOR VALUES FROM (%L) TO (%L)',
            to_char(m, 'YYYYMM'), m, (m + interval '1 month')::date);
    END LOOP;
END $$;

-- One row per app install. user_id links a guest's pre-signup activity to the
-- account once they sign in; first_seen/last_seen are Iran-time dates.
CREATE TABLE analytics_installs (
    install_id  UUID PRIMARY KEY,
    user_id     UUID,
    first_seen  DATE NOT NULL,
    last_seen   DATE NOT NULL,
    platform    TEXT,
    app_version TEXT
);
CREATE INDEX idx_analytics_installs_user ON analytics_installs (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_analytics_installs_first_seen ON analytics_installs (first_seen);

-- Rollups (Iran-time days), rebuilt per day by the scheduler.
CREATE TABLE analytics_daily_active (
    day        DATE NOT NULL,
    install_id UUID NOT NULL,
    user_id    UUID,
    events     INTEGER NOT NULL,
    PRIMARY KEY (day, install_id)
);
CREATE INDEX idx_analytics_daily_active_install ON analytics_daily_active (install_id, day);
CREATE INDEX idx_analytics_daily_active_user ON analytics_daily_active (user_id, day) WHERE user_id IS NOT NULL;

CREATE TABLE analytics_daily_counts (
    day     DATE    NOT NULL,
    name    TEXT    NOT NULL,
    count   INTEGER NOT NULL,
    uniques INTEGER NOT NULL,
    PRIMARY KEY (day, name)
);

CREATE TABLE analytics_daily_screens (
    day       DATE    NOT NULL,
    screen    TEXT    NOT NULL,
    views     INTEGER NOT NULL,
    total_ms  BIGINT  NOT NULL,
    median_ms INTEGER NOT NULL,
    PRIMARY KEY (day, screen)
);

CREATE TABLE analytics_daily_sessions (
    day      DATE PRIMARY KEY,
    sessions INTEGER NOT NULL,
    total_ms BIGINT  NOT NULL
);
