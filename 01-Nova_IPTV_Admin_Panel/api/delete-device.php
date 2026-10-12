<?php
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;

$deviceId = '';
$deviceToken = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    $deviceId = isset($data['device_id']) ? trim((string)$data['device_id']) : '';
    $deviceToken = isset($data['device_token']) ? trim((string)$data['device_token']) : '';
}

if ($deviceId === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Device ID is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

// إنهاء التفعيل مسموح فقط لمالك الجهاز (token).
// بدون token مخزّن: نرفض الطلب حتى لا يقدر جهاز آخر (بعد QR link) ينهي تفعيل الهدف.
$storedHash = app_api_device_token_hash($conn, $deviceId);
if ($storedHash === '' || !app_api_verify_device_ownership($conn, $deviceId, $deviceToken)) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'ownership_required'], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    // لا نحذف السجل نهائياً: وإلا يُعاد التسجيل كجهاز جديد بعد إعادة التثبيت.
    // إنهاء التفعيل + مسح القائمة فقط (ليس status=deleted — ذلك مخصّص لحذف الأدمن وإعادة المنح).
    $stmt = $conn->prepare(
        "UPDATE activated_devices
         SET status = 'expired',
             expiry_date = NOW(),
             custom_domain = NULL,
             web_manage_code = NULL,
             web_manage_code_months = NULL,
             web_manage_unlocked_at = NULL,
             web_manage_unlocked_fp = NULL
         WHERE device_id = ?"
    );
    $stmt->execute([$deviceId]);
    logActivity($conn, 'delete_device', $deviceId, 'Device expired from app (soft; keep row to block free re-register)');
    echo json_encode(['success' => true, 'message' => 'Device deleted'], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
