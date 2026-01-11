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
-- PROCEDURE: sp_audit_pending_events
-- Purpose: Audit all pending events for data quality issues
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_audit_pending_events$$

CREATE PROCEDURE sp_audit_pending_events(
    OUT p_error_count INT,
    OUT p_quarantined_count INT,
    OUT p_error_summary TEXT
)
BEGIN
    DECLARE v_past_date_count INT;
    DECLARE v_missing_venue_count INT;

    -- Initialize
    SET p_error_count = 0;
    SET p_quarantined_count = 0;
    SET p_error_summary = '';

    -- Check for events with past dates
    SELECT COUNT(*) INTO v_past_date_count
    FROM silver_events
    WHERE status = 'pending' AND event_date < CURDATE();

    -- Check for events with missing venues
    SELECT COUNT(*) INTO v_missing_venue_count
    FROM silver_events se
    LEFT JOIN dim_venues dv ON se.venue_id = dv.venue_id
    WHERE se.status = 'pending' AND dv.venue_id IS NULL;

    SET p_error_count = v_past_date_count + v_missing_venue_count;

    IF v_past_date_count > 0 THEN
        SET p_error_summary = CONCAT(p_error_summary, v_past_date_count, ' events with past dates. ');
    END IF;

    IF v_missing_venue_count > 0 THEN
        SET p_error_summary = CONCAT(p_error_summary, v_missing_venue_count, ' events with missing venues. ');
    END IF;

    -- Log to audit
    INSERT INTO wap_audit_log (operation, event_id, admin_user, notes, executed_at)
    VALUES ('audit', NULL, 'system', p_error_summary, NOW());
END$$

-- ============================================================================
-- PROCEDURE: sp_publish_to_gold_single
-- Purpose: Publish a single event to Gold layer (used by admin and batch)
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_publish_to_gold_single$$

CREATE PROCEDURE sp_publish_to_gold_single(
    IN p_event_id BIGINT UNSIGNED,
    IN p_admin_user VARCHAR(50),
    IN p_notes TEXT
)
BEGIN
    -- Normalize genres
    INSERT IGNORE INTO event_genres (event_id, genre_id)
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
    WHERE se.event_id = p_event_id AND se.status = 'pending'
    ON DUPLICATE KEY UPDATE
        event_name = VALUES(event_name),
        updated_at = NOW();

    -- Update Silver status
    UPDATE silver_events SET status = 'published', published_at = NOW() WHERE event_id = p_event_id;

    -- Audit log
    INSERT INTO wap_audit_log (operation, event_id, admin_user, notes, executed_at)
    VALUES ('publish', p_event_id, p_admin_user, p_notes, NOW());
END$$

-- ============================================================================
-- PROCEDURE: sp_publish_to_gold (Batch version for auto-publish)
-- Purpose: Publish all pending events to Gold layer
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_publish_to_gold$$

CREATE PROCEDURE sp_publish_to_gold(
    IN p_batch_size INT,
    OUT p_published_count INT,
    OUT p_result_message VARCHAR(500)
)
BEGIN
    DECLARE v_event_id BIGINT UNSIGNED;
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_error_count INT DEFAULT 0;

    DECLARE event_cursor CURSOR FOR
        SELECT event_id
        FROM silver_events
        WHERE status = 'pending'
        LIMIT p_batch_size;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    SET p_published_count = 0;

    OPEN event_cursor;

    publish_loop: LOOP
        FETCH event_cursor INTO v_event_id;

        IF v_done THEN
            LEAVE publish_loop;
        END IF;

        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            BEGIN
                SET v_error_count = v_error_count + 1;
            END;

            -- Call single-event publisher
            CALL sp_publish_to_gold_single(v_event_id, 'auto_publish', 'Automated batch publish');
            SET p_published_count = p_published_count + 1;
        END;
    END LOOP;

    CLOSE event_cursor;

    -- Set result message
    IF p_published_count = 0 THEN
        SET p_result_message = 'No pending events to publish';
    ELSEIF v_error_count > 0 THEN
        SET p_result_message = CONCAT('Published ', p_published_count, ' events (', v_error_count, ' errors)');
    ELSE
        SET p_result_message = CONCAT('SUCCESS: Published ', p_published_count, ' events');
    END IF;
END$$

DELIMITER ;