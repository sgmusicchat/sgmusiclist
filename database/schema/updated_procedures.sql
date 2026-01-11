-- Updated stored procedures for MUSG project
-- Includes corrected sp_publish_to_gold with genre normalization

USE rsgmusicchat_silver;

DELIMITER $$

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