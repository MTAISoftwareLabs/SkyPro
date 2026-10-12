<?php
session_start();

require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminRedirectIfNeedsSetup($conn);

$demoUsername = 'user';
$demoPassword = 'user123456';
$formUsername = '';
$formPassword = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();

    $username = trim((string) ($_POST['username'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');
    $formUsername = $username;
    $formPassword = '';

    if ($username === '' || $password === '') {
        $error = t('login.error_invalid');
    } else {
        try {
            $stmt = $conn->prepare('SELECT id, username, email, password_hash, role, is_active FROM admin_users WHERE username = ? LIMIT 1');
            $stmt->execute([$username]);
            $user = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($user && (int) $user['is_active'] === 1 && password_verify($password, $user['password_hash'])) {
                $_SESSION['admin_logged_in'] = true;
                $_SESSION['admin_user_id'] = (int) $user['id'];
                $_SESSION['admin_username'] = $user['username'];
                $_SESSION['admin_role'] = $user['role'];
                $_SESSION['admin_email'] = $user['email'] ?? '';
                $upd = $conn->prepare('UPDATE admin_users SET last_login_at = NOW() WHERE id = ?');
                $upd->execute([(int) $user['id']]);
                header('Location: index.php');
                exit();
            }
        } catch (Throwable $e) {
            // تجاهل وإظهار خطأ عام
        }
        $error = t('login.error_invalid');
    }
}

$inactiveNotice = isset($_GET['inactive']) && $_GET['inactive'] === '1';


$demoBoxHtml = static function () use ($demoUsername, $demoPassword): string {
    ob_start();
    ?>
    <div class="demo-card">
      <p class="demo-card__hint"><?php echo htmlspecialchars(t('login.demo_try_hint'), ENT_QUOTES, 'UTF-8'); ?></p>
      <div class="demo-card__row">
        <span><?php echo htmlspecialchars(t('login.username'), ENT_QUOTES, 'UTF-8'); ?></span>
        <strong><?php echo htmlspecialchars($demoUsername, ENT_QUOTES, 'UTF-8'); ?></strong>
      </div>
      <div class="demo-card__row">
        <span><?php echo htmlspecialchars(t('login.password'), ENT_QUOTES, 'UTF-8'); ?></span>
        <strong><?php echo htmlspecialchars($demoPassword, ENT_QUOTES, 'UTF-8'); ?></strong>
      </div>
      <p class="demo-card__note"><?php echo htmlspecialchars(t('login.demo_note'), ENT_QUOTES, 'UTF-8'); ?></p>
    </div>
    <?php
    return (string) ob_get_clean();
};
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang, ENT_QUOTES, 'UTF-8'); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo t('login.title'); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
:root {
  --bg: #020617;
  --card: rgba(15, 23, 42, 0.92);
  --line: rgba(148, 163, 184, 0.28);
  --text: #e5e7eb;
  --muted: #94a3b8;
  --sky: #38bdf8;
  --indigo: #6366f1;
  --radius: 18px;
  --font: "Cairo", system-ui, sans-serif;
}

* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
body {
  font-family: var(--font);
  color: var(--text);
  min-height: 100vh;
  min-height: 100dvh;
  background:
    radial-gradient(circle at top left, #1e3c72 0, #2a5298 18%, transparent 48%),
    radial-gradient(circle at bottom right, rgba(99, 102, 241, 0.28), transparent 42%),
    linear-gradient(180deg, #0b1723 0%, #020617 100%);
}

.lang {
  position: fixed;
  top: 14px;
  inset-inline-end: 14px;
  z-index: 50;
}
.lang__btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  border-radius: 12px;
  border: 1px solid var(--line);
  background: rgba(2, 6, 23, 0.75);
  color: var(--text);
  cursor: pointer;
  font: inherit;
  font-size: 0.85rem;
  font-weight: 700;
  backdrop-filter: blur(10px);
}
.lang__menu {
  position: absolute;
  top: calc(100% + 8px);
  inset-inline-end: 0;
  min-width: 160px;
  border-radius: 12px;
  border: 1px solid var(--line);
  background: rgba(2, 6, 23, 0.96);
  overflow: hidden;
  display: none;
  box-shadow: 0 16px 40px rgba(0,0,0,.45);
}
.lang.open .lang__menu { display: block; }
.lang__opt {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  color: var(--text);
  text-decoration: none;
  font-size: 0.86rem;
}
.lang__opt:hover { background: rgba(56, 189, 248, 0.12); }
.lang__opt.is-active {
  background: linear-gradient(135deg, rgba(56,189,248,.22), rgba(99,102,241,.22));
  font-weight: 800;
}

.page {
  width: min(1080px, calc(100% - 24px));
  margin: 0 auto;
  padding: 72px 0 32px;
  display: grid;
  gap: 16px;
}

.card {
  border-radius: var(--radius);
  border: 1px solid rgba(255,255,255,.08);
  background: radial-gradient(circle at top left, rgba(255,255,255,.1), rgba(10,14,27,.96));
  box-shadow: 0 20px 45px rgba(0,0,0,.45);
  backdrop-filter: blur(16px);
}

.brand {
  padding: 24px 20px;
}
.brand__badge {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--sky);
  font-size: 0.78rem;
  font-weight: 800;
  margin-bottom: 12px;
}
.brand__badge i { text-shadow: 0 0 12px rgba(56,189,248,.7); }
.brand__title {
  margin: 0 0 8px;
  font-size: clamp(1.7rem, 4vw, 2.4rem);
  font-weight: 800;
  line-height: 1.2;
  color: #f8fafc;
}
.brand__text {
  margin: 0;
  color: var(--muted);
  font-size: 0.94rem;
  line-height: 1.55;
}
.brand__chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 16px;
}
.chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid var(--line);
  background: rgba(2,6,23,.45);
  color: #cbd5e1;
  font-size: 0.75rem;
  font-weight: 700;
}
.chip i { color: var(--sky); }
.brand .demo-card { margin-top: 18px; display: none; }

