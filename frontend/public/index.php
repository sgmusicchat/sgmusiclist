<?php
/**
 * Homepage - Event Listing (Refactored for PHP 8.1+ & Terminal Functionality)
 */
require_once '../includes/config.php';

// 1. Fetch Events (Gold Layer)
$sql = "
    SELECT
        event_id, event_name, venue_name, venue_slug, event_date,
        start_time, genres_concat, price_min, price_max,
        is_free, image_url, ticket_url
    FROM v_live_events
    WHERE event_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
    ORDER BY event_date ASC, start_time ASC
    LIMIT 50
";
$stmt = $pdo_gold->prepare($sql);
$stmt->execute();
$events = $stmt->fetchAll();

// 2. Fetch Genre Stats
$sql_genres = "
    SELECT genre_name, upcoming_event_count
    FROM gold_genre_stats
    WHERE upcoming_event_count > 0
    ORDER BY upcoming_event_count DESC
    LIMIT 10
";
$stmt_genres = $pdo_gold->prepare($sql_genres);
$stmt_genres->execute();
$popular_genres = $stmt_genres->fetchAll();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>r/sgmusicchat - Singapore Electronic Music Events</title>
    <style>
        /* CSS Reset & Terminal Theme */
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Courier New', monospace; background: #000; color: #0f0; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; padding-bottom: 100px; }
        
        /* Header & Nav */
        h1 { color: #0f0; margin-bottom: 20px; font-size: 24px; }
        .header { border-bottom: 2px solid #0f0; padding-bottom: 10px; margin-bottom: 20px; }
        .nav { margin-bottom: 20px; }
        .nav a { color: #0f0; margin-right: 20px; text-decoration: none; }
        .nav a:hover { text-decoration: underline; }

        /* Layout */
        .main-content { display: flex; gap: 40px; }
        .events { flex: 3; }
        .sidebar { flex: 1; }

        /* Event Cards */
        .event { border: 1px solid #0f0; padding: 15px; margin-bottom: 15px; }
        .event-date { color: #ff0; font-weight: bold; }
        .event-name { color: #0ff; font-size: 18px; margin: 5px 0; }
        .event-venue { color: #0f0; }
        .event-genres { color: #f0f; font-size: 12px; margin: 5px 0; }
        .event-price { color: #fff; margin: 5px 0; }
        .event-free { color: #ff0; font-weight: bold; }

        /* Sidebar Boxes */
        .sidebar-box { border: 1px solid #0f0; padding: 15px; margin-bottom: 20px; }
        .sidebar-box h3 { color: #0ff; margin-bottom: 10px; font-size: 16px; }
        .genre-item { margin: 5px 0; font-size: 14px; }

        /* Terminal Prompt Bar */
        .terminal-prompt { position: fixed; bottom: 0; left: 0; width: 100%; background: #000; border-top: 2px solid #0f0; padding: 10px 20px; z-index: 1000; }
        .prompt-container { display: flex; align-items: center; max-width: 1200px; margin: 0 auto; }
        .prompt-user { color: #0ff; margin-right: 10px; }
        #terminal-input { background: transparent; border: none; color: #0f0; font-family: inherit; font-size: 16px; width: 100%; outline: none; }
        
        .no-events { color: #f00; padding: 20px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>r/sgmusicchat</h1>
            <p>Singapore Electronic Music Events (Next 7 Days)</p>
        </header>

        <nav class="nav">
            <a href="/index.php">Home</a>
            <a href="/search.php">Search</a>
            <a href="/submit.php">Submit Event</a>
            <a href="/admin/">Admin</a>
        </nav>

        <div id="display-area">
            <main class="main-content">
                <section class="events">
                    <h2 style="color: #0ff; margin-bottom: 15px;">Upcoming Events (<?= count($events) ?>)</h2>

                    <?php if (empty($events)): ?>
                        <div class="no-events">
                            No upcoming events in the next 7 days.<br>
                            <a href="/submit.php" style="color: #0ff;">Be the first to submit an event!</a>
                        </div>
                    <?php else: ?>
                        <?php foreach ($events as $event): ?>
                            <article class="event">
                                <div class="event-date">
                                    <?= date('D, M j Y', strtotime($event['event_date'] ?? 'today')) ?>
                                    <?= !empty($event['start_time']) ? ' @ ' . date('g:i A', strtotime($event['start_time'])) : '' ?>
                                </div>
                                <div class="event-name"><?= htmlspecialchars($event['event_name'] ?? '') ?></div>
                                <div class="event-venue">📍 <?= htmlspecialchars($event['venue_name'] ?? 'TBA') ?></div>
                                <?php if (!empty($event['genres_concat'])): ?>
                                    <div class="event-genres">🎵 <?= htmlspecialchars($event['genres_concat']) ?></div>
                                <?php endif; ?>
                                <div class="event-price">
                                    <?php if ($event['is_free']): ?>
                                        <span class="event-free">FREE ENTRY</span>
                                    <?php else: ?>
                                        💰 SGD $<?= number_format((float)($event['price_min'] ?? 0), 0) ?>
                                        <?php if (!empty($event['price_max']) && $event['price_max'] > $event['price_min']): ?>
                                            - $<?= number_format((float)$event['price_max'], 0) ?>
                                        <?php endif; ?>
                                    <?php endif; ?>
                                </div>
                                <?php if (!empty($event['ticket_url'])): ?>
                                    <div style="margin-top: 10px;">
                                        <a href="<?= htmlspecialchars($event['ticket_url']) ?>" target="_blank" style="color: #ff0; text-decoration: underline;">🎟️ Get Tickets</a>
                                    </div>
                                <?php endif; ?>
                            </article>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </section>

                <aside class="sidebar">
                    <div class="sidebar-box">
                        <h3>Popular Genres</h3>
                        <?php foreach ($popular_genres as $genre): ?>
                            <div class="genre-item">
                                <a href="/search.php?genre=<?= urlencode($genre['genre_name'] ?? '') ?>" style="color: #0f0; text-decoration: none;">
                                    <?= htmlspecialchars($genre['genre_name'] ?? 'Unknown') ?>
                                    <span style="color: #fff;">(<?= (int)($genre['upcoming_event_count'] ?? 0) ?>)</span>
                                </a>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </aside>
            </main>
        </div> <footer style="border-top: 1px solid #0f0; margin-top: 40px; padding-top: 20px; text-align: center; font-size: 12px; color: #666;">
            Powered by Gutsy Startup Architecture | Data refreshes hourly
        </footer>
    </div>

    <div class="terminal-prompt">
        <div class="prompt-container">
            <span class="prompt-user">newuser:~$</span>
            <input type="text" id="terminal-input" placeholder="Query events (e.g., 'show techno')..." autofocus autocomplete="off">
        </div>
    </div>

    <script>
    const input = document.getElementById('terminal-input');
    const display = document.getElementById('display-area');

    input.addEventListener('keypress', function (e) {
        if (e.key === 'Enter') {
            const cmd = this.value.trim();
            if (!cmd) return;

            // Visual feedback while loading
            display.innerHTML = `<div style="padding:40px; color:#0f0; font-family:monospace;">> ACCESSING DATABASE...<br>> ANALYZING: "${cmd}"...<br><span class="blink">_</span></div>`;

            fetch('nlp_handler.php', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'text=' + encodeURIComponent(cmd)
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    renderTable(cmd, data.data);
                } else {
                    display.innerHTML = `<div style="padding:20px; color:#f00;">ERROR: ${data.message}</div>
                                         <p><a href="javascript:location.reload()" style="color:#0ff;">[ Back to Home ]</a></p>`;
                }
            })
            .catch(err => {
                display.innerHTML = `<div style="padding:20px; color:#f00;">CONNECTION ERROR: Ensure nlp_handler.php exists.</div>`;
            });
            this.value = '';
        }
    });

    function renderTable(query, rows) {
        if (!rows || rows.length === 0) {
            display.innerHTML = `
                <div style="padding:20px; border:1px solid #ff0;">
                    <p style="color:#ff0;">> 0 RECORDS FOUND FOR: "${query}"</p>
                    <p style="margin-top:20px;"><a href="javascript:location.reload()" style="color:#0ff; text-decoration:none;">[ RETURN TO MAIN VIEW ]</a></p>
                </div>`;
            return;
        }

        // Start with the Header matching your index style
        let html = `
            <h2 style="color:#ff0; margin-bottom:15px; font-size:18px;">> SEARCH_RESULTS: ${query.toUpperCase()} (${rows.length})</h2>
            <main class="main-content">
                <section class="events">`;

        rows.forEach(event => {
            // Handle Price logic exactly like the PHP version
            let priceHTML = '';
            if (parseInt(event.is_free) === 1) {
                priceHTML = `<span class="event-free">FREE ENTRY</span>`;
            } else {
                const min = parseFloat(event.price_min || 0).toFixed(0);
                const max = parseFloat(event.price_max || 0).toFixed(0);
                priceHTML = `💰 SGD $${min}${ (max > min) ? ' - $' + max : '' }`;
            }

            // Build the Card
            html += `
                <article class="event">
                    <div class="event-date">
                        ${event.event_date} ${event.start_time ? ' @ ' + event.start_time : ''}
                    </div>
                    
                    <div class="event-name">${event.event_name || 'Untitled Event'}</div>
                    
                    <div class="event-venue">
                        📍 ${event.venue_name || 'TBA'}
                    </div>

                    ${event.genres_concat ? `<div class="event-genres">🎵 ${event.genres_concat}</div>` : ''}

                    <div class="event-price">
                        ${priceHTML}
                    </div>

                    ${event.ticket_url ? `
                        <div style="margin-top: 10px;">
                            <a href="${event.ticket_url}" target="_blank" style="color: #ff0; text-decoration: underline;">
                                🎟️ Get Tickets
                            </a>
                        </div>` : ''}
                </article>`;
        });

        html += `
                </section>
            </main>
            <p style="margin-top:20px;"><a href="javascript:location.reload()" style="color:#0ff; text-decoration:none;">[ ESC / RETURN TO MAIN VIEW ]</a></p>`;
        
        display.innerHTML = html;
    }
    </script>
</body>
</html>