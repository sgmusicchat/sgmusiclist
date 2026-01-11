USE rsgmusicchat_gold;

CREATE OR REPLACE VIEW v_live_events AS
SELECT
    event_id, uid, event_name, event_date, venue_id, venue_name, venue_slug,
    venue_address, google_maps_url, start_time, end_time, price_min, price_max,
    price_notes, is_free, description, age_restriction, ticket_url, event_url,
    fb_event_url, image_url, genre_count, genres_concat, genres_fulltext,
    artists_concat, artists_fulltext, search_tags, published_at, updated_at
FROM gold_events
WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY);