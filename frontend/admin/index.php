<?php
/**
 * Admin Dashboard
 * Purpose: View pending events, approve/reject, see quarantined events
 */

require_once '../includes/config.php';
require_admin();

// Get pending events
$sql_pending = "
    SELECT se.event_id, se.event_name, se.event_date, se.start_time,
           dv.venue_name, se.source_type, se.created_at, se.status
    FROM silver_events se
    INNER JOIN dim_venues dv ON se.venue_id = dv.venue_id
    WHERE se.status = 'pending'
    ORDER BY se.created_at DESC
    LIMIT 50
";
$stmt_pending = $pdo_silver->prepare($sql_pending);
$stmt_pending->execute();
$pending_events = $stmt_pending->fetchAll();

// Get quarantined events
$sql_quarantined = "
    SELECT se.event_id, se.event_name, se.event_date, se.rejection_reason, se.created_at
    FROM silver_events se
    WHERE se.status = 'quarantined'
    ORDER BY se.created_at DESC
    LIMIT 20
";
$stmt_quar = $pdo_silver->prepare($sql_quarantined);
$stmt_quar->execute();
$quarantined_events = $stmt_quar->fetchAll();

// Get event counts
$sql_counts = "
    SELECT status, COUNT(*) as count
    FROM silver_events
    GROUP BY status
";
$stmt_counts = $pdo_silver->prepare($sql_counts);
$stmt_counts->execute();
$counts = [];
foreach ($stmt_counts->fetchAll() as $row) {
    $counts[$row['status']] = $row['count'];
}

