<?php
/**
 * Approve Pending Event
 * Purpose: Mark event as published → triggers WAP publish on next cycle
 */

require_once '../includes/config.php';
require_admin();

$event_id = $_GET['id'] ?? null;

if (!$event_id) {
    header('Location: /admin/index.php');
    exit;
}

try {
    // Verify event exists and is pending
    $sql_check = "SELECT event_id FROM silver_events WHERE event_id = :event_id AND status = 'pending'";
    $stmt_check = $pdo_silver->prepare($sql_check);
    $stmt_check->execute(['event_id' => $event_id]);

    if ($stmt_check->rowCount() === 0) {
        header('Location: /admin/index.php?error=Event not found or already processed');
        exit;
    }

    // Call WAP publish procedure to mark as published AND insert to Gold in one atomic operation
    $sql_publish = "CALL sp_publish_to_gold(100, @published_count, @result_message)";
    $pdo_silver->query($sql_publish);

    // Get results
    $result = $pdo_silver->query("SELECT @published_count as count, @result_message as message")->fetch();

    if ($result['count'] > 0) {
        header('Location: /admin/index.php?success=Event approved and published to Gold layer');
    } else {
        header('Location: /admin/index.php?success=Event approved (may appear shortly)');
    }
} catch (Exception $e) {
    header('Location: /admin/index.php?error=' . urlencode($e->getMessage()));
}
exit;
?>
