<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';
require_once 'includes/xtream_api.php';

$current_page = 'customers';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$canManage = adminCan('users_manage') || adminIsSuperAdmin() || adminRoleIsAdmin($_SESSION['admin_role'] ?? '');
$isGuest = adminIsGuestRole();

$success = $error = '';
$filter = trim((string)($_GET['filter'] ?? ''));
$search = trim((string)($_GET['q'] ?? ''));

// Handle Actions (POST)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    $action = trim((string)($_POST['action'] ?? ''));

    if ($action === 'add') {
        $username = trim((string)($_POST['username'] ?? ''));
        $password = (string)($_POST['password'] ?? '');
        $customerName = trim((string)($_POST['customer_name'] ?? ''));
        $email = trim((string)($_POST['email'] ?? ''));
        $phone = trim((string)($_POST['phone'] ?? ''));
        $duration = trim((string)($_POST['duration'] ?? '1m'));
        $customDate = trim((string)($_POST['custom_expiry'] ?? ''));
        $maxConnections = max(1, (int)($_POST['max_connections'] ?? 1));
        $packageName = trim((string)($_POST['package_name'] ?? 'Standard'));
        $notes = trim((string)($_POST['notes'] ?? ''));

        $expiryDate = '';
        if ($duration === 'custom' && $customDate !== '') {
            $expiryDate = date('Y-m-d H:i:s', strtotime($customDate));
        } else {
            $days = 30;
            if ($duration === '3m') $days = 90;
            elseif ($duration === '6m') $days = 180;
            elseif ($duration === '1y') $days = 365;
            elseif ($duration === '2y') $days = 730;
            $expiryDate = date('Y-m-d H:i:s', strtotime("+$days days"));
        }

        $res = addCustomer($conn, [
            'username' => $username,
            'password' => $password,
            'customer_name' => $customerName,
            'email' => $email,
            'phone' => $phone,
            'expiry_date' => $expiryDate,
            'max_connections' => $maxConnections,
            'package_name' => $packageName,
            'notes' => $notes,
        ]);

        if ($res['success']) {
            $success = $lang === 'ar' ? 'تمت إضافة المشترك بنجاح!' : 'Customer added successfully!';
            if (!empty($res['sync_message'])) {
                $success .= ' (' . $res['sync_message'] . ')';
            }
        } else {
            $error = $res['message'];
        }
    } elseif ($action === 'extend') {
        $id = (int)($_POST['customer_id'] ?? 0);
        $days = (int)($_POST['days'] ?? 30);
        if ($id > 0 && extendCustomer($conn, $id, $days)) {
            $success = $lang === 'ar' ? "تم تمديد الاشتراك بمقدار $days يوماً بنجاح!" : "Subscription extended by $days days successfully!";
        } else {
            $error = $lang === 'ar' ? 'فشل التمديد.' : 'Failed to extend subscription.';
        }
    } elseif ($action === 'toggle') {
        $id = (int)($_POST['customer_id'] ?? 0);
        if ($id > 0 && toggleCustomerStatus($conn, $id)) {
            $success = $lang === 'ar' ? 'تم تغيير حالة الاشتراك بنجاح!' : 'Customer status updated successfully!';
        } else {
            $error = $lang === 'ar' ? 'فشل تغيير الحالة.' : 'Failed to update status.';
        }
    } elseif ($action === 'delete') {
        $id = (int)($_POST['customer_id'] ?? 0);
        if ($id > 0 && deleteCustomer($conn, $id)) {
            $success = $lang === 'ar' ? 'تم حذف المشترك بنجاح!' : 'Customer deleted successfully!';
        } else {
            $error = $lang === 'ar' ? 'فشل الحذف.' : 'Failed to delete customer.';
        }
    }
}

