<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$current_page = 'profile';
$uid = (int) $_SESSION['admin_user_id'];

$stmt = $conn->prepare('SELECT id, username, email, role FROM admin_users WHERE id = ? LIMIT 1');
$stmt->execute([$uid]);
$me = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$me) {
    header('Location: logout.php');
    exit;
}

$msgOk = $msgErr = '';
$isGuestViewOnly = adminIsGuestRole();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    if ($isGuestViewOnly) {
        $msgErr = t('denied.perm.profile_edit');
    } else {
        $action = $_POST['profile_action'] ?? '';

        if ($action === 'username') {
            $cur = (string) ($_POST['current_password_username'] ?? '');
            $newUsername = trim((string) ($_POST['username'] ?? ''));
            $stmt = $conn->prepare('SELECT password_hash, username FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$uid]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row || !password_verify($cur, $row['password_hash'])) {
                $msgErr = t('profile.error_current');
            } elseif (!preg_match('/^[a-zA-Z0-9_]{3,64}$/', $newUsername)) {
                $msgErr = t('profile.error_username');
            } elseif (strcasecmp($newUsername, (string) ($row['username'] ?? '')) === 0) {
                $msgOk = t('profile.success_username');
            } else {
                try {
                    $up = $conn->prepare('UPDATE admin_users SET username = ? WHERE id = ?');
                    $up->execute([$newUsername, $uid]);
                    $_SESSION['admin_username'] = $newUsername;
                    $me['username'] = $newUsername;
                    $msgOk = t('profile.success_username');
                } catch (PDOException $e) {
                    if ((int) $e->getCode() === 23000) {
                        $msgErr = t('profile.error_username_used');
                    } else {
                        $msgErr = t('msg.db_error');
                    }
                }
            }
        }

        if ($action === 'email') {
            $cur = (string) ($_POST['current_password_email'] ?? '');
            $newEmail = trim((string) ($_POST['email'] ?? ''));
            $stmt = $conn->prepare('SELECT password_hash FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$uid]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row || !password_verify($cur, $row['password_hash'])) {
                $msgErr = t('profile.error_current');
            } elseif ($newEmail !== '' && !filter_var($newEmail, FILTER_VALIDATE_EMAIL)) {
                $msgErr = t('profile.error_email');
            } else {
                $emailVal = $newEmail === '' ? null : $newEmail;
                try {
                    $up = $conn->prepare('UPDATE admin_users SET email = ? WHERE id = ?');
                    $up->execute([$emailVal, $uid]);
                    $_SESSION['admin_email'] = $emailVal ?? '';
                    $me['email'] = $emailVal;
                    $msgOk = t('profile.success_email');
                } catch (PDOException $e) {
                    if ((int) $e->getCode() === 23000) {
                        $msgErr = t('profile.error_email_used');
                    } else {
                        $msgErr = t('msg.db_error');
                    }
                }
            }
        }

        if ($action === 'password') {
            $cur = (string) ($_POST['current_password_pw'] ?? '');
            $new = (string) ($_POST['new_password'] ?? '');
            $confirm = (string) ($_POST['confirm_password'] ?? '');
            $stmt = $conn->prepare('SELECT password_hash FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$uid]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row || !password_verify($cur, $row['password_hash'])) {
                $msgErr = t('profile.error_current');
            } elseif (strlen($new) < 8) {
                $msgErr = t('profile.error_short');
            } elseif ($new !== $confirm) {
                $msgErr = t('profile.error_mismatch');
            } else {
                $hash = password_hash($new, PASSWORD_DEFAULT);
                $up = $conn->prepare('UPDATE admin_users SET password_hash = ? WHERE id = ?');
                $up->execute([$hash, $uid]);
                $msgOk = t('profile.success_password');
            }
        }
    }
}

$username = (string) ($me['username'] ?? '');
$emailDisplay = trim((string) ($me['email'] ?? ''));
$roleLabel = adminRoleLabel((string) ($me['role'] ?? ''));
$initial = function_exists('mb_substr')
    ? mb_strtoupper(mb_substr($username !== '' ? $username : 'A', 0, 1))
    : strtoupper(substr($username !== '' ? $username : 'A', 0, 1));
