<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Location: activity_log.php');
    exit();
}

admin_require_csrf();

if (!adminCan('activity_log_clear')) {
    header('Location: access_denied.php?perm=activity_log_clear');
    exit();
}

try {
    $conn->exec("TRUNCATE TABLE activity_log");
} catch (PDOException $e) {
    // الجدول قد يكون غير موجود
}

header('Location: activity_log.php?log_cleared=1');
exit();
