<?php
/**
 * Approve Event - Publish to Gold
 */

require_once '../includes/config.php';
require_admin();

$event_id = $_GET['id'] ?? null;
if (!$event_id || !is_numeric($event_id)) {
    die("Invalid event ID.");
}

try {
    // Call the publish procedure
    $stmt = $pdo_silver->prepare("CALL sp_publish_to_gold(?, 'admin', 'Approved from admin panel')");
    $stmt->execute([$event_id]);
    
    // Redirect back with success
    header("Location: /admin/index.php?msg=Event approved successfully.");
    exit;
} catch (Exception $e) {
    // Redirect back with error
    header("Location: /admin/index.php?error=Approval failed: " . $e->getMessage());
    exit;
}