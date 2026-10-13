<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/admin_auth.php';

// Device activations are disabled for SkyPro (Username/Password authentication only).
header('Location: index.php');
exit;