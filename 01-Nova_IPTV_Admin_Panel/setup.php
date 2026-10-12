<?php
/**
 * First-run setup: create the initial super administrator.
 * Accessible only when admin_users is empty (no hardcoded default password).
 */
session_start();

require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);

if (!adminNeedsInitialSetup($conn)) {
    header('Location: login.php');
    exit;
}

$error = '';
$formUsername = 'admin';
$formEmail = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    $username = trim((string) ($_POST['username'] ?? ''));
    $email = trim((string) ($_POST['email'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');
    $confirm = (string) ($_POST['password_confirm'] ?? '');
    $formUsername = $username;
    $formEmail = $email;

    if ($username === '' || $password === '') {
        $error = t('setup.error_required');
    } elseif (!preg_match('/^[A-Za-z0-9._-]{3,64}$/', $username)) {
        $error = t('setup.error_username');
    } elseif (strlen($password) < 8) {
        $error = t('setup.error_password_short');
    } elseif ($password !== $confirm) {
        $error = t('setup.error_password_mismatch');
    } elseif ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $error = t('setup.error_email');
    } else {
        try {
            // Re-check under race conditions.
            if (!adminNeedsInitialSetup($conn)) {
                header('Location: login.php');
                exit;
            }
            $hash = password_hash($password, PASSWORD_DEFAULT);
            $ins = $conn->prepare(
                'INSERT INTO admin_users (username, email, password_hash, role, is_active) VALUES (?, ?, ?, ?, 1)'
            );
            $ins->execute([
                $username,
                $email !== '' ? $email : null,
                $hash,
                ADMIN_ROLE_SUPER_ADMIN,
            ]);
            $newId = (int) $conn->lastInsertId();

            $_SESSION['admin_logged_in'] = true;
            $_SESSION['admin_user_id'] = $newId;
            $_SESSION['admin_username'] = $username;
            $_SESSION['admin_role'] = ADMIN_ROLE_SUPER_ADMIN;
            $_SESSION['admin_email'] = $email;

            // توليد مفاتيح الأمان تلقائياً عند أول تثبيت — بدون خطوة يدوية في الإعدادات.
            if (function_exists('adminEnsureSecurityKeysOnFirstSetup')) {
                adminEnsureSecurityKeysOnFirstSetup($conn);
            }

            header('Location: index.php?setup=1');
            exit;
        } catch (Throwable $e) {
            $error = t('setup.error_db');
        }
    }
}
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo $lang; ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo htmlspecialchars(t('setup.title'), ENT_QUOTES, 'UTF-8'); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
<link rel="stylesheet" href="assets/css/admin-responsive.css">
<style>
body{
font-family:'Cairo',sans-serif;
min-height:100vh;
display:flex;
align-items:center;
justify-content:center;
background:
radial-gradient(circle at top left,#1e3a8a 0,#1d4ed8 22%,transparent 55%),
radial-gradient(circle at bottom right,#4c1d95 0,#020617 55%);
color:#e5e7eb;
}
.login-card{
background: radial-gradient(circle at top left, rgba(248,250,252,0.12), rgba(15,23,42,0.98));
border-radius:20px;
box-shadow:0 30px 90px rgba(15,23,42,0.95),0 0 0 1px rgba(148,163,184,0.25);
padding:32px 28px 26px;
width:100%;
max-width:440px;
}
.login-header{text-align:center;margin-bottom:24px;}
.login-header p{font-size:.9rem;color:#9ca3af;}
.form-control{
background:rgba(15,23,42,.95);
border-radius:12px;
border:1px solid rgba(148,163,184,.55);
color:#e5e7eb;
}
.form-control:focus{
box-shadow:0 0 0 1px rgba(56,189,248,.7);
border-color:rgba(56,189,248,.9);
}
.btn-primary{
border-radius:999px;
background:linear-gradient(135deg,#38bdf8,#6366f1);
border:none;
font-weight:500;
}
.lang-switcher{position:absolute;top:25px;inset-inline-end:25px;z-index:1000;}
.lang-current{
display:flex;align-items:center;gap:8px;padding:7px 16px;border-radius:999px;
background:rgba(15,23,42,.65);border:1px solid rgba(255,255,255,.15);color:#e5e7eb;
font-size:.85rem;cursor:pointer;
}
.lang-dropdown{
position:absolute;top:42px;right:0;min-width:160px;background:rgba(2,6,23,.92);
border-radius:14px;border:1px solid rgba(255,255,255,.08);overflow:hidden;
opacity:0;transform:translateY(-8px);pointer-events:none;transition:.18s;
}
.lang-switcher.open .lang-dropdown{opacity:1;transform:translateY(0);pointer-events:auto;}
.lang-option{display:flex;align-items:center;gap:10px;padding:10px 14px;font-size:.85rem;color:#e5e7eb;text-decoration:none;}
.lang-option:hover{background:rgba(148,163,184,.18);}
.lang-option.active{background:linear-gradient(135deg,#38bdf8,#6366f1);color:#020617;font-weight:600;}
.setup-hint{font-size:.82rem;color:#9ca3af;line-height:1.5;margin-top:14px;margin-bottom:0;}
</style>
</head>
<body>
<div class="lang-switcher" id="langSwitcher">
<div class="lang-current" onclick="document.getElementById('langSwitcher').classList.toggle('open')">
<i class="fas fa-globe"></i>
<span><?php echo $lang === 'ar' ? '🇸🇦 العربية' : '🇬🇧 English'; ?></span>
<i class="fas fa-angle-down"></i>
</div>
<div class="lang-dropdown">
<a href="<?php echo build_lang_url('ar'); ?>" class="lang-option <?php echo $lang==='ar'?'active':''; ?>"><?php echo t('lang.name_ar'); ?></a>
<a href="<?php echo build_lang_url('en'); ?>" class="lang-option <?php echo $lang==='en'?'active':''; ?>"><?php echo t('lang.name_en'); ?></a>
</div>
</div>

<div class="container">
<div class="row justify-content-center">
<div class="col-md-6">
<div class="login-card">
<div class="login-header">
<h2><?php echo htmlspecialchars(t('setup.title'), ENT_QUOTES, 'UTF-8'); ?></h2>
<p><?php echo htmlspecialchars(t('setup.subtitle'), ENT_QUOTES, 'UTF-8'); ?></p>
</div>

<?php if ($error !== ''): ?>
<div class="alert alert-danger"><?php echo htmlspecialchars($error, ENT_QUOTES, 'UTF-8'); ?></div>
<?php endif; ?>

<form method="POST" autocomplete="off">
<?php echo admin_csrf_field(); ?>
<div class="mb-3">
<label class="form-label"><?php echo t('setup.username'); ?></label>
<input type="text" name="username" class="form-control" required minlength="3" maxlength="64"
       pattern="[A-Za-z0-9._\-]{3,64}"
       value="<?php echo htmlspecialchars($formUsername, ENT_QUOTES, 'UTF-8'); ?>">
<small class="text-muted"><?php echo t('setup.username_help'); ?></small>
</div>
<div class="mb-3">
<label class="form-label"><?php echo t('setup.email'); ?></label>
<input type="email" name="email" class="form-control"
       value="<?php echo htmlspecialchars($formEmail, ENT_QUOTES, 'UTF-8'); ?>"
       placeholder="<?php echo htmlspecialchars(t('setup.email_optional'), ENT_QUOTES, 'UTF-8'); ?>">
</div>
<div class="mb-3">
<label class="form-label"><?php echo t('setup.password'); ?></label>
<input type="password" name="password" class="form-control" required minlength="8" autocomplete="new-password">
<small class="text-muted"><?php echo t('setup.password_help'); ?></small>
</div>
<div class="mb-3">
<label class="form-label"><?php echo t('setup.password_confirm'); ?></label>
<input type="password" name="password_confirm" class="form-control" required minlength="8" autocomplete="new-password">
</div>
<button type="submit" class="btn btn-primary w-100">
<i class="fas fa-user-shield me-1"></i><?php echo t('setup.submit'); ?>
</button>
</form>
<p class="setup-hint"><?php echo htmlspecialchars(t('setup.hint'), ENT_QUOTES, 'UTF-8'); ?></p>
</div>
</div>
</div>
</div>
<script>
document.addEventListener('click', function(e){
  const menu = document.getElementById('langSwitcher');
  if (menu && !menu.contains(e.target)) menu.classList.remove('open');
});
</script>
</body>
</html>
