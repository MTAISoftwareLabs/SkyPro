<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

if (!adminIsLoggedIn()) {
    header('Location: login.php');
    exit;
}

adminRefreshSessionFromDb($conn);

$perm = isset($_GET['perm']) ? preg_replace('/[^a-z_]/', '', (string) $_GET['perm']) : '';
if ($perm === '') {
    $perm = 'dashboard';
}

if (adminCan($perm)) {
    header('Location: index.php');
    exit;
}

$msgKey = 'denied.perm.' . $perm;
$bodyText = t($msgKey);
if ($bodyText === $msgKey) {
    $bodyText = t('denied.perm.generic');
}

$current_page = '';
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo htmlspecialchars(t('denied.page_title')); ?> — <?php echo htmlspecialchars(t('app.title')); ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
    <style>
        body.denied-page {
            font-family: 'Cairo', system-ui, sans-serif;
            min-height: 100vh;
            margin: 0;
            display: flex;
            flex-direction: column;
            background:
                radial-gradient(ellipse 80% 50% at 50% -20%, rgba(99, 102, 241, 0.25) 0%, transparent 55%),
                radial-gradient(ellipse 60% 40% at 100% 100%, rgba(244, 63, 94, 0.12) 0%, transparent 45%),
                linear-gradient(165deg, #0f172a 0%, #1e293b 40%, #0f172a 100%);
            color: #e2e8f0;
        }
        .denied-page .denied-stage {
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem 1rem;
        }
        @keyframes deniedCardIn {
            from { opacity: 0; transform: translateY(28px) scale(0.94); }
            to { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes deniedRing {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
        }
        .denied-card {
            max-width: 460px;
            width: 100%;
            border-radius: 24px;
            padding: 2.25rem 1.75rem 2rem;
            text-align: center;
            background: linear-gradient(155deg, rgba(255,255,255,0.11) 0%, rgba(15,23,42,0.85) 100%);
            border: 1px solid rgba(148, 163, 184, 0.28);
            box-shadow:
                0 24px 60px rgba(0,0,0,0.45),
                inset 0 1px 0 rgba(255,255,255,0.08);
            animation: deniedCardIn 0.65s cubic-bezier(0.22, 1, 0.36, 1) forwards;
            position: relative;
            overflow: hidden;
        }
        .denied-card::before {
            content: '';
            position: absolute;
            inset: -50%;
            background: conic-gradient(from 0deg, transparent, rgba(56, 189, 248, 0.06), transparent, rgba(99, 102, 241, 0.08), transparent);
            animation: deniedRing 14s linear infinite;
            pointer-events: none;
        }
        .denied-card-inner { position: relative; z-index: 1; }
        .denied-icon {
            width: 88px;
            height: 88px;
            margin: 0 auto 1.25rem;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 2.1rem;
            background: linear-gradient(145deg, #f87171, #dc2626);
            color: #fff;
            box-shadow: 0 12px 40px rgba(220, 38, 38, 0.45);
        }
        .denied-title {
            font-weight: 800;
            font-size: 1.35rem;
            color: #f8fafc;
            margin-bottom: 0.75rem;
            letter-spacing: -0.02em;
        }
        .denied-text {
            color: #94a3b8;
            font-size: 0.98rem;
            line-height: 1.7;
            margin-bottom: 1.75rem;
        }
        .denied-actions .btn {
            border-radius: 999px;
            font-weight: 700;
            padding: 0.55rem 1.6rem;
        }
        .denied-actions .btn-home {
            background: linear-gradient(135deg, #38bdf8, #6366f1);
            border: none;
            color: #0f172a;
            box-shadow: 0 10px 32px rgba(56, 189, 248, 0.35);
        }
        .denied-actions .btn-home:hover {
            filter: brightness(1.08);
            color: #0f172a;
        }
    </style>
</head>
<body class="denied-page">
<?php require_once 'includes/header.php'; ?>

<div class="denied-stage">
    <div class="denied-card">
        <div class="denied-card-inner">
            <div class="denied-icon">
                <i class="fas fa-lock" aria-hidden="true"></i>
            </div>
            <h1 class="denied-title"><?php echo htmlspecialchars(t('denied.modal_title')); ?></h1>
            <p class="denied-text mb-0"><?php echo htmlspecialchars($bodyText); ?></p>
            <div class="denied-actions mt-4">
                <a href="index.php" class="btn btn-home"><?php echo htmlspecialchars(t('denied.back_home')); ?></a>
            </div>
        </div>
    </div>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
