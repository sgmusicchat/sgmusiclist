<?php
/**
 * Reject Pending Event
 * Purpose: Call sp_reject_event stored procedure
 */

require_once '../includes/config.php';
require_admin();

$event_id = $_GET['id'] ?? null;
$reason = $_POST['reason'] ?? 'Manual rejection by admin';

if (!$event_id) {
    header('Location: /admin/index.php');
    exit;
}

// If POST (with reason), reject the event
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $sql = "CALL sp_reject_event(:event_id, :reason)";
        $stmt = $pdo_silver->prepare($sql);
        $stmt->execute([
            'event_id' => $event_id,
            'reason' => $reason
        ]);

        header('Location: /admin/index.php?success=Event rejected');
        exit;
    } catch (Exception $e) {
        header('Location: /admin/index.php?error=' . urlencode($e->getMessage()));
        exit;
    }
}

// If GET, show rejection form
$sql = "SELECT event_id, event_name, event_date FROM silver_events WHERE event_id = :event_id";
$stmt = $pdo_silver->prepare($sql);
$stmt->execute(['event_id' => $event_id]);
$event = $stmt->fetch();

if (!$event) {
    header('Location: /admin/index.php?error=Event not found');
    exit;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reject Event - Admin</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Courier New', monospace; background: #000; color: #0f0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        h1 { color: #f00; margin-bottom: 20px; }
        .event-info { border: 1px solid #0f0; padding: 15px; margin-bottom: 20px; }
        label { display: block; color: #0ff; margin-bottom: 5px; }
        textarea { width: 100%; padding: 10px; background: #111; color: #0f0; border: 1px solid #0f0; font-family: 'Courier New', monospace; }
        .buttons { margin-top: 20px; }
        button { padding: 10px 20px; margin-right: 10px; font-family: 'Courier New', monospace; cursor: pointer; }
        .btn-reject { background: #f00; color: #fff; border: none; }
        .btn-cancel { background: #666; color: #fff; border: none; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Reject Event</h1>

        <div class="event-info">
            <strong><?= htmlspecialchars($event['event_name']) ?></strong><br>
            Date: <?= date('M j, Y', strtotime($event['event_date'])) ?><br>
            ID: <?= $event['event_id'] ?>
        </div>

        <form method="POST">
            <label>Rejection Reason</label>
            <textarea name="reason" rows="4" required>Manual rejection by admin</textarea>

            <div class="buttons">
                <button type="submit" class="btn-reject">Reject Event</button>
                <button type="button" class="btn-cancel" onclick="window.location='/admin/index.php'">Cancel</button>
            </div>
        </form>
    </div>
</body>
</html>
