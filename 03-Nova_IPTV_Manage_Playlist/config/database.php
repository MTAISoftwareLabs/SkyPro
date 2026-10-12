<?php
/**
 * يجب أن تكون نفس بيانات MySQL الخاصة بلوحة التحكم تماماً.
 * إن اختلفت القاعدة → لن يتعرف الموقع على الأجهزة الموجودة في اللوحة.
 *
 * Smart TV: أجهزة التلفزيون في قاعدة لوحة Smart TV (جدول devices)،
 * وليست في activated_devices. املأ $mp_stv_db_* بنفس قيم لوحة smartnova.
 */

$mp_shared_panel_db = dirname(__DIR__) . DIRECTORY_SEPARATOR
    . '..' . DIRECTORY_SEPARATOR
    . 'admin panel' . DIRECTORY_SEPARATOR
    . 'config' . DIRECTORY_SEPARATOR
    . 'database.php';

$mp_panel_candidates = [
    $mp_shared_panel_db,
    dirname(__DIR__) . '/../admin_panel/config/database.php',
    dirname(__DIR__) . '/../admin/config/database.php',
    dirname(__DIR__) . '/../panel/config/database.php',
    dirname(__DIR__) . '/../01-Nova_IPTV_Admin_Panel/config/database.php',
];

$conn = null;
foreach ($mp_panel_candidates as $candidate) {
    if (is_file($candidate)) {
        require_once $candidate;
        break;
    }
}

if (!isset($conn) || !($conn instanceof PDO)) {
    $db_host = 'localhost';
    $db_name = 'YOUR_DB_NAME';
    $db_user = 'YOUR_DB_USER';
    $db_pass = 'YOUR_DB_PASSWORD';

    date_default_timezone_set('Africa/Casablanca');

    try {
        $conn = new PDO(
            "mysql:host=$db_host;dbname=$db_name;charset=utf8mb4",
            $db_user,
            $db_pass
        );
        $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $conn->exec("SET time_zone = '" . date('P') . "'");
    } catch (PDOException $e) {
        http_response_code(500);
        die('Database connection failed. Check manage-playlist/config/database.php (must match admin panel DB).');
    }
}

/**
 * قاعدة لوحة Smart TV (جدول devices).
 * على الاستضافة: ضع هنا نفس host/name/user/pass ديال smartnova admin/config/database.php
 */
$mp_stv_db_host = '';
$mp_stv_db_name = '';
$mp_stv_db_user = '';
$mp_stv_db_pass = '';

$mp_stv_candidates = [
    dirname(__DIR__) . '/../nova_iptv_smart_tv/admin/config/database.php',
    dirname(__DIR__) . '/../smarttv/admin/config/database.php',
    dirname(__DIR__) . '/../smartnova/admin/config/database.php',
    dirname(__DIR__) . '/../nova_smart_tv/admin/config/database.php',
];

$conn_stv = null;

/**
 * قراءة بيانات الاتصال من ملف لوحة دون تنفيذه (حتى لا يكتب فوق $conn أو يعمل die).
 */
function mp_read_db_file_credentials(string $file): ?array
{
    $src = @file_get_contents($file);
    if ($src === false || $src === '') {
        return null;
    }
    $out = ['host' => 'localhost', 'name' => '', 'user' => '', 'pass' => ''];
    foreach (['host' => 'db_host', 'name' => 'db_name', 'user' => 'db_user', 'pass' => 'db_pass'] as $key => $var) {
        if (preg_match('/\$' . $var . '\s*=\s*\'((?:\\\\\'|[^\'])*)\'/', $src, $m)
            || preg_match('/\$' . $var . '\s*=\s*"((?:\\\\"|[^"])*)"/', $src, $m)) {
            $out[$key] = stripcslashes($m[1]);
        }
    }
    if ($out['name'] === '' || $out['user'] === '') {
        return null;
    }
    return $out;
}

foreach ($mp_stv_candidates as $candidate) {
    $creds = mp_read_db_file_credentials($candidate);
    if (!$creds) {
        continue;
    }
    try {
        $conn_stv = new PDO(
            'mysql:host=' . $creds['host'] . ';dbname=' . $creds['name'] . ';charset=utf8mb4',
            $creds['user'],
            $creds['pass']
        );
        $conn_stv->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $conn_stv->exec("SET time_zone = '" . date('P') . "'");
        break;
    } catch (PDOException $e) {
        $conn_stv = null;
    }
}

if (!($conn_stv instanceof PDO) && $mp_stv_db_name !== '' && $mp_stv_db_user !== '') {
    try {
        $conn_stv = new PDO(
            'mysql:host=' . ($mp_stv_db_host !== '' ? $mp_stv_db_host : 'localhost')
                . ';dbname=' . $mp_stv_db_name . ';charset=utf8mb4',
            $mp_stv_db_user,
            $mp_stv_db_pass
        );
        $conn_stv->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $conn_stv->exec("SET time_zone = '" . date('P') . "'");
    } catch (PDOException $e) {
        $conn_stv = null;
    }
}
