<?php
/**
 * ترقيم صفحات موحد للوحة التحكم (12 صفاً افتراضياً).
 */

if (!function_exists('admin_pagination_per_page')) {
    function admin_pagination_per_page(): int
    {
        return 12;
    }
}

/**
 * @param list<mixed> $items
 * @return array{items: list<mixed>, page: int, pages: int, total: int, per_page: int, offset: int}
 */
function admin_paginate_items(array $items, ?int $page = null, ?int $perPage = null): array
{
    $perPage = $perPage !== null && $perPage > 0 ? $perPage : admin_pagination_per_page();
    $total = count($items);
    $pages = max(1, (int)ceil($total / $perPage));
    if ($page === null) {
        $page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
    }
    if ($page < 1) {
        $page = 1;
    }
    if ($page > $pages) {
        $page = $pages;
    }
    $offset = ($page - 1) * $perPage;
    return [
        'items' => array_slice($items, $offset, $perPage),
        'page' => $page,
        'pages' => $pages,
        'total' => $total,
        'per_page' => $perPage,
        'offset' => $offset,
    ];
}

/**
 * أرقام الصفحات المعروضة مع حذف الوسط عند الحاجة: 1 2 3 … 64
 *
 * @return list<int|string> أعداد أو '…'
 */
function admin_pagination_page_window(int $current, int $totalPages, int $edge = 2, int $around = 1): array
{
    if ($totalPages <= 1) {
        return [1];
    }
    $keep = [];
    for ($i = 1; $i <= $totalPages; $i++) {
        if (
            $i <= $edge
            || $i > $totalPages - $edge
            || abs($i - $current) <= $around
        ) {
            $keep[$i] = true;
        }
    }
    $out = [];
    $prev = 0;
    foreach (array_keys($keep) as $i) {
        if ($prev && $i - $prev > 1) {
            $out[] = '…';
        }
        $out[] = $i;
        $prev = $i;
    }
    return $out;
}

/**
 * رقم الصفحة من الطلب (GET ثم POST). 0 إن لم يُرسل.
 */
function admin_request_list_page(): int
{
    $page = 0;
    if (isset($_GET['page'])) {
        $page = (int) $_GET['page'];
    } elseif (isset($_POST['page'])) {
        $page = (int) $_POST['page'];
    }
    return $page > 0 ? $page : 0;
}

/**
 * رابط الرئيسية مع الإبقاء على صفحة الأجهزة إن وُجدت.
 */
function admin_devices_home_url(?int $page = null): string
{
    if ($page === null) {
        $page = admin_request_list_page();
    }
    if ($page > 1) {
        return 'index.php?page=' . $page;
    }
    return 'index.php';
}

/**
 * بناء رابط مع الحفاظ على بقية معاملات GET.
 */
function admin_pagination_url(int $page, array $preserveQuery = []): string
{
    $q = $preserveQuery;
    if ($q === []) {
        $q = $_GET;
    }
    if ($page <= 1) {
        unset($q['page']);
    } else {
        $q['page'] = $page;
    }
    $path = strtok($_SERVER['REQUEST_URI'] ?? '', '?') ?: '';
    $base = basename($path);
    if ($base === '' || $base === '/' || $base === '\\') {
        $base = basename((string)($_SERVER['PHP_SELF'] ?? 'index.php'));
    }
    $qs = http_build_query($q);
    return $qs === '' ? $base : ($base . '?' . $qs);
}

/**
 * HTML شريط الترقيم (يُخفى إن كانت صفحة واحدة فقط).
 */
function admin_render_pagination(int $page, int $pages, array $opts = []): string
{
    if ($pages <= 1) {
        return '';
    }
    $preserve = $opts['query'] ?? [];
    $id = isset($opts['id']) ? (string)$opts['id'] : '';
    $class = isset($opts['class']) ? (string)$opts['class'] : '';
    $isRtl = !empty($GLOBALS['isRtl']);
    $window = admin_pagination_page_window($page, $pages);

    $prevPage = max(1, $page - 1);
    $nextPage = min($pages, $page + 1);
    // في RTL: « للأمام (صفحة أعلى)، » للخلف — كما في لوحات عربية شائعة
    $prevLabel = $isRtl ? '»' : '«';
    $nextLabel = $isRtl ? '«' : '»';

    $html = '<nav class="admin-pager' . ($class !== '' ? ' ' . htmlspecialchars($class) : '') . '"'
        . ($id !== '' ? ' id="' . htmlspecialchars($id) . '"' : '')
        . ' aria-label="Pagination">';
    $html .= '<div class="admin-pager__inner">';

    $prevDisabled = $page <= 1;
    if ($prevDisabled) {
        $html .= '<span class="admin-pager__btn is-disabled" aria-disabled="true">' . $prevLabel . '</span>';
    } else {
        $html .= '<a class="admin-pager__btn" href="' . htmlspecialchars(admin_pagination_url($prevPage, $preserve)) . '" rel="prev">' . $prevLabel . '</a>';
    }

    foreach ($window as $token) {
        if ($token === '…') {
            $html .= '<span class="admin-pager__btn admin-pager__ellipsis" aria-hidden="true">…</span>';
            continue;
        }
        $n = (int)$token;
        if ($n === $page) {
            $html .= '<span class="admin-pager__btn is-active" aria-current="page">' . $n . '</span>';
        } else {
            $html .= '<a class="admin-pager__btn" href="' . htmlspecialchars(admin_pagination_url($n, $preserve)) . '">' . $n . '</a>';
        }
    }

    $nextDisabled = $page >= $pages;
    if ($nextDisabled) {
        $html .= '<span class="admin-pager__btn is-disabled" aria-disabled="true">' . $nextLabel . '</span>';
    } else {
        $html .= '<a class="admin-pager__btn" href="' . htmlspecialchars(admin_pagination_url($nextPage, $preserve)) . '" rel="next">' . $nextLabel . '</a>';
    }

    $html .= '</div></nav>';
    return $html;
}

/**
 * حاوية فارغة لترقيم JS (الصفحة الرئيسية مع الفلاتر).
 */
function admin_render_pagination_shell(string $id = 'adminTablePager'): string
{
    return '<nav class="admin-pager" id="' . htmlspecialchars($id) . '" aria-label="Pagination" hidden>'
        . '<div class="admin-pager__inner"></div>'
        . '</nav>';
}