.auth {
  padding: 22px 18px 18px;
}
.auth__title {
  margin: 0 0 4px;
  font-size: 1.28rem;
  font-weight: 800;
  color: #f8fafc;
}
.auth__sub {
  margin: 0 0 16px;
  color: var(--muted);
  font-size: 0.88rem;
  line-height: 1.45;
}


.alert {
  border-radius: 12px;
  padding: 10px 12px;
  margin-bottom: 12px;
  font-size: 0.86rem;
  border: 1px solid transparent;
}
.alert-danger {
  background: rgba(239,68,68,.12);
  border-color: rgba(239,68,68,.35);
  color: #fecaca;
}
.alert-warning {
  background: rgba(245,158,11,.12);
  border-color: rgba(245,158,11,.35);
  color: #fde68a;
}

.field { margin-bottom: 12px; }
.field label {
  display: block;
  margin-bottom: 6px;
  font-size: 0.82rem;
  font-weight: 700;
  color: #cbd5e1;
}
.field input[type="text"],
.field input[type="password"] {
  width: 100%;
  border-radius: 12px;
  border: 1px solid rgba(148,163,184,.45);
  background: rgba(2,6,23,.72);
  color: var(--text);
  padding: 12px 14px;
  font: inherit;
  font-size: 0.95rem;
  outline: none;
}
.field input:focus {
  border-color: rgba(56,189,248,.9);
  box-shadow: 0 0 0 1px rgba(56,189,248,.55);
}
.pass {
  position: relative;
}
.pass input { padding-inline-end: 46px; }
.pass__toggle {
  position: absolute;
  top: 50%;
  inset-inline-end: 10px;
  transform: translateY(-50%);
  border: 0;
  background: transparent;
  color: var(--muted);
  cursor: pointer;
  padding: 6px;
}
.pass__toggle:hover { color: var(--text); }

.remember {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  margin: 2px 0 14px;
  padding: 8px 12px;
  border-radius: 12px;
  border: 1px solid var(--line);
  background: rgba(2,6,23,.45);
  cursor: pointer;
  user-select: none;
  font-size: 0.88rem;
  font-weight: 700;
  color: #cbd5e1;
}
.remember input {
  position: absolute;
  opacity: 0;
  width: 0;
  height: 0;
}
.remember__box {
  width: 20px;
  height: 20px;
  border-radius: 6px;
  border: 1.6px solid rgba(148,163,184,.55);
  background: rgba(2,6,23,.7);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: transparent;
  font-size: 0.7rem;
}
.remember.is-on,
.remember:has(input:checked) {
  border-color: rgba(56,189,248,.65);
  background: linear-gradient(135deg, rgba(56,189,248,.14), rgba(99,102,241,.12));
  color: #f8fafc;
}
.remember.is-on .remember__box,
.remember:has(input:checked) .remember__box {
  border-color: transparent;
  background: linear-gradient(135deg, var(--sky), var(--indigo));
  color: #020617;
}

.btn-login {
  width: 100%;
  border: 0;
  border-radius: 999px;
  padding: 13px 16px;
  font: inherit;
  font-weight: 800;
  font-size: 0.98rem;
  color: #020617;
  cursor: pointer;
  background: linear-gradient(135deg, var(--sky), var(--indigo));
  box-shadow: 0 12px 26px rgba(56,189,248,.18);
}
.btn-login:hover { filter: brightness(1.05); }

