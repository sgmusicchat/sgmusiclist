<?php
<?php
/**
 * Reject Event - Update Status to Rejected
 */

require_once '../includes/config.php';
require_admin();

$event_id = $_GET['id'] ?? null;
$reason = $_POST['reason'] ?? 'Rejected by admin';

if (!$event_id || !is_numeric($event_id)) {
    die("Invalid event ID.");
}

try {
    // Update status to rejected
    $stmt = $pdo_silver->prepare("UPDATE silver_events SET status = 'rejected', rejection_reason = ?, updated_at = NOW() WHERE event_id = ?");
    $stmt->execute([$reason, $event_id]);
    
    // Redirect back with success
    header("Location: /admin/index.php?msg=Event rejected.");
    exit;
} catch (Exception $e) {
    // Redirect back with error
    header("Location: /admin/index.php?error=Rejection failed: " . $e->getMessage());
    exit;
}