<?php
// Public playlist management and Device ID activation are disabled for SkyPro.
// SkyPro purely uses the Username and Password login system.
header('Location: /login.php');
exit;
