-- ============================================================================
-- r/sgmusicchat - GOLD LAYER
-- Purpose: High-performance 7-day TTL serving layer (read-optimized)
-- Architecture: Zero-downtime VIEW pattern for hot-swappable rebuilds
-- Performance Target: <100ms for simple queries, <150ms for boolean search
-- ============================================================================

-- Create Gold database
CREATE DATABASE IF NOT EXISTS rsgmusicchat_gold
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE rsgmusicchat_gold;

-- ============================================================================
-- GOLD EVENTS TABLE (Primary denormalized table)
-- Purpose: Blazing-fast reads for PHP frontend
-- Strategy: Denormalize all JOINs, aggressive indexing
-- ============================================================================

CREATE TABLE gold_events (
    event_id BIGINT UNSIGNED NOT NULL COMMENT 'Same as silver_events.event_id',
    uid VARCHAR(32) NOT NULL COMMENT 'MD5 hash for idempotency',

    -- Deal-breaker columns
    event_name VARCHAR(500) NOT NULL,
    event_date DATE NOT NULL,

    -- Denormalized venue data (avoid JOINs in queries)
    venue_id INT UNSIGNED NOT NULL,
    venue_name VARCHAR(255) NOT NULL,
    venue_slug VARCHAR(255) NOT NULL,
    venue_address TEXT DEFAULT NULL,
    google_maps_url VARCHAR(500) DEFAULT NULL,

    -- Time and pricing
    start_time TIME DEFAULT NULL,
    end_time TIME DEFAULT NULL,
    price_min DECIMAL(8,2) DEFAULT NULL,
    price_max DECIMAL(8,2) DEFAULT NULL,
    price_notes VARCHAR(255) DEFAULT NULL,
    is_free BOOLEAN NOT NULL DEFAULT FALSE,

    -- Event metadata
    description TEXT DEFAULT NULL,
    age_restriction ENUM('all_ages', '18+', '21+', '25+') DEFAULT 'all_ages',
    ticket_url VARCHAR(500) DEFAULT NULL,
    event_url VARCHAR(500) DEFAULT NULL,
    fb_event_url VARCHAR(500) DEFAULT NULL,
    image_url VARCHAR(500) DEFAULT NULL,

    -- Denormalized genre data
    genres_concat VARCHAR(500) DEFAULT NULL COMMENT 'Comma-separated for display: "Techno, House"',
    genres_fulltext TEXT DEFAULT NULL COMMENT 'Space-separated for FULLTEXT: "Techno House"',

    -- Denormalized artist data
    artists_concat VARCHAR(1000) DEFAULT NULL COMMENT 'Comma-separated for display',
    artists_fulltext TEXT DEFAULT NULL COMMENT 'Space-separated for FULLTEXT search',

    -- Combined search tags (for comprehensive boolean search)
    search_tags TEXT DEFAULT NULL COMMENT 'Combined searchable text',

    -- Audit timestamps
    published_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (event_id),
    UNIQUE KEY uk_uid (uid),

    -- B-Tree indexes (every WHERE/ORDER BY column gets an index)
    INDEX idx_event_date (event_date) COMMENT 'Primary filter for 7-day window',
    INDEX idx_venue_id (venue_id) COMMENT 'Filter by venue',
    INDEX idx_venue_date (venue_id, event_date) COMMENT 'Composite for venue pages',
    INDEX idx_price (price_min, price_max) COMMENT 'Price range queries',
    INDEX idx_is_free (is_free, event_date) COMMENT 'Free events filter',
    INDEX idx_published_at (published_at) COMMENT 'Chronological sorting',

    -- Full-Text indexes for Boolean search (+Techno -House)
    FULLTEXT INDEX ft_search_all (event_name, genres_fulltext, artists_fulltext, search_tags)
        WITH PARSER ngram COMMENT 'Comprehensive boolean search',
    FULLTEXT INDEX ft_event_name (event_name)
        WITH PARSER ngram COMMENT 'Event name search',
    FULLTEXT INDEX ft_genres (genres_fulltext)
        WITH PARSER ngram COMMENT 'Genre-specific search'
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Gold layer primary table - 7-day TTL denormalized serving';

-- ============================================================================
-- GOLD EVENTS NEW (Shadow table for zero-downtime rebuilds)
-- Purpose: Identical schema to gold_events for atomic swaps
-- ============================================================================

CREATE TABLE gold_events_new (
    event_id BIGINT UNSIGNED NOT NULL,
    uid VARCHAR(32) NOT NULL,

    -- Deal-breaker columns
    event_name VARCHAR(500) NOT NULL,
    event_date DATE NOT NULL,

    -- Denormalized venue data
    venue_id INT UNSIGNED NOT NULL,
    venue_name VARCHAR(255) NOT NULL,
    venue_slug VARCHAR(255) NOT NULL,
    venue_address TEXT DEFAULT NULL,
    google_maps_url VARCHAR(500) DEFAULT NULL,

    -- Time and pricing
    start_time TIME DEFAULT NULL,
    end_time TIME DEFAULT NULL,
    price_min DECIMAL(8,2) DEFAULT NULL,
    price_max DECIMAL(8,2) DEFAULT NULL,
    price_notes VARCHAR(255) DEFAULT NULL,
    is_free BOOLEAN NOT NULL DEFAULT FALSE,

    -- Event metadata
    description TEXT DEFAULT NULL,
    age_restriction ENUM('all_ages', '18+', '21+', '25+') DEFAULT 'all_ages',
    ticket_url VARCHAR(500) DEFAULT NULL,
    event_url VARCHAR(500) DEFAULT NULL,
    fb_event_url VARCHAR(500) DEFAULT NULL,
    image_url VARCHAR(500) DEFAULT NULL,

    -- Denormalized genre and artist data
    genres_concat VARCHAR(500) DEFAULT NULL,
    genres_fulltext TEXT DEFAULT NULL,
    artists_concat VARCHAR(1000) DEFAULT NULL,
    artists_fulltext TEXT DEFAULT NULL,
    search_tags TEXT DEFAULT NULL,

    -- Audit timestamps
    published_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (event_id),
    UNIQUE KEY uk_uid (uid),

    -- Identical indexes as gold_events
    INDEX idx_event_date (event_date),
    INDEX idx_venue_id (venue_id),
    INDEX idx_venue_date (venue_id, event_date),
    INDEX idx_price (price_min, price_max),
    INDEX idx_is_free (is_free, event_date),
    INDEX idx_published_at (published_at),

    FULLTEXT INDEX ft_search_all (event_name, genres_fulltext, artists_fulltext, search_tags)
        WITH PARSER ngram,
    FULLTEXT INDEX ft_event_name (event_name)
        WITH PARSER ngram,
    FULLTEXT INDEX ft_genres (genres_fulltext)
        WITH PARSER ngram
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Shadow table for zero-downtime Gold rebuilds';

-- ============================================================================
-- VIEW: v_live_events
-- Purpose: Serving layer for PHP application (enables zero-downtime rebuilds)
-- CRITICAL: PHP app must query THIS VIEW, not gold_events directly
-- ============================================================================

CREATE OR REPLACE VIEW v_live_events AS
SELECT
    event_id, uid, event_name, event_date, venue_id, venue_name, venue_slug,
    venue_address, google_maps_url, start_time, end_time, price_min, price_max,
    price_notes, is_free, description, age_restriction, ticket_url, event_url,
    fb_event_url, image_url, genre_count, genres_concat, genres_fulltext,
    artists_concat, artists_fulltext, search_tags, published_at, updated_at
FROM gold_events
WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY);

-- ============================================================================
-- EXAMPLE QUERIES (For performance testing and validation)
-- ============================================================================

-- Query 1: 7-day event list (homepage)
-- Target: <100ms
/*
SELECT
    event_id,
    event_name,
    venue_name,
    event_date,
    start_time,
    genres_concat,
    price_min,
    is_free
FROM v_live_events
WHERE event_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY event_date ASC, start_time ASC
LIMIT 50;
*/

-- Query 2: Boolean genre search (+Techno -House)
-- Target: <150ms
/*
SELECT
    event_id,
    event_name,
    venue_name,
    event_date,
    genres_concat,
    MATCH(genres_fulltext) AGAINST('+Techno -House' IN BOOLEAN MODE) AS relevance_score
FROM v_live_events
WHERE
    event_date >= CURDATE()
    AND MATCH(genres_fulltext) AGAINST('+Techno -House' IN BOOLEAN MODE)
ORDER BY relevance_score DESC, event_date ASC
LIMIT 20;
*/

-- Query 3: Free events
-- Target: <100ms
/*
SELECT
    event_id,
    event_name,
    venue_name,
    event_date,
    genres_concat
FROM v_live_events
WHERE
    is_free = TRUE
    AND event_date >= CURDATE()
ORDER BY event_date ASC
LIMIT 20;
*/

-- Query 4: Venue-specific events
-- Target: <100ms (uses composite index idx_venue_date)
/*
SELECT
    event_id,
    event_name,
    event_date,
    start_time,
    genres_concat,
    price_min
FROM v_live_events
WHERE
    venue_id = 123
    AND event_date >= CURDATE()
ORDER BY event_date ASC;
*/

-- Query 5: Comprehensive search (event name + genres + artists)
-- Target: <150ms
/*
SELECT
    event_id,
    event_name,
    venue_name,
    event_date,
    artists_concat,
    genres_concat,
    MATCH(event_name, genres_fulltext, artists_fulltext, search_tags)
        AGAINST('+Amelie +Lens' IN BOOLEAN MODE) AS relevance
FROM v_live_events
WHERE
    event_date >= CURDATE()
    AND MATCH(event_name, genres_fulltext, artists_fulltext, search_tags)
        AGAINST('+Amelie +Lens' IN BOOLEAN MODE)
ORDER BY relevance DESC, event_date ASC
LIMIT 20;
*/

-- ============================================================================
-- PERFORMANCE TESTING
-- ============================================================================

-- Enable query profiling
-- SET profiling = 1;
-- [Run queries above]
-- SHOW PROFILES;
-- Expected: All queries <150ms

-- Check index usage with EXPLAIN
-- EXPLAIN SELECT ... FROM v_live_events WHERE event_date >= CURDATE();
-- Expected: key=idx_event_date, type=range

-- ============================================================================
-- PRE-AGGREGATION: Add genre_count column for fast filtering
-- ============================================================================

ALTER TABLE gold_events
ADD COLUMN genre_count SMALLINT UNSIGNED DEFAULT 0
    COMMENT 'Number of genres for this event (pre-calculated during publish)';

ALTER TABLE gold_events
ADD INDEX idx_genre_count (genre_count)
    COMMENT 'Filter events by number of genres';

-- Add to shadow table as well
ALTER TABLE gold_events_new
ADD COLUMN genre_count SMALLINT UNSIGNED DEFAULT 0
    COMMENT 'Number of genres for this event (pre-calculated during publish)';

ALTER TABLE gold_events_new
ADD INDEX idx_genre_count (genre_count);

-- ============================================================================
-- PRE-AGGREGATION TABLE: gold_genre_stats
-- Purpose: Genre popularity widget for homepage sidebar
-- Updated during: sp_publish_to_gold()
-- ============================================================================

CREATE TABLE gold_genre_stats (
    genre_id SMALLINT UNSIGNED NOT NULL,
    genre_name VARCHAR(100) NOT NULL,
    upcoming_event_count INT UNSIGNED DEFAULT 0
        COMMENT 'Number of upcoming events for this genre',
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        COMMENT 'Timestamp of last stats update',

    PRIMARY KEY (genre_id),
    INDEX idx_popularity (upcoming_event_count DESC)
        COMMENT 'Sort by most popular genres'
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Pre-aggregated genre statistics for fast homepage rendering';

-- ============================================================================
-- PRE-AGGREGATION TABLE: gold_venue_stats
-- Purpose: Venue event count for venue detail pages
-- Updated during: sp_publish_to_gold()
-- ============================================================================

CREATE TABLE gold_venue_stats (
    venue_id INT UNSIGNED NOT NULL,
    venue_name VARCHAR(255) NOT NULL,
    upcoming_event_count INT UNSIGNED DEFAULT 0
        COMMENT 'Number of upcoming events at this venue',
    last_event_date DATE DEFAULT NULL
        COMMENT 'Date of most recent upcoming event',
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        COMMENT 'Timestamp of last stats update',

    PRIMARY KEY (venue_id),
    INDEX idx_event_count (upcoming_event_count DESC)
        COMMENT 'Sort by most active venues',
    INDEX idx_last_event (last_event_date DESC)
        COMMENT 'Sort by most recent event'
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Pre-aggregated venue statistics for fast venue pages';

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. NO foreign keys in Gold layer - optimized for reads only
-- 2. Denormalization eliminates JOINs (all data in single table)
-- 3. Both tables (gold_events + gold_events_new) maintain identical schemas
-- 4. VIEW swap during rebuild: CREATE OR REPLACE VIEW v_live_events AS SELECT * FROM gold_events_new;
-- 5. PHP app queries v_live_events VIEW for zero-downtime benefit
-- 6. TTL purge: DELETE FROM gold_events WHERE event_date < DATE_SUB(CURDATE(), INTERVAL 7 DAY)
-- 7. FULLTEXT ngram parser supports partial matches and non-English text
-- 8. Covering indexes: idx_is_free and idx_venue_date enable index-only scans
-- 9. Pre-aggregations (genre_count, gold_genre_stats, gold_venue_stats) updated during publish
-- 10. Genre/venue stats enable fast sidebar widgets without live aggregation queries
-- ============================================================================