.demo-card {
  margin-top: 16px;
  padding: 14px;
  border-radius: 14px;
  border: 1px solid rgba(99,102,241,.28);
  background: rgba(99,102,241,.08);
}
.demo-card__hint {
  margin: 0 0 10px;
  color: #c7d2fe;
  font-size: 0.8rem;
  line-height: 1.45;
}
.demo-card__row {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 6px;
  font-size: 0.86rem;
  color: #e2e8f0;
}
.demo-card__row strong {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  color: #fff;
}
.demo-card__note {
  margin: 10px 0 0;
  text-align: center;
  color: var(--muted);
  font-size: 0.75rem;
  line-height: 1.4;
}
.auth .demo-card { display: block; }

.contact {
  margin-top: 16px;
  padding-top: 14px;
  border-top: 1px solid var(--line);
}
.contact__label {
  margin: 0 0 10px;
  color: var(--muted);
  font-size: 0.78rem;
  font-weight: 700;
}
.contact__grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}
.contact__item {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 72px;
  padding: 10px 6px;
  border-radius: 14px;
  border: 1px solid var(--line);
  background: linear-gradient(145deg, #0f172a, #020617);
  color: var(--text);
  text-decoration: none;
  transition: transform .15s ease, border-color .15s ease;
}
.contact__item:hover {
  transform: translateY(-2px);
  border-color: rgba(56,189,248,.55);
  color: var(--text);
}
.contact__item i {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #fff;
}
.contact__item span {
  font-size: 0.7rem;
  font-weight: 700;
  text-align: center;
  line-height: 1.2;
  color: #cbd5e1;
}
.contact__item--mail i { background: linear-gradient(135deg, #f59e0b, #ef4444); }
.contact__item--tg i { background: linear-gradient(135deg, #38bdf8, #0284c7); }
.contact__item--dc i { background: linear-gradient(135deg, #818cf8, #6366f1); }

@media (min-width: 900px) {
  .page {
    grid-template-columns: 1.05fr 0.95fr;
    align-items: stretch;
    min-height: calc(100vh - 24px);
    padding: 36px 0;
    gap: 20px;
    /* brand دائماً على اليسار */
    direction: ltr;
  }
  [dir="rtl"] .brand,
  [dir="rtl"] .auth {
    direction: rtl;
  }
  .brand {
    padding: 36px 32px;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .brand .demo-card { display: block; }
  .auth {
    padding: 32px 28px 24px;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .auth .demo-card { display: none; }
}

@media (max-width: 420px) {
  .page { width: calc(100% - 16px); padding-top: 64px; }
  .contact__item { min-height: 66px; }
  .contact__item span { font-size: 0.66rem; }
}
</style>
</head>
<body>

<div class="lang" id="langSwitcher">
  <button type="button" class="lang__btn" onclick="toggleLang()">
<i class="fas fa-globe"></i>
    <span><?php echo $lang === 'ar' ? 'العربية' : 'English'; ?></span>
<i class="fas fa-angle-down"></i>
  </button>
  <div class="lang__menu">
    <a class="lang__opt <?php echo $lang === 'ar' ? 'is-active' : ''; ?>" href="<?php echo build_lang_url('ar'); ?>" onclick="saveLang('ar')">
      <span>🇸🇦</span><?php echo t('lang.name_ar'); ?>
    </a>
    <a class="lang__opt <?php echo $lang === 'en' ? 'is-active' : ''; ?>" href="<?php echo build_lang_url('en'); ?>" onclick="saveLang('en')">
      <span>🇬🇧</span><?php echo t('lang.name_en'); ?>
    </a>
</div>
</div>

<main class="page">
  <section class="card brand">
    <div class="brand__badge">
      <i class="fas fa-shield-halved"></i>
      <?php echo t('login.secure_area'); ?>
</div>
    <h1 class="brand__title"><?php echo t('app.title'); ?></h1>
    <p class="brand__text"><?php echo t('app.subtitle'); ?></p>
    <div class="brand__chips">
      <span class="chip"><i class="fas fa-tv"></i> IPTV</span>
      <span class="chip"><i class="fas fa-mobile-screen"></i> Mobile</span>
      <span class="chip"><i class="fas fa-lock"></i> Secure</span>
</div>
    <?php echo $demoBoxHtml(); ?>
  </section>

  <section class="card auth">

    <h2 class="auth__title"><?php echo t('login.title'); ?></h2>
    <p class="auth__sub"><?php echo t('login.subtitle'); ?></p>

<?php if (!empty($inactiveNotice)): ?>
<div class="alert alert-warning"><?php echo t('login.inactive_account'); ?></div>
<?php endif; ?>
    <?php if (isset($error)): ?>
      <div class="alert alert-danger"><?php echo htmlspecialchars($error, ENT_QUOTES, 'UTF-8'); ?></div>
<?php endif; ?>

    <form method="POST" autocomplete="on">
<?php echo admin_csrf_field(); ?>
      <div class="field">
        <label for="usernameInput"><?php echo t('login.username'); ?></label>
        <input id="usernameInput" type="text" name="username" required autocomplete="username"
               value="<?php echo htmlspecialchars($formUsername, ENT_QUOTES, 'UTF-8'); ?>">
</div>
      <div class="field">
        <label for="passwordInput"><?php echo t('login.password'); ?></label>
        <div class="pass">
          <input id="passwordInput" type="password" name="password" required autocomplete="current-password"
                 value="<?php echo htmlspecialchars($formPassword, ENT_QUOTES, 'UTF-8'); ?>">
          <button type="button" class="pass__toggle" id="passwordToggle"
                  aria-label="<?php echo htmlspecialchars(t('login.show_password'), ENT_QUOTES, 'UTF-8'); ?>">
<i class="fas fa-eye" id="passwordToggleIcon"></i>
</button>
</div>
</div>
      <label class="remember" for="rememberMe">
        <input type="checkbox" id="rememberMe">
        <span class="remember__box" aria-hidden="true"><i class="fas fa-check"></i></span>
        <span><?php echo t('login.remember_me'); ?></span>
      </label>
      <button class="btn-login" type="submit"><?php echo t('button.login'); ?></button>
</form>

    <?php echo $demoBoxHtml(); ?>

    <div class="contact">
      <p class="contact__label"><?php echo t('contact.title'); ?></p>
      <div class="contact__grid">
        <a class="contact__item contact__item--mail" href="mailto:mehdilamnaouar18@gmail.com"
           title="<?php echo htmlspecialchars(t('contact.email_hint'), ENT_QUOTES, 'UTF-8'); ?>">
          <i class="fas fa-envelope"></i>
          <span><?php echo t('contact.email_action'); ?></span>
        </a>
        <a class="contact__item contact__item--tg" href="https://t.me/Me1hdi1" target="_blank" rel="noopener noreferrer">
          <i class="fab fa-telegram"></i>
          <span>@Me1hdi1</span>
        </a>
        <a class="contact__item contact__item--dc" href="https://discord.com/users/424037902121435139" target="_blank" rel="noopener noreferrer"
           title="<?php echo htmlspecialchars(t('contact.discord_hint'), ENT_QUOTES, 'UTF-8'); ?>">
          <i class="fab fa-discord"></i>
          <span>@me1hdi</span>
        </a>
</div>
</div>
  </section>
</main>


<script>
function toggleLang() {
  document.getElementById('langSwitcher').classList.toggle('open');
}
document.addEventListener('click', function (e) {
  var menu = document.getElementById('langSwitcher');
  if (!menu.contains(e.target)) menu.classList.remove('open');
});
function saveLang(lang) {
  localStorage.setItem('site_lang', lang);
}

var loginForm = document.querySelector('form[method="POST"]');
var rememberMe = document.getElementById('rememberMe');
var usernameInput = document.getElementById('usernameInput');
var passwordInput = document.getElementById('passwordInput');
var passwordToggle = document.getElementById('passwordToggle');
var passwordToggleIcon = document.getElementById('passwordToggleIcon');
var rememberKey = 'admin_login_remember';
var userKey = 'admin_login_username';
var passKey = 'admin_login_password';

function syncRememberUi() {
  var wrap = rememberMe && rememberMe.closest('.remember');
  if (wrap) wrap.classList.toggle('is-on', !!rememberMe.checked);
}

if (localStorage.getItem(rememberKey) === '1') {
  rememberMe.checked = true;
  usernameInput.value = localStorage.getItem(userKey) || '';
  passwordInput.value = localStorage.getItem(passKey) || '';
}
if (rememberMe) {
  syncRememberUi();
  rememberMe.addEventListener('change', syncRememberUi);
}

if (passwordToggle) {
  passwordToggle.addEventListener('click', function () {
    var hidden = passwordInput.type === 'password';
    passwordInput.type = hidden ? 'text' : 'password';
    passwordToggleIcon.className = hidden ? 'fas fa-eye-slash' : 'fas fa-eye';
    passwordToggle.setAttribute(
      'aria-label',
      hidden
        ? <?php echo json_encode(t('login.hide_password')); ?>
        : <?php echo json_encode(t('login.show_password')); ?>
    );
  });
}

if (loginForm) {
  loginForm.addEventListener('submit', function () {
    if (rememberMe.checked) {
      localStorage.setItem(rememberKey, '1');
      localStorage.setItem(userKey, usernameInput.value || '');
      localStorage.setItem(passKey, passwordInput.value || '');
    } else {
      localStorage.removeItem(rememberKey);
      localStorage.removeItem(userKey);
      localStorage.removeItem(passKey);
    }
  });
}

</script>
</body>
</html>
