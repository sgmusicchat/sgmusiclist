<?php
/**
 * Event Submission Form (Public)
 * Purpose: Allow visitors to submit events → Bronze + Silver (status='pending')
 * Flow: POST → Bronze audit trail → Silver (sp_upsert_event) → Admin approval
 */

require_once '../includes/config.php';

$success_message = '';
$error_message = '';

// Fetch venues for dropdown
$sql_venues = "SELECT venue_id, venue_name FROM dim_venues WHERE is_active = 1 ORDER BY venue_name";
$stmt_venues = $pdo_silver->prepare($sql_venues);
$stmt_venues->execute();
$venues = $stmt_venues->fetchAll();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        // Handle new venue creation if "Other" was selected
        $venue_id = $_POST['venue_id'];
        if ($venue_id === 'other' && !empty($_POST['new_venue_name'])) {
            // Create new venue with minimal information
            $sql_new_venue = "
                INSERT INTO dim_venues (venue_name, venue_slug, is_active, created_at)
                VALUES (:venue_name, :venue_slug, 1, NOW())
            ";
            $venue_slug = strtolower(preg_replace('/[^a-z0-9]+/', '-', $_POST['new_venue_name']));
            $stmt_new_venue = $pdo_silver->prepare($sql_new_venue);
            $stmt_new_venue->execute([
                'venue_name' => trim($_POST['new_venue_name']),
                'venue_slug' => $venue_slug
            ]);
            $venue_id = $pdo_silver->lastInsertId();
        }

        // Step 1: Write to Bronze (audit trail)
        $sql_bronze = "
            INSERT INTO bronze_user_submissions (submitted_at, submission_ip, raw_form_data, user_agent)
            VALUES (NOW(), :ip, :form_data, :user_agent)
        ";
        $stmt_bronze = $pdo_bronze->prepare($sql_bronze);
        $stmt_bronze->execute([
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            'form_data' => json_encode($_POST),
            'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown'
        ]);
        $bronze_id = $pdo_bronze->lastInsertId();

        // Step 2: Call sp_upsert_event to write to Silver
        $sql_upsert = "
            CALL sp_upsert_event(
                :venue_id, :event_date, :event_name, :start_time, :end_time, :genres_concat,
                :price_min, :price_max, :is_free, :description, :age_restriction,
                :ticket_url, 'user_submission', :bronze_id,
                @event_id, @is_new
            )
        ";

        $stmt_upsert = $pdo_silver->prepare($sql_upsert);
        $stmt_upsert->execute([
            'venue_id' => $venue_id,
            'event_date' => $_POST['event_date'],
            'event_name' => $_POST['event_name'],
            'start_time' => $_POST['start_time'] ?: null,
            'end_time' => $_POST['end_time'] ?: null,
            'genres_concat' => $_POST['genres_concat'],


            // Check if 'is_free' exists using isset()
            'price_min' => isset($_POST['is_free']) ? null : ($_POST['price_min'] ?: null),
            'price_max' => isset($_POST['is_free']) ? null : ($_POST['price_max'] ?: null),
            
            // Map the checkbox state to 1 (checked) or 0 (unchecked)
            'is_free' => isset($_POST['is_free']) ? 1 : 0,
            
            'description' => $_POST['description'] ?: null,
            'age_restriction' => $_POST['age_restriction'] ?: 'all_ages',
            'ticket_url' => $_POST['ticket_url'] ?: null,
            'bronze_id' => $bronze_id
        ]);
        
        
        $success_message = "✅ Thank you! Your event has been submitted and is pending admin approval.";

        // Clear form
        $_POST = [];
    } catch (Exception $e) {
        $error_message = "❌ Submission failed: " . $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Submit Event - r/sgmusicchat</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Courier New', monospace; background: #000; color: #0f0; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #0f0; margin-bottom: 20px; }
        .nav { margin-bottom: 20px; border-bottom: 1px solid #0f0; padding-bottom: 10px; }
        .nav a { color: #0f0; margin-right: 20px; text-decoration: none; }
        .form-group { margin-bottom: 20px; }
        label { display: block; color: #0ff; margin-bottom: 5px; font-weight: bold; }
        input, select, textarea { width: 100%; padding: 10px; background: #111; color: #0f0; border: 1px solid #0f0; font-family: 'Courier New', monospace; }
        input[type="checkbox"] { width: auto; }
        button { background: #0f0; color: #000; border: none; padding: 15px 30px; font-size: 16px; font-weight: bold; cursor: pointer; font-family: 'Courier New', monospace; }
        button:hover { background: #0ff; }
        .success { background: #0f0; color: #000; padding: 15px; margin-bottom: 20px; }
        .error { background: #f00; color: #fff; padding: 15px; margin-bottom: 20px; }
        .required { color: #ff0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="nav">
            <a href="/index.php">← Back to Events</a>
        </div>

        <h1>Submit Event</h1>

        <?php if ($success_message): ?>
            <div class="success"><?= $success_message ?></div>
        <?php endif; ?>

        <?php if ($error_message): ?>
            <div class="error"><?= $error_message ?></div>
        <?php endif; ?>

        <form method="POST">
            <div class="form-group">
                <label>Venue <span class="required">*</span></label>
                <select name="venue_id" id="venue_select" required onchange="toggleNewVenue()">
                    <option value="">Select a venue...</option>
                    <?php foreach ($venues as $venue): ?>
                        <option value="<?= $venue['venue_id'] ?>"><?= htmlspecialchars($venue['venue_name']) ?></option>
                    <?php endforeach; ?>
                    <option value="other">➕ Other / New Venue</option>
                </select>
            </div>

            <div class="form-group" id="new_venue_field" style="display: none;">
                <label>New Venue Name <span class="required">*</span></label>
                <input type="text" name="new_venue_name" id="new_venue_input" placeholder="Enter venue name..." maxlength="255">
                <small style="color: #ff0; display: block; margin-top: 5px;">This venue will be added to the database after admin review</small>
            </div>

            <div class="form-group">
                <label>Event Name <span class="required">*</span></label>
                <input type="text" name="event_name" required maxlength="500" value="<?= htmlspecialchars($_POST['event_name'] ?? '') ?>">
            </div>

            <div class="form-group">
                <label>Event Date <span class="required">*</span></label>
                <input type="date" name="event_date" required value="<?= htmlspecialchars($_POST['event_date'] ?? '') ?>">
            </div>

            <div class="form-group">
                <label>Start Time</label>
                <input type="time" name="start_time" value="<?= htmlspecialchars($_POST['start_time'] ?? '') ?>">
            </div>

            <div class="form-group">
                <label>End Time</label>
                <input type="time" name="end_time" value="<?= htmlspecialchars($_POST['end_time'] ?? '') ?>">
            </div>
            <div class="form-group">
                <label>Genres</label>
                <input type="text" name="genres_concat" placeholder="e.g., Techno, House, Trance" value="<?= htmlspecialchars($_POST['genres_concat'] ?? '') ?>">
            </div>

            <div class="form-group">
                <label>
                    <input type="checkbox" name="is_free" id="is_free" onchange="togglePrice()">
                    Free Event
                </label>
            </div>

            <div class="form-group" id="price_fields">
                <label>Price (SGD)</label>
                <input type="number" name="price_min" step="0.01" placeholder="Minimum price" value="<?= htmlspecialchars($_POST['price_min'] ?? '') ?>">
                <input type="number" name="price_max" step="0.01" placeholder="Maximum price (optional)" value="<?= htmlspecialchars($_POST['price_max'] ?? '') ?>" style="margin-top: 5px;">
            </div>

            <div class="form-group">
                <label>Age Restriction</label>
                <select name="age_restriction">
                    <option value="all_ages">All Ages</option>
                    <option value="18+">18+</option>
                    <option value="21+">21+</option>
                    <option value="25+">25+</option>
                </select>
            </div>

            <div class="form-group">
                <label>Description</label>
                <textarea name="description" rows="4" placeholder="Event details..."><?= htmlspecialchars($_POST['description'] ?? '') ?></textarea>
            </div>

            <div class="form-group">
                <label>Ticket URL</label>
                <input type="url" name="ticket_url" placeholder="https://..." value="<?= htmlspecialchars($_POST['ticket_url'] ?? '') ?>">
            </div>

            <button type="submit">Submit Event for Review</button>
        </form>

        <div style="margin-top: 40px; padding: 15px; border: 1px solid #0f0; font-size: 12px;">
            <strong>Note:</strong> Your submission will be reviewed by admins before appearing on the site.
            This helps maintain data quality and prevent spam.
        </div>
    </div>

    <script>
        function toggleNewVenue() {
            const venueSelect = document.getElementById('venue_select');
            const newVenueField = document.getElementById('new_venue_field');
            const newVenueInput = document.getElementById('new_venue_input');

            if (venueSelect.value === 'other') {
                newVenueField.style.display = 'block';
                newVenueInput.required = true;
            } else {
                newVenueField.style.display = 'none';
                newVenueInput.required = false;
                newVenueInput.value = '';
            }
        }

        function togglePrice() {
            const isFree = document.getElementById('is_free').checked;
            document.getElementById('price_fields').style.display = isFree ? 'none' : 'block';
        }
    </script>
</body>
</html>
