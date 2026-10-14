<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

// Redirect to unified Customers Hub
header('Location: customers.php' . (!empty($_SERVER['QUERY_STRING']) ? '?' . $_SERVER['QUERY_STRING'] : ''));
exit();