// Get Gold count
$stmt_gold = $pdo_gold->query("SELECT COUNT(*) as count FROM gold_events");
$gold_count = $stmt_gold->fetch()['count'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Dashboard - r/sgmusicchat</title>
    <style>
        .terminal-prompt {
            position: fixed;
            bottom: 0;
            left: 0;
            width: 100%;
            background: #000;
            border-top: 2px solid #0f0;
            padding: 10px 20px;
            box-shadow: 0 -5px 15px rgba(0, 255, 0, 0.2);
        }
        .prompt-container {
            display: flex;
            align-items: center;
            max-width: 1400px;
            margin: 0 auto;
        }
        .prompt-user {
            color: #0ff;
            margin-right: 10px;
            white-space: nowrap;
        }
        #terminal-input {
            background: transparent;
            border: none;
            color: #0f0;
            font-family: 'Courier New', monospace;
            font-size: 16px;
            width: 100%;
            outline: none;
        }
        /* Push the footer/container up so it's not hidden by the bar */
        .container {
            padding-bottom: 80px; 
        }


        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Courier New', monospace; background: #000; color: #0f0; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: #0ff; margin-bottom: 20px; }
        .nav { margin-bottom: 20px; border-bottom: 1px solid #0f0; padding-bottom: 10px; }
        .nav a { color: #0f0; margin-right: 20px; text-decoration: none; }
        .stats { display: flex; gap: 20px; margin-bottom: 30px; }
        .stat-box { border: 1px solid #0f0; padding: 20px; flex: 1; text-align: center; }
        .stat-number { font-size: 36px; color: #0ff; font-weight: bold; }
        .stat-label { color: #0f0; margin-top: 5px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #ff0; margin-bottom: 15px; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #0f0; color: #000; padding: 10px; text-align: left; }
        td { border: 1px solid #0f0; padding: 10px; }
        tr:nth-child(even) { background: #111; }
        .btn { padding: 5px 10px; margin-right: 5px; text-decoration: none; cursor: pointer; font-size: 12px; font-family: 'Courier New', monospace; }
        .btn-approve { background: #0f0; color: #000; }
        .btn-reject { background: #f00; color: #fff; }
        .btn-view { background: #0ff; color: #000; }
        .source-badge { padding: 2px 5px; font-size: 10px; }
        .source-scraper { background: #ff0; color: #000; }
        .source-user { background: #0ff; color: #000; }
        .source-admin { background: #f0f; color: #000; }
        .logout { float: right; color: #f00; }
    </style>
</head>
<body>
    <div class="container">
        <div class="nav">
            <a href="/admin/index.php">Dashboard</a>
            <a href="/admin/quarantined.php">Quarantined (<?= count($quarantined_events) ?>)</a>
            <a href="/index.php">← Public Site</a>
            <a href="/admin/logout.php" class="logout">Logout</a>
        </div>

        <h1>Admin Dashboard</h1>
        <?php
        if (isset($_GET['msg'])) {
            echo "<p style='color: #0f0; padding: 10px; border: 1px solid #0f0;'>{$_GET['msg']}</p>";
        }
        if (isset($_GET['error'])) {
            echo "<p style='color: #f00; padding: 10px; border: 1px solid #f00;'>{$_GET['error']}</p>";
        }
        ?>
        <div class="stats">
            <div class="stat-box">
                <div class="stat-number"><?= $counts['pending'] ?? 0 ?></div>
                <div class="stat-label">Pending Review</div>
            </div>
            <div class="stat-box">
                <div class="stat-number"><?= $counts['published'] ?? 0 ?></div>
                <div class="stat-label">Published (Silver)</div>
            </div>
            <div class="stat-box">
                <div class="stat-number"><?= $gold_count ?></div>
                <div class="stat-label">Live (Gold)</div>
            </div>
            <div class="stat-box">
                <div class="stat-number"><?= $counts['quarantined'] ?? 0 ?></div>
                <div class="stat-label">Quarantined</div>
            </div>
            <div class="stat-box">
                <div class="stat-number"><?= $counts['rejected'] ?? 0 ?></div>
                <div class="stat-label">Rejected</div>
            </div>
        </div>

        <div class="section">
            <h2>Pending Events (<?= count($pending_events) ?>)</h2>

            <?php if (empty($pending_events)): ?>
                <p style="color: #666; padding: 20px;">No pending events. All submissions have been processed!</p>
            <?php else: ?>
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Event Name</th>
                            <th>Venue</th>
                            <th>Date</th>
                            <th>Source</th>
                            <th>Submitted</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($pending_events as $event): ?>
                            <tr>
                                <td><?= $event['event_id'] ?></td>
                                <td><?= htmlspecialchars($event['event_name']) ?></td>
                                <td><?= htmlspecialchars($event['venue_name']) ?></td>
                                <td><?= date('M j, Y', strtotime($event['event_date'])) ?></td>
                                <td>
                                    <span class="source-badge source-<?= $event['source_type'] ?>">
                                        <?= strtoupper($event['source_type']) ?>
                                    </span>
                                </td>
                                <td><?= date('M j, g:i A', strtotime($event['created_at'])) ?></td>
                                <td>
                                    <a href="/admin/approve.php?id=<?= $event['event_id'] ?>"
                                       class="btn btn-approve"
                                       onclick="return confirm('Approve this event?')">
                                        ✓ Approve
                                    </a>
                                    <a href="/admin/reject.php?id=<?= $event['event_id'] ?>"
                                       class="btn btn-reject">
                                        ✗ Reject
                                    </a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </div>

        <div class="section">
            <h2>Recent Quarantined Events (<?= count($quarantined_events) ?>)</h2>
            <?php if (empty($quarantined_events)): ?>
                <p style="color: #666; padding: 20px;">No quarantined events. The WAP audit is working perfectly!</p>
            <?php else: ?>
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Event Name</th>
                            <th>Date</th>
                            <th>Reason</th>
                            <th>Quarantined At</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($quarantined_events as $event): ?>
                            <tr>
                                <td><?= $event['event_id'] ?></td>
                                <td><?= htmlspecialchars($event['event_name']) ?></td>
                                <td><?= date('M j, Y', strtotime($event['event_date'])) ?></td>
                                <td style="color: #f00;"><?= htmlspecialchars($event['rejection_reason']) ?></td>
                                <td><?= date('M j, g:i A', strtotime($event['created_at'])) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </div>

        <div style="border-top: 1px solid #0f0; margin-top: 40px; padding-top: 20px; text-align: center; font-size: 12px; color: #666;">
            Logged in as: <?= $_SESSION['admin_username'] ?>
        </div>
    </div>


</body>
</html>