$roleTone = 'viewer';
$roleRaw = (string) ($me['role'] ?? '');
if (adminRoleIsSuperAdmin($roleRaw)) {
    $roleTone = 'super';
} elseif (adminRoleIsAdmin($roleRaw)) {
    $roleTone = 'admin';
} elseif ($roleRaw === 'moderator') {
    $roleTone = 'mod';
}
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo t('profile.title'); ?> — <?php echo t('app.title'); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
body{
  font-family:'Cairo',sans-serif;
  background:#020617;
  color:#e5e7eb;
  min-height:100vh;
  display:flex;
  flex-direction:column;
}
.admin-main{
  flex:1 0 auto;
  padding-bottom:calc(32px + env(safe-area-inset-bottom, 0px));
}
.container.admin-main{
  padding-left:max(12px, env(safe-area-inset-left, 0px));
  padding-right:max(12px, env(safe-area-inset-right, 0px));
}
.profile-shell{
  max-width:880px;
  margin:0 auto;
  width:100%;
}

.profile-hero{
  display:flex;
  align-items:flex-start;
  gap:16px;
  margin-bottom:18px;
}
.profile-hero__avatar{
  width:64px;
  height:64px;
  border-radius:18px;
  flex-shrink:0;
  display:flex;
  align-items:center;
  justify-content:center;
  font-size:1.45rem;
  font-weight:800;
  color:#fff;
  background:linear-gradient(145deg,#0ea5e9,#2563eb 55%,#6366f1);
  box-shadow:0 14px 30px rgba(37,99,235,.35);
  border:1px solid rgba(255,255,255,.12);
}
.profile-hero h1{
  margin:0;
  font-size:clamp(1.2rem, 4vw, 1.45rem);
  font-weight:800;
  color:#f8fafc;
  line-height:1.25;
}
.profile-hero p{
  margin:6px 0 0;
  color:#94a3b8;
  font-size:.9rem;
  line-height:1.55;
  max-width:560px;
}

.profile-identity{
  display:flex;
  align-items:center;
  gap:16px;
  flex-wrap:wrap;
  padding:18px;
  margin-bottom:16px;
  border-radius:20px;
  background:
    radial-gradient(ellipse 80% 120% at 100% 0%, rgba(56,189,248,.14), transparent 50%),
    linear-gradient(160deg,#0f172a 0%,#020617 100%);
  border:1px solid rgba(148,163,184,.22);
  box-shadow:0 18px 40px rgba(0,0,0,.35);
}
.profile-identity__meta{ min-width:0; flex:1; }
.profile-identity__name{
  margin:0;
  font-size:1.15rem;
  font-weight:800;
  color:#f8fafc;
  word-break:break-word;
}
.profile-identity__mail{
  margin:4px 0 0;
  color:#94a3b8;
  font-size:.86rem;
  word-break:break-all;
}
.profile-badges{
  display:flex;
  flex-wrap:wrap;
  gap:8px;
  margin-top:10px;
}
.profile-badge{
  display:inline-flex;
  align-items:center;
  gap:6px;
  padding:6px 12px;
  border-radius:999px;
  font-size:.78rem;
  font-weight:700;
  border:1px solid transparent;
}
.profile-badge--role-super{
  color:#fde68a;
  background:rgba(245,158,11,.12);
  border-color:rgba(245,158,11,.35);
}
.profile-badge--role-admin{
  color:#c4b5fd;
  background:rgba(139,92,246,.14);
  border-color:rgba(139,92,246,.35);
}
.profile-badge--role-mod{
  color:#7dd3fc;
  background:rgba(14,165,233,.12);
  border-color:rgba(14,165,233,.35);
}
.profile-badge--role-viewer{
  color:#cbd5e1;
  background:rgba(148,163,184,.12);
  border-color:rgba(148,163,184,.28);
}
.profile-badge--user{
  color:#86efac;
  background:rgba(34,197,94,.1);
  border-color:rgba(34,197,94,.28);
}

.profile-card{
  border-radius:20px;
  background:linear-gradient(160deg,#0f172a 0%,#020617 100%);
  border:1px solid rgba(148,163,184,.22);
  box-shadow:0 18px 40px rgba(0,0,0,.35);
  overflow:hidden;
  margin-bottom:16px;
}
.profile-card__head{
  display:flex;
  align-items:flex-start;
  gap:14px;
  padding:18px 18px 0;
}
.profile-card__ico{
  width:44px;
  height:44px;
  border-radius:14px;
  display:flex;
  align-items:center;
  justify-content:center;
  flex-shrink:0;
  font-size:1rem;
}
.profile-card__ico--user{
  color:#7dd3fc;
  background:rgba(14,165,233,.12);
  border:1px solid rgba(14,165,233,.28);
}
.profile-card__ico--mail{
  color:#fde68a;
  background:rgba(245,158,11,.14);
  border:1px solid rgba(245,158,11,.28);
}
.profile-card__ico--lock{
  color:#86efac;
  background:rgba(34,197,94,.12);
  border:1px solid rgba(34,197,94,.28);
}
.profile-card__title{
  margin:0;
  font-size:1rem;
  font-weight:800;
  color:#f1f5f9;
}
.profile-card__hint{
  margin:4px 0 0;
  font-size:.8rem;
  color:#94a3b8;
  line-height:1.5;
}
.profile-card__body{ padding:16px 18px 18px; }

.form-label{
  font-size:.82rem;
  font-weight:700;
  color:#cbd5e1;
  margin-bottom:6px;
}
.form-control{
  background:#020617;
  border:1px solid #334155;
  color:#e5e7eb;
  border-radius:12px;
  min-height:46px;
}
.form-control:focus{
  background:#020617;
  color:#fff;
  border-color:#3b82f6;
  box-shadow:0 0 0 3px rgba(59,130,246,.2);
}
.form-control::placeholder{ color:#64748b; }
.field-help{
  display:block;
  margin-top:6px;
  font-size:.72rem;
  color:#64748b;
}

.pw-wrap{ position:relative; }
.pw-wrap .form-control{ padding-inline-end:48px; }
.pw-toggle{
  position:absolute;
  top:50%;
  <?php echo $isRtl ? 'left' : 'right'; ?>:8px;
  transform:translateY(-50%);
  width:34px;
  height:34px;
  border:0;
  border-radius:10px;
  background:rgba(148,163,184,.1);
  color:#94a3b8;
  display:inline-flex;
  align-items:center;
  justify-content:center;
  cursor:pointer;
  transition:background .15s ease, color .15s ease;
}
.pw-toggle:hover{
  background:rgba(56,189,248,.16);
  color:#7dd3fc;
}

.btn-profile{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  gap:8px;
  min-height:46px;
  padding:0 22px;
  border-radius:999px;
  font-weight:800;
  font-size:.9rem;
  border:1px solid transparent;
  transition:transform .18s ease, box-shadow .18s ease, filter .18s ease;
  -webkit-tap-highlight-color:transparent;
}
.btn-profile:hover{ transform:translateY(-1px); }
.btn-profile:active{ transform:translateY(0); }
.btn-profile__ico{
  width:26px;
  height:26px;
  border-radius:999px;
  display:inline-flex;
  align-items:center;
  justify-content:center;
  font-size:.75rem;
  background:rgba(255,255,255,.16);
}
.btn-profile--primary{
  color:#fff !important;
  background:linear-gradient(135deg,#0ea5e9 0%,#2563eb 55%,#4f46e5 100%);
  box-shadow:0 12px 28px rgba(37,99,235,.32);
}
.btn-profile--primary:hover{
  color:#fff !important;
  filter:brightness(1.05);
  box-shadow:0 16px 32px rgba(37,99,235,.4);
}
.btn-profile--secure{
  color:#052e16 !important;
  background:linear-gradient(135deg,#86efac,#22c55e 50%,#16a34a);
  box-shadow:0 12px 28px rgba(34,197,94,.28);
}
.btn-profile--secure:hover{
  color:#052e16 !important;
  filter:brightness(1.04);
}
.profile-actions{
  display:flex;
  justify-content:flex-start;
  margin-top:4px;
}
.alert{
  border-radius:14px;
  border:0;
}
.alert-success{
  background:rgba(34,197,94,.12);
  color:#bbf7d0;
}
.alert-danger{
  background:rgba(239,68,68,.12);
  color:#fecaca;
}

@media (max-width:640px){
  .profile-identity{ padding:14px; }
  .profile-hero__avatar{ width:56px; height:56px; border-radius:16px; }
  .profile-card__head,
  .profile-card__body{ padding-left:14px; padding-right:14px; }
  .btn-profile{ width:100%; }
  .profile-actions{ display:block; }
}
</style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container admin-main mt-4">
  <div class="profile-shell">

    <div class="profile-hero">
      <div class="profile-hero__avatar" aria-hidden="true"><?php echo htmlspecialchars($initial); ?></div>
      <div>
        <h1><?php echo t('profile.title'); ?></h1>
        <p><?php echo t('profile.subtitle'); ?></p>
      </div>
    </div>

    <?php if ($isGuestViewOnly): ?>
      <?php $viewOnlyLangKey = 'denied.perm.profile_edit'; require 'includes/view_only_banner.php'; ?>
      <script>
      if (window.ADMIN_PERMS) window.ADMIN_PERMS.profile = false;
      if (window.ADMIN_DENIED_MESSAGES) window.ADMIN_DENIED_MESSAGES.profile = <?php echo json_encode(t('denied.perm.profile_edit'), JSON_UNESCAPED_UNICODE); ?>;
      </script>
    <?php endif; ?>

    <?php if ($msgOk): ?><div class="alert alert-success"><?php echo htmlspecialchars($msgOk); ?></div><?php endif; ?>
    <?php if ($msgErr): ?><div class="alert alert-danger"><?php echo htmlspecialchars($msgErr); ?></div><?php endif; ?>

    <section class="profile-identity">
      <div class="profile-identity__meta">
        <h2 class="profile-identity__name"><?php echo htmlspecialchars($username); ?></h2>
        <p class="profile-identity__mail">
          <?php echo $emailDisplay !== '' ? htmlspecialchars($emailDisplay) : '—'; ?>
        </p>
        <div class="profile-badges">
          <span class="profile-badge profile-badge--role-<?php echo htmlspecialchars($roleTone); ?>">
            <i class="fas fa-shield-halved"></i>
            <?php echo htmlspecialchars($roleLabel); ?>
          </span>
          <span class="profile-badge profile-badge--user">
            <i class="fas fa-at"></i>
            <?php echo htmlspecialchars($username); ?>
          </span>
        </div>
      </div>
    </section>

    <section class="profile-card">
      <div class="profile-card__head">
        <span class="profile-card__ico profile-card__ico--user"><i class="fas fa-user-pen"></i></span>
        <div>
          <h2 class="profile-card__title"><?php echo t('profile.username_section'); ?></h2>
          <p class="profile-card__hint"><?php echo t('profile.username_help'); ?></p>
        </div>
      </div>
      <div class="profile-card__body">
        <form method="post" data-admin-perm="profile">
          <input type="hidden" name="profile_action" value="username">
          <div class="mb-3">
            <label class="form-label" for="profileUsername"><?php echo t('profile.username'); ?></label>
            <input type="text"
                   id="profileUsername"
                   name="username"
                   class="form-control"
                   value="<?php echo htmlspecialchars($username); ?>"
                   required
                   pattern="[a-zA-Z0-9_]{3,64}"
                   maxlength="64"
                   autocomplete="username"
                   style="font-family:ui-monospace,Menlo,Consolas,monospace;font-weight:700;letter-spacing:.3px;"
                   <?php echo $isGuestViewOnly ? 'readonly' : ''; ?>>
            <span class="field-help"><?php echo t('profile.username_rules'); ?></span>
          </div>
          <div class="mb-3">
            <label class="form-label" for="profileUsernamePw"><?php echo t('profile.current_password'); ?></label>
            <div class="pw-wrap">
              <input type="password"
                     id="profileUsernamePw"
                     name="current_password_username"
                     class="form-control"
                     required
                     autocomplete="current-password"
                     <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
              <button type="button" class="pw-toggle" data-pw-toggle="profileUsernamePw" aria-label="toggle">
                <i class="fas fa-eye"></i>
              </button>
            </div>
            <span class="field-help"><?php echo t('profile.confirm_with_password'); ?></span>
          </div>
          <div class="profile-actions">
            <button type="submit" class="btn-profile btn-profile--primary" <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
              <span class="btn-profile__ico"><i class="fas fa-check"></i></span>
              <span><?php echo t('profile.save_username'); ?></span>
            </button>
          </div>
        </form>
      </div>
    </section>

    <section class="profile-card">
      <div class="profile-card__head">
        <span class="profile-card__ico profile-card__ico--mail"><i class="fas fa-envelope"></i></span>
        <div>
          <h2 class="profile-card__title"><?php echo t('profile.email_section'); ?></h2>
          <p class="profile-card__hint"><?php echo t('profile.email_help'); ?></p>
        </div>
      </div>
      <div class="profile-card__body">
        <form method="post" data-admin-perm="profile">
          <input type="hidden" name="profile_action" value="email">
          <div class="mb-3">
            <label class="form-label" for="profileEmail"><?php echo t('profile.email_label'); ?></label>
            <input type="email"
                   id="profileEmail"
                   name="email"
                   class="form-control"
                   value="<?php echo htmlspecialchars($me['email'] ?? ''); ?>"
                   placeholder="name@example.com"
                   <?php echo $isGuestViewOnly ? 'readonly' : ''; ?>>
          </div>
          <div class="mb-3">
            <label class="form-label" for="profileEmailPw"><?php echo t('profile.current_password'); ?></label>
            <div class="pw-wrap">
              <input type="password"
                     id="profileEmailPw"
                     name="current_password_email"
                     class="form-control"
                     required
                     autocomplete="current-password"
                     <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
              <button type="button" class="pw-toggle" data-pw-toggle="profileEmailPw" aria-label="toggle">
                <i class="fas fa-eye"></i>
              </button>
            </div>
            <span class="field-help"><?php echo t('profile.confirm_with_password'); ?></span>
          </div>
          <div class="profile-actions">
            <button type="submit" class="btn-profile btn-profile--primary" <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
              <span class="btn-profile__ico"><i class="fas fa-check"></i></span>
              <span><?php echo t('profile.save_email'); ?></span>
            </button>
          </div>
        </form>
      </div>
    </section>

    <section class="profile-card">
      <div class="profile-card__head">
        <span class="profile-card__ico profile-card__ico--lock"><i class="fas fa-lock"></i></span>
        <div>
          <h2 class="profile-card__title"><?php echo t('profile.password_section'); ?></h2>
          <p class="profile-card__hint"><?php echo t('profile.password_help'); ?></p>
        </div>
      </div>
      <div class="profile-card__body">
        <form method="post" data-admin-perm="profile">
          <input type="hidden" name="profile_action" value="password">
          <div class="mb-3">
            <label class="form-label" for="profileCurPw"><?php echo t('profile.current_password'); ?></label>
            <div class="pw-wrap">
              <input type="password"
                     id="profileCurPw"
                     name="current_password_pw"
                     class="form-control"
                     required
                     autocomplete="current-password"
                     <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
              <button type="button" class="pw-toggle" data-pw-toggle="profileCurPw" aria-label="toggle">
                <i class="fas fa-eye"></i>
              </button>
            </div>
          </div>
          <div class="row g-3 mb-3">
            <div class="col-md-6">
              <label class="form-label" for="profileNewPw"><?php echo t('profile.new_password'); ?></label>
              <div class="pw-wrap">
                <input type="password"
                       id="profileNewPw"
                       name="new_password"
                       class="form-control"
                       required
                       minlength="8"
                       autocomplete="new-password"
                       <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
                <button type="button" class="pw-toggle" data-pw-toggle="profileNewPw" aria-label="toggle">
                  <i class="fas fa-eye"></i>
                </button>
              </div>
            </div>
            <div class="col-md-6">
              <label class="form-label" for="profileConfirmPw"><?php echo t('profile.confirm_password'); ?></label>
              <div class="pw-wrap">
                <input type="password"
                       id="profileConfirmPw"
                       name="confirm_password"
                       class="form-control"
                       required
                       minlength="8"
                       autocomplete="new-password"
                       <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
                <button type="button" class="pw-toggle" data-pw-toggle="profileConfirmPw" aria-label="toggle">
                  <i class="fas fa-eye"></i>
                </button>
              </div>
            </div>
          </div>
          <div class="profile-actions">
            <button type="submit" class="btn-profile btn-profile--secure" <?php echo $isGuestViewOnly ? 'disabled' : ''; ?>>
              <span class="btn-profile__ico"><i class="fas fa-key"></i></span>
              <span><?php echo t('profile.change_password'); ?></span>
            </button>
          </div>
        </form>
      </div>
    </section>

  </div>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
(function () {
  document.querySelectorAll('[data-pw-toggle]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var id = btn.getAttribute('data-pw-toggle');
      var input = document.getElementById(id);
      if (!input || input.disabled) return;
      var show = input.type === 'password';
      input.type = show ? 'text' : 'password';
      var icon = btn.querySelector('i');
      if (icon) {
        icon.classList.toggle('fa-eye', !show);
        icon.classList.toggle('fa-eye-slash', show);
      }
    });
  });
})();
</script>
</body>
</html>
