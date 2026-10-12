<?php
// Database connection - replace with your hosting MySQL details
$db_host = 'localhost';
$db_name = 'YOUR_DB_NAME';
$db_user = 'YOUR_DB_USER';
$db_pass = 'YOUR_DB_PASSWORD';

// Server timezone (examples: Africa/Casablanca, Asia/Riyadh, Africa/Cairo)
date_default_timezone_set('Africa/Casablanca');

try {
    $conn = new PDO("mysql:host=$db_host;dbname=$db_name;charset=utf8mb4", $db_user, $db_pass);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $conn->exec("SET time_zone = '" . date('P') . "'");
} catch(PDOException $e) {
    die("Database connection failed: " . $e->getMessage());
}