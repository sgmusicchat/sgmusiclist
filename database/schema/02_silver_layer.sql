-- ============================================================================
-- r/sgmusicchat - SILVER LAYER
-- Purpose: System of record with full history (NO TTL)
-- Architecture: Kimball dimensional modeling (Star Schema)
-- Data Quality: Enforces referential integrity, CHECK constraints, NOT NULL
-- ============================================================================

-- Create Silver database
CREATE DATABASE IF NOT EXISTS rsgmusicchat_silver
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE rsgmusicchat_silver;

-- ============================================================================
-- DIMENSION TABLE: dim_venues
-- Purpose: Geographic dimension for event locations
-- Pattern: Slowly Changing Dimension Type 2 (via is_active flag)
-- ============================================================================

CREATE TABLE dim_venues (
    venue_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    venue_name VARCHAR(255) NOT NULL,
    venue_slug VARCHAR(255) NOT NULL COMMENT 'URL-friendly slug (e.g., zouk-singapore)',
    address TEXT DEFAULT NULL,
    postal_code VARCHAR(10) DEFAULT NULL,
    google_maps_url VARCHAR(500) DEFAULT NULL,
    capacity INT UNSIGNED DEFAULT NULL COMMENT 'Maximum capacity',
    venue_type ENUM('club', 'bar', 'concert_hall', 'outdoor', 'gallery', 'other') DEFAULT 'other',
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Soft delete flag',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (venue_id),
    UNIQUE KEY uk_venue_slug (venue_slug),
    INDEX idx_venue_name (venue_name),
    INDEX idx_is_active (is_active),
    INDEX idx_venue_type (venue_type)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Venue dimension - geographic and location information';

-- ============================================================================
-- DIMENSION TABLE: dim_artists
-- Purpose: Artist/performer dimension for lineup tracking
-- ============================================================================

CREATE TABLE dim_artists (
    artist_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    artist_name VARCHAR(255) NOT NULL,
    artist_slug VARCHAR(255) NOT NULL COMMENT 'URL-friendly slug',
    bio TEXT DEFAULT NULL COMMENT 'Artist biography',
    spotify_url VARCHAR(500) DEFAULT NULL,
    soundcloud_url VARCHAR(500) DEFAULT NULL,
    instagram_handle VARCHAR(100) DEFAULT NULL,
    website_url VARCHAR(500) DEFAULT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Soft delete flag',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (artist_id),
    UNIQUE KEY uk_artist_slug (artist_slug),
    INDEX idx_artist_name (artist_name),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Artist dimension - performer metadata and social links';

-- ============================================================================
-- DIMENSION TABLE: dim_genres
-- Purpose: Genre taxonomy (controlled vocabulary)
-- Anti-Pattern Prevention: No "Jaywalking" (comma-separated genres in event table)
-- ============================================================================

CREATE TABLE dim_genres (
    genre_id SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    genre_name VARCHAR(100) NOT NULL,
    genre_slug VARCHAR(100) NOT NULL COMMENT 'URL-friendly slug',
    parent_genre_id SMALLINT UNSIGNED DEFAULT NULL COMMENT 'For hierarchical genres (e.g., Deep House → House)',
    sort_order SMALLINT UNSIGNED DEFAULT 999 COMMENT 'Display order in UI',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    PRIMARY KEY (genre_id),
    UNIQUE KEY uk_genre_slug (genre_slug),
    INDEX idx_genre_name (genre_name),
    INDEX idx_is_active (is_active),
    INDEX idx_parent (parent_genre_id),
    FOREIGN KEY (parent_genre_id) REFERENCES dim_genres(genre_id) ON DELETE SET NULL
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Genre dimension - controlled vocabulary for music genres';

-- Pre-populate common electronic music genres for Singapore scene
INSERT INTO dim_genres (genre_name, genre_slug, sort_order) VALUES
    ('Techno', 'techno', 1),
    ('House', 'house', 2),
    ('Trance', 'trance', 3),
    ('Drum and Bass', 'drum-and-bass', 4),
    ('Dubstep', 'dubstep', 5),
    ('Electro', 'electro', 6),
    ('Ambient', 'ambient', 7),
    ('Experimental', 'experimental', 8),
    ('Breakbeat', 'breakbeat', 9),
    ('Garage', 'garage', 10),
    ('Indie', 'indie', 12),
    ('AOR', 'aor', 13),
    ('Electronic', 'electronic', 14),
    ('Progressive', 'progressive', 15),
    ('Minimal', 'minimal', 16),
    ('Deep House', 'deep-house', 17),
    ('Tech House', 'tech-house', 18),
    ('Acid', 'acid', 19),
    ('Synthwave', 'synthwave', 20),
    ('IDM', 'idm', 21),
    ('Downtempo', 'downtempo', 22),
    ('Jungle', 'jungle', 23),
    ('Footwork', 'footwork', 24),
    ('Bass', 'bass', 25),
    ('Trap', 'trap', 26),
    ('Future Bass', 'future-bass', 27),
    ('Glitch', 'glitch', 28),
    ('Industrial', 'industrial', 29),
    ('EBM', 'ebm', 30),
    ('Hardcore', 'hardcore', 31),
    ('Other', 'other', 999);

-- ============================================================================
-- FACT TABLE: silver_events
-- Purpose: Main event fact table (historical system of record)
-- Idempotency: uid = MD5(venue_id + event_date + start_time)
-- WAP Status: pending → published → rejected
-- ============================================================================

CREATE TABLE silver_events (
    event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uid VARCHAR(32) NOT NULL COMMENT 'MD5 hash: MD5(CONCAT(venue_id, event_date, start_time))',

    -- Deal-breaker columns (NOT NULL enforced)
    venue_id INT UNSIGNED NOT NULL COMMENT 'FK to dim_venues - REQUIRED',
    event_date DATE NOT NULL COMMENT 'The date of the event - REQUIRED',
    event_name VARCHAR(500) NOT NULL COMMENT 'Event title - REQUIRED',

    -- Time fields
    start_time TIME DEFAULT NULL COMMENT 'Event start time (HH:MM:SS)',
    end_time TIME DEFAULT NULL COMMENT 'Event end time (HH:MM:SS)',

    -- Genres (temporary for submission, will be normalized to event_genres)
    genres_concat VARCHAR(500) DEFAULT NULL COMMENT 'Comma-separated genres from submission',

    -- Pricing fields
    price_min DECIMAL(8,2) DEFAULT NULL COMMENT 'Minimum price in SGD',
    price_max DECIMAL(8,2) DEFAULT NULL COMMENT 'Maximum price in SGD',
    price_notes VARCHAR(255) DEFAULT NULL COMMENT 'e.g., "Early bird until 1 Jan"',
    is_free BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Free entry flag',

    -- Event metadata
    description TEXT DEFAULT NULL COMMENT 'Event description (HTML allowed)',
    age_restriction ENUM('all_ages', '18+', '21+', '25+') DEFAULT 'all_ages',
    ticket_url VARCHAR(500) DEFAULT NULL COMMENT 'Ticketing platform URL',
    event_url VARCHAR(500) DEFAULT NULL COMMENT 'Official event page',
    fb_event_url VARCHAR(500) DEFAULT NULL COMMENT 'Facebook event URL',
    image_url VARCHAR(500) DEFAULT NULL COMMENT 'Event poster/flyer URL',

    -- WAP (Write-Audit-Publish) status tracking
    status ENUM('pending', 'published', 'rejected', 'quarantined') NOT NULL DEFAULT 'pending'
        COMMENT 'pending=awaiting audit, published=in Gold, rejected=manually rejected, quarantined=auto-rejected',
    rejection_reason TEXT DEFAULT NULL COMMENT 'Why event was rejected or quarantined',

    -- Lineage tracking (data provenance)
    source_type ENUM('scraper', 'user_submission', 'admin_manual') NOT NULL,
    source_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'FK to bronze layer table',
    created_by VARCHAR(100) DEFAULT NULL COMMENT 'Admin username or "system"',

    -- Audit timestamps
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    published_at DATETIME DEFAULT NULL COMMENT 'When status changed to published',

    PRIMARY KEY (event_id),
    UNIQUE KEY uk_uid (uid) COMMENT 'Idempotency key - prevents duplicates',
    INDEX idx_venue_date (venue_id, event_date),
    INDEX idx_event_date (event_date),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    INDEX idx_source (source_type, source_id),
    INDEX idx_published_at (published_at),

    -- Referential integrity
    FOREIGN KEY (venue_id) REFERENCES dim_venues(venue_id) ON DELETE RESTRICT,

    -- Business logic constraints
    CONSTRAINT chk_end_after_start CHECK (
        end_time IS NULL OR start_time IS NULL OR end_time >= start_time
    ),
    CONSTRAINT chk_price_logic CHECK (
        (is_free = TRUE AND price_min IS NULL AND price_max IS NULL) OR
        (is_free = FALSE)
    ),
    CONSTRAINT chk_price_range CHECK (
        price_min IS NULL OR price_max IS NULL OR price_max >= price_min
    )
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Silver fact table - full event history with WAP status';

-- ============================================================================
-- MAPPING TABLE: event_genres
-- Purpose: Many-to-many relationship between events and genres
-- Anti-Pattern: Prevents Jaywalking (storing "techno, house" in single column)
-- ============================================================================

CREATE TABLE event_genres (
    event_id BIGINT UNSIGNED NOT NULL,
    genre_id SMALLINT UNSIGNED NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Primary genre for event',

    PRIMARY KEY (event_id, genre_id),
    INDEX idx_genre_events (genre_id, event_id) COMMENT 'Reverse lookup: events by genre',
    INDEX idx_primary (event_id, is_primary) COMMENT 'Find primary genre per event',

    FOREIGN KEY (event_id) REFERENCES silver_events(event_id) ON DELETE CASCADE,
    FOREIGN KEY (genre_id) REFERENCES dim_genres(genre_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Event-Genre many-to-many mapping - prevents comma-separated values';

-- ============================================================================
-- MAPPING TABLE: event_artists
-- Purpose: Many-to-many relationship between events and artists (lineup)
-- ============================================================================

CREATE TABLE event_artists (
    event_id BIGINT UNSIGNED NOT NULL,
    artist_id INT UNSIGNED NOT NULL,
    performance_order SMALLINT UNSIGNED DEFAULT NULL COMMENT 'Lineup order (1=headliner, 2=support, etc.)',
    is_headliner BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Headliner flag',

    PRIMARY KEY (event_id, artist_id),
    INDEX idx_artist_events (artist_id, event_id) COMMENT 'Reverse lookup: events by artist',
    INDEX idx_headliners (is_headliner, event_id) COMMENT 'Find headliner events',
    INDEX idx_performance_order (event_id, performance_order) COMMENT 'Sorted lineup',

    FOREIGN KEY (event_id) REFERENCES silver_events(event_id) ON DELETE CASCADE,
    FOREIGN KEY (artist_id) REFERENCES dim_artists(artist_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Event-Artist many-to-many mapping - lineup tracking';

-- ============================================================================
-- HELPER VIEWS (Optional - for easier querying)
-- ============================================================================

-- View: Events with denormalized venue information
CREATE VIEW vw_events_with_venue AS
SELECT
    e.event_id,
    e.uid,
    e.event_name,
    e.event_date,
    e.start_time,
    e.end_time,
    e.price_min,
    e.price_max,
    e.is_free,
    e.description,
    e.status,
    v.venue_id,
    v.venue_name,
    v.venue_slug,
    v.address AS venue_address,
    v.google_maps_url,
    e.created_at,
    e.published_at
FROM silver_events e
INNER JOIN dim_venues v ON e.venue_id = v.venue_id;

-- View: Events with genre information (for debugging)
CREATE VIEW vw_events_with_genres AS
SELECT
    e.event_id,
    e.event_name,
    e.event_date,
    e.status,
    GROUP_CONCAT(g.genre_name ORDER BY g.genre_name SEPARATOR ', ') AS genres
FROM silver_events e
LEFT JOIN event_genres eg ON e.event_id = eg.event_id
LEFT JOIN dim_genres g ON eg.genre_id = g.genre_id
GROUP BY e.event_id, e.event_name, e.event_date, e.status;

-- ============================================================================
-- DATA QUALITY CHECKS (SQL Assertions for testing)
-- ============================================================================

-- Check: No events with NULL deal-breaker columns
-- SELECT COUNT(*) AS violations FROM silver_events
-- WHERE venue_id IS NULL OR event_date IS NULL OR event_name IS NULL;
-- Expected: 0

-- Check: No published events in the past
-- SELECT COUNT(*) AS violations FROM silver_events
-- WHERE status = 'published' AND event_date < CURDATE();
-- Expected: 0 (or very few edge cases)

-- Check: No orphaned event_genres entries
-- SELECT COUNT(*) AS violations FROM event_genres eg
-- LEFT JOIN silver_events e ON eg.event_id = e.event_id
-- WHERE e.event_id IS NULL;
-- Expected: 0

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. uid UNIQUE constraint ensures 100% duplicate prevention
-- 2. CHECK constraints validate temporal logic (end_time >= start_time)
-- 3. Foreign keys use RESTRICT on dimensions (prevent orphaned events)
-- 4. Foreign keys use CASCADE on mappings (clean up when event deleted)
-- 5. No TTL on Silver - full history preserved forever
-- 6. status='pending' events await audit validation before Gold promotion
-- 7. Replay capability: Can rebuild Gold from Silver at any time
-- ============================================================================