$customers = getCustomers($conn, $filter, $search);
$allCustomers = getCustomers($conn);
$activeCount = count(array_filter($allCustomers, fn($c) => $c['status'] === 'active'));
$expiredCount = count(array_filter($allCustomers, fn($c) => $c['status'] === 'expired'));
$disabledCount = count(array_filter($allCustomers, fn($c) => $c['status'] === 'disabled'));
$xtreamCfg = xtream_get_config($conn);
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $lang === 'ar' ? 'إدارة المشتركين' : 'Customer Management'; ?> - SkyPro</title>
    <link rel="icon" type="image/png" sizes="32x32" href="assets/images/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="assets/images/favicon-16x16.png">
    <link rel="apple-touch-icon" sizes="180x180" href="assets/images/apple-touch-icon.png">
    <link rel="shortcut icon" href="favicon.ico">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&family=Outfit:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #020617;
            --card-bg: rgba(15, 23, 42, 0.85);
            --border-color: rgba(148, 163, 184, 0.18);
            --neon-blue: #007bff;
            --neon-sky: #38bdf8;
            --silver: #e2e8f0;
        }
        body {
            background-color: var(--bg);
            color: var(--silver);
            font-family: 'Cairo', 'Outfit', sans-serif;
            min-height: 100vh;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }
        .stat-card {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 20px;
            display: flex;
            align-items: center;
            gap: 16px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.4);
            backdrop-filter: blur(10px);
        }
        .stat-icon {
            width: 50px;
            height: 50px;
            border-radius: 14px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.4rem;
        }
        .stat-val { font-size: 1.8rem; font-weight: 800; line-height: 1.1; }
        .stat-lbl { font-size: 0.85rem; color: #94a3b8; font-weight: 600; }
        .action-bar {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 16px;
            margin-bottom: 20px;
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 16px 20px;
        }
        .cust-table-card {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 18px;
            overflow: hidden;
            box-shadow: 0 16px 40px rgba(0,0,0,0.5);
        }
        .table {
            margin-bottom: 0;
            color: var(--silver);
            vertical-align: middle;
        }
        .table thead th {
            background: rgba(2, 6, 23, 0.7);
            border-bottom: 1px solid var(--border-color);
            font-weight: 700;
            font-size: 0.88rem;
            color: #94a3b8;
            padding: 16px 20px;
        }
        .table tbody td {
            padding: 16px 20px;
            border-bottom: 1px solid rgba(148, 163, 184, 0.1);
        }
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 12px;
            border-radius: 999px;
            font-size: 0.78rem;
            font-weight: 700;
        }
        .badge-active { background: rgba(34, 197, 94, 0.15); color: #4ade80; border: 1px solid rgba(34, 197, 94, 0.3); }
        .badge-expired { background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }
        .badge-disabled { background: rgba(148, 163, 184, 0.15); color: #94a3b8; border: 1px solid rgba(148, 163, 184, 0.3); }
        .btn-neon {
            background: linear-gradient(135deg, #007bff, #0056b3);
            color: #fff;
            border: none;
            padding: 10px 22px;
            border-radius: 12px;
            font-weight: 700;
            box-shadow: 0 0 15px rgba(0,123,255,0.4);
            transition: 0.2s;
        }
        .btn-neon:hover {
            color: #fff;
            transform: translateY(-2px);
            box-shadow: 0 0 25px rgba(0,123,255,0.65);
        }
        .pill-btn {
            background: rgba(255,255,255,0.05);
            border: 1px solid var(--border-color);
            color: var(--silver);
            padding: 6px 14px;
            border-radius: 10px;
            font-size: 0.85rem;
            font-weight: 600;
            text-decoration: none;
            transition: 0.2s;
        }
        .pill-btn.active, .pill-btn:hover {
            background: rgba(0,123,255,0.2);
            border-color: var(--neon-blue);
            color: #fff;
        }
        .modal-content {
            background: #0b1329;
            border: 1px solid rgba(0,123,255,0.3);
            border-radius: 20px;
            color: #fff;
            box-shadow: 0 20px 60px rgba(0,0,0,0.8);
        }
        .modal-header { border-bottom: 1px solid var(--border-color); padding: 20px 24px; }
        .modal-footer { border-top: 1px solid var(--border-color); padding: 16px 24px; }
        .form-control, .form-select {
            background: rgba(15, 23, 42, 0.9);
            border: 1px solid var(--border-color);
            color: #fff;
            border-radius: 12px;
            padding: 10px 14px;
        }
        .form-control:focus, .form-select:focus {
            background: rgba(15, 23, 42, 1);
            border-color: var(--neon-blue);
            color: #fff;
            box-shadow: 0 0 12px rgba(0,123,255,0.35);
        }
    </style>
</head>
<body class="admin-app">
    <?php require_once 'includes/header.php'; ?>

    <div class="container-fluid px-3 px-lg-4 mt-4">
        <?php if ($success): ?>
            <div class="alert alert-success d-flex align-items-center gap-2 mb-3 rounded-4 shadow-sm">
                <i class="fas fa-circle-check"></i> <?php echo htmlspecialchars($success); ?>
            </div>
        <?php endif; ?>
        <?php if ($error): ?>
            <div class="alert alert-danger d-flex align-items-center gap-2 mb-3 rounded-4 shadow-sm">
                <i class="fas fa-triangle-exclamation"></i> <?php echo htmlspecialchars($error); ?>
            </div>
        <?php endif; ?>

        <!-- Statistics Cards -->
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background:rgba(0,123,255,0.2); color:#38bdf8;">
                    <i class="fas fa-users"></i>
                </div>
                <div>
                    <div class="stat-val"><?php echo count($allCustomers); ?></div>
                    <div class="stat-lbl"><?php echo $lang === 'ar' ? 'إجمالي المشتركين' : 'Total Customers'; ?></div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background:rgba(34,197,94,0.2); color:#4ade80;">
                    <i class="fas fa-circle-check"></i>
                </div>
                <div>
                    <div class="stat-val" style="color:#4ade80;"><?php echo $activeCount; ?></div>
                    <div class="stat-lbl"><?php echo $lang === 'ar' ? 'الاشتراكات النشطة' : 'Active Lines'; ?></div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background:rgba(239,68,68,0.2); color:#f87171;">
                    <i class="fas fa-clock"></i>
                </div>
                <div>
                    <div class="stat-val" style="color:#f87171;"><?php echo $expiredCount; ?></div>
                    <div class="stat-lbl"><?php echo $lang === 'ar' ? 'الاشتراكات المنتهية' : 'Expired Lines'; ?></div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background:rgba(168,85,247,0.2); color:#c084fc;">
                    <i class="fas fa-server"></i>
                </div>
                <div>
                    <div class="stat-val" style="font-size:1.1rem; padding-top:6px;">
                        <span id="serverStatusBadge" class="badge bg-secondary"><?php echo $lang === 'ar' ? 'فحص...' : 'Checking...'; ?></span>
                    </div>
                    <div class="stat-lbl"><?php echo $lang === 'ar' ? 'سيرفر البث' : 'Streaming Server'; ?></div>
                </div>
            </div>
        </div>

        <!-- Action Bar -->
        <div class="action-bar">
            <div class="d-flex flex-wrap align-items-center gap-2">
                <a href="customers.php" class="pill-btn <?php echo $filter === '' ? 'active' : ''; ?>"><?php echo $lang === 'ar' ? 'الكل' : 'All'; ?> (<?php echo count($allCustomers); ?>)</a>
                <a href="customers.php?filter=active" class="pill-btn <?php echo $filter === 'active' ? 'active' : ''; ?>"><?php echo $lang === 'ar' ? 'النشطة' : 'Active'; ?> (<?php echo $activeCount; ?>)</a>
                <a href="customers.php?filter=expired" class="pill-btn <?php echo $filter === 'expired' ? 'active' : ''; ?>"><?php echo $lang === 'ar' ? 'المنتهية' : 'Expired'; ?> (<?php echo $expiredCount; ?>)</a>
                <a href="customers.php?filter=disabled" class="pill-btn <?php echo $filter === 'disabled' ? 'active' : ''; ?>"><?php echo $lang === 'ar' ? 'المعطلة' : 'Disabled'; ?> (<?php echo $disabledCount; ?>)</a>
            </div>

            <div class="d-flex align-items-center gap-2">
                <form method="GET" class="d-flex align-items-center">
                    <?php if ($filter): ?><input type="hidden" name="filter" value="<?php echo htmlspecialchars($filter); ?>"><?php endif; ?>
                    <input type="text" name="q" class="form-control form-control-sm" style="min-width:180px;" placeholder="<?php echo $lang === 'ar' ? 'بحث عن مشترك...' : 'Search customer...'; ?>" value="<?php echo htmlspecialchars($search); ?>">
                </form>
                <button type="button" class="btn btn-neon d-inline-flex align-items-center gap-2" data-bs-toggle="modal" data-bs-target="#addCustomerModal">
                    <i class="fas fa-user-plus"></i>
                    <span><?php echo $lang === 'ar' ? 'إضافة مشترك جديد' : 'Add New Customer'; ?></span>
                </button>
            </div>
        </div>

        <!-- Table Card -->
        <div class="cust-table-card">
            <div class="table-responsive">
                <table class="table">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th><?php echo $lang === 'ar' ? 'اسم المستخدم' : 'Username'; ?></th>
                            <th><?php echo $lang === 'ar' ? 'كلمة المرور' : 'Password'; ?></th>
                            <th><?php echo $lang === 'ar' ? 'الاسم / الملاحظات' : 'Name / Notes'; ?></th>
                            <th><?php echo $lang === 'ar' ? 'تاريخ الانتهاء' : 'Expiry Date'; ?></th>
                            <th><?php echo $lang === 'ar' ? 'الحالة' : 'Status'; ?></th>
                            <th><?php echo $lang === 'ar' ? 'مزامنة السيرفر' : 'Server Sync'; ?></th>
                            <th class="text-end"><?php echo $lang === 'ar' ? 'إجراءات' : 'Actions'; ?></th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($customers)): ?>
                            <tr>
                                <td colspan="8" class="text-center py-5 text-muted">
                                    <i class="fas fa-user-slash fa-3x mb-3 d-block opacity-50"></i>
                                    <?php echo $lang === 'ar' ? 'لا يوجد مشتركون حالياً.' : 'No customers found.'; ?>
                                </td>
                            </tr>
                        <?php else: ?>
                            <?php foreach ($customers as $c): ?>
                                <?php
                                    $expTime = strtotime($c['expiry_date']);
                                    $isExp = $expTime <= time();
                                    $daysLeft = (int)ceil(($expTime - time()) / 86400);
                                    $badgeClass = ($c['status'] === 'disabled') ? 'badge-disabled' : ($isExp ? 'badge-expired' : 'badge-active');
                                ?>
                                <tr>
                                    <td class="text-muted fw-bold">#<?php echo $c['id']; ?></td>
                                    <td>
                                        <div class="fw-bold text-white d-flex align-items-center gap-2">
                                            <i class="fas fa-user text-primary"></i>
                                            <span><?php echo htmlspecialchars($c['username']); ?></span>
                                        </div>
                                        <div class="small text-muted"><?php echo htmlspecialchars($c['package_name'] ?? 'Standard'); ?> (<?php echo (int)$c['max_connections']; ?> <?php echo $lang === 'ar' ? 'اتصال' : 'conn'; ?>)</div>
                                    </td>
                                    <td>
                                        <div class="d-inline-flex align-items-center gap-1 bg-dark px-2 py-1 rounded-2 border border-secondary">
                                            <span class="font-monospace small pass-peek" id="pass-<?php echo $c['id']; ?>" data-pass="<?php echo htmlspecialchars($c['password']); ?>">••••••••</span>
                                            <button type="button" class="btn btn-sm btn-link text-info p-0 ms-1" onclick="togglePassPeek(<?php echo $c['id']; ?>)"><i class="fas fa-eye"></i></button>
                                            <button type="button" class="btn btn-sm btn-link text-muted p-0 ms-1" onclick="navigator.clipboard.writeText('<?php echo htmlspecialchars($c['password']); ?>')"><i class="fas fa-copy"></i></button>
                                        </div>
                                    </td>
                                    <td>
                                        <div class="fw-semibold"><?php echo htmlspecialchars($c['customer_name'] ?: '—'); ?></div>
                                        <?php if ($c['notes']): ?><div class="small text-muted"><?php echo htmlspecialchars($c['notes']); ?></div><?php endif; ?>
                                    </td>
                                    <td>
                                        <div class="fw-bold"><?php echo date('Y-m-d', $expTime); ?></div>
                                        <div class="small <?php echo $daysLeft > 7 ? 'text-success' : ($daysLeft > 0 ? 'text-warning' : 'text-danger'); ?>">
                                            <?php echo $daysLeft > 0 ? ($lang === 'ar' ? "متبقي $daysLeft يوم" : "$daysLeft days left") : ($lang === 'ar' ? 'منتهي الصلاحية' : 'Expired'); ?>
                                        </div>
                                    </td>
                                    <td>
                                        <span class="status-badge <?php echo $badgeClass; ?>">
                                            <i class="fas fa-circle" style="font-size:0.5rem;"></i>
                                            <?php echo ucfirst($c['status']); ?>
                                        </span>
                                    </td>
                                    <td>
                                        <?php if (($c['server_sync_status'] ?? '') === 'synced'): ?>
                                            <span class="badge bg-success-subtle text-success border border-success-subtle" title="<?php echo htmlspecialchars($c['server_sync_message'] ?? ''); ?>">
                                                <i class="fas fa-check-circle me-1"></i> <?php echo $lang === 'ar' ? 'متزامن' : 'Synced'; ?>
                                            </span>
                                        <?php else: ?>
                                            <div class="d-inline-flex align-items-center gap-1">
                                                <span class="badge bg-warning-subtle text-warning border border-warning-subtle" id="sync-badge-<?php echo $c['id']; ?>" title="<?php echo htmlspecialchars($c['server_sync_message'] ?: 'Pending server synchronization'); ?>" style="cursor:help;">
                                                    <i class="fas fa-clock me-1"></i> <?php echo $lang === 'ar' ? 'معلق' : 'Pending'; ?>
                                                </span>
                                                <button type="button" class="btn btn-sm btn-outline-info p-0 px-2 rounded-pill" id="sync-btn-<?php echo $c['id']; ?>" onclick="retrySync(<?php echo $c['id']; ?>)" title="<?php echo $lang === 'ar' ? 'إعادة المزامنة مع السيرفر' : 'Retry Sync to IPTV Server'; ?>">
                                                    <i class="fas fa-rotate"></i>
                                                </button>
                                            </div>
                                        <?php endif; ?>
                                    </td>
                                    <td class="text-end">
                                        <div class="dropdown d-inline-block">
                                            <button class="btn btn-sm btn-outline-secondary dropdown-toggle rounded-pill px-3" type="button" data-bs-toggle="dropdown">
                                                <?php echo $lang === 'ar' ? 'إجراء' : 'Action'; ?>
                                            </button>
                                            <ul class="dropdown-menu dropdown-menu-dark dropdown-menu-end shadow">
                                                <li>
                                                    <button type="button" class="dropdown-item" onclick="retrySync(<?php echo $c['id']; ?>)">
                                                        <i class="fas fa-arrows-rotate text-info me-2"></i> <?php echo $lang === 'ar' ? 'مزامنة مع سيرفر البث' : 'Sync to Streaming Server'; ?>
                                                    </button>
                                                </li>
                                                <li><hr class="dropdown-divider"></li>
                                                <li>
                                                    <form method="POST" class="d-inline">
                                                        <?php echo admin_csrf_field(); ?>
                                                        <input type="hidden" name="action" value="extend">
                                                        <input type="hidden" name="customer_id" value="<?php echo $c['id']; ?>">
                                                        <input type="hidden" name="days" value="30">
                                                        <button type="submit" class="dropdown-item"><i class="fas fa-calendar-plus text-success me-2"></i> +30 <?php echo $lang === 'ar' ? 'يوم' : 'Days'; ?></button>
                                                    </form>
                                                </li>
                                                <li>
                                                    <form method="POST" class="d-inline">
                                                        <?php echo admin_csrf_field(); ?>
                                                        <input type="hidden" name="action" value="extend">
                                                        <input type="hidden" name="customer_id" value="<?php echo $c['id']; ?>">
                                                        <input type="hidden" name="days" value="365">
                                                        <button type="submit" class="dropdown-item"><i class="fas fa-star text-warning me-2"></i> +1 <?php echo $lang === 'ar' ? 'سنة' : 'Year'; ?></button>
                                                    </form>
                                                </li>
                                                <li><hr class="dropdown-divider"></li>
                                                <li>
                                                    <button type="button" class="dropdown-item" onclick="copyM3u('<?php echo htmlspecialchars($xtreamCfg['server_url']); ?>', '<?php echo htmlspecialchars($c['username']); ?>', '<?php echo htmlspecialchars($c['password']); ?>')">
                                                        <i class="fas fa-link text-info me-2"></i> <?php echo $lang === 'ar' ? 'نسخ رابط M3U' : 'Copy M3U Link'; ?>
                                                    </button>
                                                </li>
                                                <li>
                                                    <form method="POST" class="d-inline">
                                                        <?php echo admin_csrf_field(); ?>
                                                        <input type="hidden" name="action" value="toggle">
                                                        <input type="hidden" name="customer_id" value="<?php echo $c['id']; ?>">
                                                        <button type="submit" class="dropdown-item">
                                                            <i class="fas <?php echo $c['status'] === 'active' ? 'fa-ban text-warning' : 'fa-check text-success'; ?> me-2"></i>
                                                            <?php echo $c['status'] === 'active' ? ($lang === 'ar' ? 'تعطيل الحساب' : 'Disable') : ($lang === 'ar' ? 'تفعيل الحساب' : 'Enable'); ?>
                                                        </button>
                                                    </form>
                                                </li>
                                                <li><hr class="dropdown-divider"></li>
                                                <li>
                                                    <form method="POST" class="d-inline" onsubmit="return confirm('<?php echo $lang === 'ar' ? 'هل أنت متأكد من حذف هذا المشترك؟' : 'Are you sure you want to delete this customer?'; ?>');">
                                                        <?php echo admin_csrf_field(); ?>
                                                        <input type="hidden" name="action" value="delete">
                                                        <input type="hidden" name="customer_id" value="<?php echo $c['id']; ?>">
                                                        <button type="submit" class="dropdown-item text-danger"><i class="fas fa-trash-can me-2"></i> <?php echo $lang === 'ar' ? 'حذف' : 'Delete'; ?></button>
                                                    </form>
                                                </li>
                                            </ul>
                                        </div>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Modal: Add New Customer -->
    <div class="modal fade" id="addCustomerModal" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
                <form method="POST">
                    <?php echo admin_csrf_field(); ?>
                    <input type="hidden" name="action" value="add">
                    <div class="modal-header">
                        <h5 class="modal-title fw-bold d-flex align-items-center gap-2">
                            <i class="fas fa-user-plus text-primary"></i>
                            <span><?php echo $lang === 'ar' ? 'إضافة مشترك جديد إلى السيرفر' : 'Add New Customer to Server'; ?></span>
                        </h5>
                        <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
                    </div>
                    <div class="modal-body p-4">
                        <div class="mb-3">
                            <label class="form-label fw-bold"><?php echo $lang === 'ar' ? 'اسم المستخدم (Username)' : 'Username'; ?> *</label>
                            <div class="input-group">
                                <input type="text" name="username" id="newUsername" class="form-control" required placeholder="user_xxxx">
                                <button type="button" class="btn btn-outline-secondary" onclick="generateRandomUser()"><i class="fas fa-dice"></i></button>
                            </div>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-bold"><?php echo $lang === 'ar' ? 'كلمة المرور (Password)' : 'Password'; ?> *</label>
                            <div class="input-group">
                                <input type="text" name="password" id="newPassword" class="form-control" required placeholder="pass_xxxx">
                                <button type="button" class="btn btn-outline-secondary" onclick="generateRandomPass()"><i class="fas fa-dice"></i></button>
                            </div>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-bold"><?php echo $lang === 'ar' ? 'اسم العميل / ملاحظة' : 'Customer Name / Note'; ?></label>
                            <input type="text" name="customer_name" class="form-control" placeholder="<?php echo $lang === 'ar' ? 'مثال: أحمد محمد' : 'e.g. John Doe'; ?>">
                        </div>
                        <div class="row g-2 mb-3">
                            <div class="col-md-6">
                                <label class="form-label fw-bold"><?php echo $lang === 'ar' ? 'المدة' : 'Duration'; ?></label>
                                <select name="duration" id="durationSelect" class="form-select" onchange="toggleCustomDate(this.value)">
                                    <option value="1m">1 <?php echo $lang === 'ar' ? 'شهر (30 يوم)' : 'Month (30 days)'; ?></option>
                                    <option value="3m">3 <?php echo $lang === 'ar' ? 'أشهر (90 يوم)' : 'Months (90 days)'; ?></option>
                                    <option value="6m">6 <?php echo $lang === 'ar' ? 'أشهر (180 يوم)' : 'Months (180 days)'; ?></option>
                                    <option value="1y" selected>1 <?php echo $lang === 'ar' ? 'سنة (365 يوم)' : 'Year (365 days)'; ?></option>
                                    <option value="2y">2 <?php echo $lang === 'ar' ? 'سنتين' : 'Years'; ?></option>
                                    <option value="custom"><?php echo $lang === 'ar' ? 'تاريخ محدد...' : 'Custom Date...'; ?></option>
                                </select>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label fw-bold"><?php echo $lang === 'ar' ? 'عدد الشاشات' : 'Max Connections'; ?></label>
                                <input type="number" name="max_connections" class="form-control" value="1" min="1" max="10">
                            </div>
                        </div>
                        <div class="mb-3" id="customDateWrap" style="display:none;">
                            <label class="form-label fw-bold"><?php echo $lang === 'ar' ? 'تاريخ الانتهاء المخصص' : 'Custom Expiry Date'; ?></label>
                            <input type="datetime-local" name="custom_expiry" class="form-control">
                        </div>
                        <div class="p-3 rounded-3" style="background:rgba(0,123,255,0.08); border:1px solid rgba(0,123,255,0.2);">
                            <div class="d-flex align-items-center gap-2">
                                <i class="fas fa-cloud-arrow-up text-primary"></i>
                                <span class="small fw-semibold"><?php echo $lang === 'ar' ? 'المزامنة التلقائية مفعلة مع سيرفر IPTV' : 'Automatic sync enabled with IPTV server'; ?></span>
                            </div>
                            <div class="small text-muted mt-1"><?php echo htmlspecialchars($xtreamCfg['server_url']); ?></div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary rounded-pill" data-bs-dismiss="modal"><?php echo $lang === 'ar' ? 'إلغاء' : 'Cancel'; ?></button>
                        <button type="submit" class="btn btn-neon rounded-pill"><?php echo $lang === 'ar' ? 'حفظ وتفعيل المشترك' : 'Save & Provision Customer'; ?></button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function togglePassPeek(id) {
            var el = document.getElementById('pass-' + id);
            if (!el) return;
            if (el.innerText === '••••••••') {
                el.innerText = el.getAttribute('data-pass');
            } else {
                el.innerText = '••••••••';
            }
        }
        function generateRandomUser() {
            var rand = Math.floor(100000 + Math.random() * 900000);
            document.getElementById('newUsername').value = 'sky_' + rand;
        }
        function generateRandomPass() {
            var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
            var res = '';
            for (var i = 0; i < 8; i++) res += chars.charAt(Math.floor(Math.random() * chars.length));
            document.getElementById('newPassword').value = res;
        }
        function toggleCustomDate(val) {
            document.getElementById('customDateWrap').style.display = (val === 'custom') ? 'block' : 'none';
        }
        function copyM3u(server, user, pass) {
            var link = server + '/get.php?username=' + encodeURIComponent(user) + '&password=' + encodeURIComponent(pass) + '&type=m3u_plus&output=ts';
            navigator.clipboard.writeText(link).then(function() {
                alert('<?php echo $lang === 'ar' ? 'تم نسخ رابط M3U بنجاح!' : 'M3U link copied to clipboard!'; ?>');
            });
        }

        function retrySync(id) {
            var btn = document.getElementById('sync-btn-' + id);
            var badge = document.getElementById('sync-badge-' + id);
            var origHtml = btn ? btn.innerHTML : '';
            if (btn) {
                btn.disabled = true;
                btn.innerHTML = '<span class="spinner-border spinner-border-sm" style="width:0.75rem;height:0.75rem;" role="status"></span>';
            }
            fetch('api/sync_customer.php', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ customer_id: id })
            })
            .then(function(r) { return r.json(); })
            .then(function(res) {
                if (btn) {
                    btn.disabled = false;
                    btn.innerHTML = origHtml;
                }
                if (res.synced) {
                    if (badge) {
                        badge.className = 'badge bg-success-subtle text-success border border-success-subtle';
                        badge.innerHTML = '<i class="fas fa-check-circle me-1"></i> <?php echo $lang === 'ar' ? "متزامن" : "Synced"; ?>';
                        badge.title = res.message || 'Synced successfully';
                    }
                    if (btn) btn.style.display = 'none';
                    alert('<?php echo $lang === 'ar' ? "تمت المزامنة بنجاح مع سيرفر البث!" : "Successfully synced to IPTV streaming server!"; ?>');
                } else {
                    if (badge) {
                        badge.title = res.message || 'Sync failed';
                    }
                    alert((res.message || 'Sync failed') + (res.http_code ? ' (HTTP ' + res.http_code + ')' : ''));
                }
            })
            .catch(function(err) {
                if (btn) {
                    btn.disabled = false;
                    btn.innerHTML = origHtml;
                }
                alert('Network error: ' + err.message);
            });
        }

        // Live probe server connection
        fetch('api/test_xtream_connection.php')
            .then(function(r){ return r.json(); })
            .then(function(data){
                var badge = document.getElementById('serverStatusBadge');
                if (!badge) return;
                if (data.success) {
                    badge.className = 'badge bg-success';
                    badge.innerHTML = '<i class="fas fa-check"></i> <?php echo $lang === 'ar' ? 'متصل' : 'Online'; ?> (' + data.latency_ms + 'ms)';
                } else {
                    badge.className = 'badge bg-warning text-dark';
                    badge.innerHTML = '<i class="fas fa-triangle-exclamation"></i> ' + (data.http_code ? 'HTTP ' + data.http_code : '<?php echo $lang === 'ar' ? 'غير متصل' : 'Offline'; ?>');
                }
            })
            .catch(function(){
                var badge = document.getElementById('serverStatusBadge');
                if (badge) {
                    badge.className = 'badge bg-danger';
                    badge.innerText = 'Error';
                }
            });
    </script>
</body>
</html>
