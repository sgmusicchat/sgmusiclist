-- ============================================================================
-- r/sgmusicchat - WAP (WRITE-AUDIT-PUBLISH) PROCEDURES
-- ============================================================================

USE rsgmusicchat_silver;

-- ============================================================================
-- WAP AUDIT LOG TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS wap_audit_log (
    log_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    operation VARCHAR(50) NOT NULL,
    event_id BIGINT UNSIGNED,
    admin_user VARCHAR(100),
    notes TEXT,
    executed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id),
    INDEX idx_operation (operation),
    INDEX idx_event_id (event_id),
    INDEX idx_executed_at (executed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$

-- ============================================================================
-- PROCEDURE: sp_upsert_event
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_upsert_event$$

CREATE PROCEDURE sp_upsert_event(
    IN p_venue_id INT UNSIGNED,
    IN p_event_date DATE,
    IN p_event_name VARCHAR(500),
    IN p_start_time TIME,
    IN p_end_time TIME,
    IN p_genres_concat VARCHAR(500),  -- Added for genre handling
    IN p_price_min DECIMAL(8,2),
    IN p_price_max DECIMAL(8,2),
    IN p_is_free BOOLEAN,
    IN p_description TEXT,
    IN p_age_restriction VARCHAR(20),
    IN p_ticket_url VARCHAR(500),
    IN p_source_type VARCHAR(50),
    IN p_source_id BIGINT UNSIGNED,
    OUT p_event_id BIGINT UNSIGNED,
    OUT p_is_new BOOLEAN
)
BEGIN
    DECLARE v_uid VARCHAR(32);
    DECLARE v_existing_id BIGINT UNSIGNED;

    -- Generate idempotency key
    SET v_uid = MD5(CONCAT(
        CAST(p_venue_id AS CHAR),
        CAST(p_event_date AS CHAR),
        IFNULL(CAST(p_start_time AS CHAR), '00:00:00')
    ));

    -- Check for existing event
    SELECT event_id INTO v_existing_id
    FROM silver_events
    WHERE uid = v_uid
    LIMIT 1;

    -- Insert or update the full event record
    INSERT INTO silver_events (
        uid, venue_id, event_date, event_name, start_time, end_time, genres_concat,
        price_min, price_max, is_free, description, age_restriction, ticket_url,
        source_type, source_id, status
    ) VALUES (
        v_uid, p_venue_id, p_event_date, p_event_name, p_start_time, p_end_time, p_genres_concat,
        p_price_min, p_price_max, p_is_free, p_description, p_age_restriction, p_ticket_url,
        p_source_type, p_source_id, 'pending'
    )
    ON DUPLICATE KEY UPDATE
        event_name = VALUES(event_name),
        start_time = VALUES(start_time),
        end_time = VALUES(end_time),
        genres_concat = VALUES(genres_concat),
        price_min = VALUES(price_min),
        price_max = VALUES(price_max),
        is_free = VALUES(is_free),
        description = VALUES(description),
        age_restriction = VALUES(age_restriction),
        ticket_url = VALUES(ticket_url),
        source_type = VALUES(source_type),
        source_id = VALUES(source_id),
        updated_at = CURRENT_TIMESTAMP;

    -- Set output parameters
    IF v_existing_id IS NULL THEN
        SET p_event_id = LAST_INSERT_ID();
        SET p_is_new = TRUE;
    ELSE
        SET p_event_id = v_existing_id;
        SET p_is_new = FALSE;
    END IF;
END$$

-- ============================================================================
-- PROCEDURE: sp_publish_to_gold
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_publish_to_gold$$

CREATE PROCEDURE sp_publish_to_gold(
    IN p_event_id BIGINT UNSIGNED,
    IN p_admin_user VARCHAR(50),
    IN p_notes TEXT
)
BEGIN
    -- Normalize genres: split genres_concat into event_genres (remove spaces for matching)
    INSERT INTO event_genres (event_id, genre_id)
    SELECT se.event_id, dg.genre_id
    FROM silver_events se
    INNER JOIN dim_genres dg ON FIND_IN_SET(dg.genre_name, REPLACE(se.genres_concat, ' ', '')) > 0
    WHERE se.event_id = p_event_id AND se.genres_concat IS NOT NULL;

    -- Publish to Gold
    INSERT INTO rsgmusicchat_gold.gold_events (
        event_id, uid, event_name, event_date, venue_id, venue_name, venue_slug,
        venue_address, google_maps_url, start_time, end_time, price_min, price_max,
        price_notes, is_free, description, age_restriction, ticket_url, event_url,
        fb_event_url, image_url, genre_count, genres_concat, genres_fulltext,
        artists_concat, artists_fulltext, search_tags, published_at
    )
    SELECT
        se.event_id, se.uid, se.event_name, se.event_date, se.venue_id,
        dv.venue_name, dv.venue_slug, dv.address, dv.google_maps_url,
        se.start_time, se.end_time, se.price_min, se.price_max, se.price_notes,
        se.is_free, se.description, se.age_restriction, se.ticket_url, se.event_url,
        se.fb_event_url, se.image_url,
        (SELECT COUNT(*) FROM event_genres WHERE event_id = se.event_id) AS genre_count,
        (SELECT GROUP_CONCAT(dg.genre_name ORDER BY dg.genre_name SEPARATOR ", ")
         FROM event_genres eg INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
         WHERE eg.event_id = se.event_id) AS genres_concat,
        (SELECT GROUP_CONCAT(dg.genre_name ORDER BY dg.genre_name SEPARATOR " ")
         FROM event_genres eg INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
         WHERE eg.event_id = se.event_id) AS genres_fulltext,
        (SELECT GROUP_CONCAT(da.artist_name ORDER BY ea.performance_order SEPARATOR ", ")
         FROM event_artists ea INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
         WHERE ea.event_id = se.event_id) AS artists_concat,
        (SELECT GROUP_CONCAT(da.artist_name ORDER BY ea.performance_order SEPARATOR " ")
         FROM event_artists ea INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
         WHERE ea.event_id = se.event_id) AS artists_fulltext,
        CONCAT_WS(" ", se.event_name, dv.venue_name,
            (SELECT GROUP_CONCAT(dg.genre_name SEPARATOR " ")
             FROM event_genres eg INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
             WHERE eg.event_id = se.event_id),
            (SELECT GROUP_CONCAT(da.artist_name SEPARATOR " ")
             FROM event_artists ea INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
             WHERE ea.event_id = se.event_id)),
        NOW()
    FROM silver_events se
    INNER JOIN dim_venues dv ON se.venue_id = dv.venue_id
    WHERE se.event_id = p_event_id AND se.status = 'pending';

    -- Update Silver status
    UPDATE silver_events SET status = 'published', published_at = NOW() WHERE event_id = p_event_id;

    -- Audit log
    INSERT INTO wap_audit_log (
        operation, event_id, admin_user, notes, executed_at
    ) VALUES (
        'publish', p_event_id, p_admin_user, p_notes, NOW()
    );
END$$

DELIMITER ;