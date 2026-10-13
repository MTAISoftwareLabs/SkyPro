<?php
require_once '../includes/api_boot.php';

// Device activation by MAC/ID is disabled for SkyPro (Username/Password authentication only).
app_emit_activation_json($conn, '', [
    'success' => false,
    'activated' => false,
    'message' => 'device_activation_disabled',
], 403);
