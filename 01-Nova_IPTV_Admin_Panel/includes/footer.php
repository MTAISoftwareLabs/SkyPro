<footer class="admin-footer text-center mt-4">
    <div class="container">
        <?php echo $translations[$lang]['site.dev']; ?>
        <a href="https://khamsat.com/user/%D9%85%D9%87%D8%AF%D9%8A-%D8%A7%D9%84%D9%85%D9%86%D9%88%D8%B1" target="_blank" rel="noopener noreferrer">
            <?php echo $translations[$lang]['site.developer']; ?>
        </a>
    </div>
</footer>
<?php
if (function_exists('adminIsLoggedIn') && adminIsLoggedIn()) {
    require_once __DIR__ . '/admin_denied_modal.php';
}
?>
