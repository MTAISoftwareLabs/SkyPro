<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$deviceId = $_GET['device_id'] ?? '';
$success = $error = '';
$canActivate = adminCan('devices_add');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    if (!$canActivate) {
        header('Location: access_denied.php?perm=devices_add');
        exit;
    }
    $expiry_date = $_POST['expiry_date'] ?? '';
    
    if (empty($expiry_date)) {
        $error = 'يرجى تحديد تاريخ انتهاء التفعيل';
    } else {
        try {
            if (addDevice($conn, $deviceId, $expiry_date)) {
                $success = 'تم تفعيل الجهاز بنجاح';
            } else {
                $error = 'حدث خطأ أثناء تفعيل الجهاز';
            }
        } catch (PDOException $e) {
            if ($e->getCode() == 23000) { // Duplicate entry
                $error = 'هذا الجهاز مفعل بالفعل';
            } else {
                $error = 'حدث خطأ في قاعدة البيانات';
            }
        }
    }
}
?>

<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تفعيل جهاز جديد</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            font-family: 'Cairo', sans-serif;
            background-color: #f8f9fa;
        }
        .card {
            border-radius: 15px;
            box-shadow: 0 0 15px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <div class="container mt-5">
        <div class="row justify-content-center">
            <div class="col-md-8">
                <div class="card">
                    <div class="card-header bg-primary text-white">
                        <h5 class="mb-0">تفعيل جهاز جديد</h5>
                    </div>
                    <div class="card-body">
                        <?php if ($success): ?>
                            <div class="alert alert-success"><?php echo $success; ?></div>
                        <?php endif; ?>
                        
                        <?php if ($error): ?>
                            <div class="alert alert-danger"><?php echo $error; ?></div>
                        <?php endif; ?>
                        
                        <form method="POST" action="" data-admin-perm="devices_add">
                            <?php if (!$canActivate): ?>
                            <div class="alert alert-info">يمكنك معاينة الصفحة فقط؛ تفعيل الجهاز يتطلب صلاحية إضافة أجهزة.</div>
                            <?php endif; ?>
                            <fieldset <?php echo $canActivate ? '' : 'disabled'; ?> style="border:0;padding:0;margin:0;min-width:0;">
                            <div class="mb-3">
                                <label class="form-label">معرف الجهاز</label>
                                <input type="text" class="form-control" value="<?php echo htmlspecialchars($deviceId); ?>" readonly>
                            </div>
                            <div class="mb-3">
                                <label for="expiry_date" class="form-label">تاريخ انتهاء التفعيل</label>
                                <input type="date" class="form-control" id="expiry_date" name="expiry_date" required>
                            </div>
                            <div class="d-grid gap-2">
                                <button type="submit" class="btn btn-primary">تفعيل الجهاز</button>
                            </div>
                            </fieldset>
                            <div class="d-grid gap-2 mt-2">
                                <a href="index.php" class="btn btn-secondary">العودة للرئيسية</a>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html> 