-- =============================================================================
-- Nova IPTV Player — Complete Admin Panel database (buyer install)
-- Version: 1.4.2 — full schema (all tables + columns used by the panel)
-- =============================================================================
-- How to use:
--   1. Create an empty MySQL database in cPanel / hosting panel.
--   2. phpMyAdmin → select that database → Import → this file.
--   3. Edit 01-Nova_IPTV_Admin_Panel/config/database.php (DB name/user/pass).
--   4. Open the panel URL → complete setup.php (create your super admin).
--
-- Notes:
--   - No default admin user/password (CodeCanyon requirement).
--   - App API Secret + credential encryption keys are created on first run.
--   - Re-importing DROPS existing tables listed below.
--   - MySQL 5.7+ / MariaDB 10.3+, InnoDB, utf8mb4.
-- =============================================================================

SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';
SET time_zone = '+00:00';

-- -----------------------------------------------------------------------------
-- Drop (clean install)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `playlist_code_devices`;
DROP TABLE IF EXISTS `playlist_access_codes`;
DROP TABLE IF EXISTS `device_web_playlists`;
DROP TABLE IF EXISTS `device_login_sessions`;
DROP TABLE IF EXISTS `push_notifications_log`;
DROP TABLE IF EXISTS `client_feedback`;
DROP TABLE IF EXISTS `activity_log`;
DROP TABLE IF EXISTS `api_request_nonces`;
DROP TABLE IF EXISTS `activated_devices`;
DROP TABLE IF EXISTS `admin_role_permissions`;
DROP TABLE IF EXISTS `admin_users`;
DROP TABLE IF EXISTS `settings`;

-- -----------------------------------------------------------------------------
-- Settings (single-row configuration) — COMPLETE columns
-- -----------------------------------------------------------------------------
CREATE TABLE `settings` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `app_name` VARCHAR(255) DEFAULT 'Nova IPTV Player',
  `home_theme` VARCHAR(50) NOT NULL DEFAULT 'original',
  `default_expiry_days` INT NOT NULL DEFAULT 30,
  `max_devices_per_user` INT NOT NULL DEFAULT 1,
  `auto_block_expired` TINYINT(1) NOT NULL DEFAULT 0,
  `device_registration` TINYINT(1) NOT NULL DEFAULT 1,
  `block_vpn_global` TINYINT(1) NOT NULL DEFAULT 0,
  `default_server_url` VARCHAR(500) DEFAULT NULL,
  `login_servers` TEXT DEFAULT NULL,
  `piracy_detection_enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `piracy_packages` TEXT DEFAULT NULL,
  `piracy_message` TEXT DEFAULT NULL,
  `ads_enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `banner_home_only` TINYINT(1) NOT NULL DEFAULT 1,
  `banner_ad_unit_android` VARCHAR(100) DEFAULT NULL,
  `banner_ad_unit_ios` VARCHAR(100) DEFAULT NULL,
  `interstitial_ad_unit_android` VARCHAR(100) DEFAULT NULL,
  `interstitial_ad_unit_ios` VARCHAR(100) DEFAULT NULL,
  `admob_app_id_android` VARCHAR(120) DEFAULT NULL,
  `admob_app_id_ios` VARCHAR(120) DEFAULT NULL,
  `tv_banner_image_url` VARCHAR(1200) DEFAULT NULL,
  `tv_banner_click_url` VARCHAR(1200) DEFAULT NULL,
  `tv_banner_html_url` VARCHAR(1200) DEFAULT NULL,
  `show_add_change_button` TINYINT(1) NOT NULL DEFAULT 1,
  `show_username_login` TINYINT(1) NOT NULL DEFAULT 1,
  `sync_activation_with_server` TINYINT(1) NOT NULL DEFAULT 0,
  `app_version` VARCHAR(50) DEFAULT '1.4.2',
  `support_contact_url` VARCHAR(700) DEFAULT NULL,
  `purchase_url` VARCHAR(1200) DEFAULT NULL,
  `activation_enforced` TINYINT(1) NOT NULL DEFAULT 1,
  `block_screenshots` TINYINT(1) NOT NULL DEFAULT 1,
  `privacy_policy_url` VARCHAR(1200) DEFAULT NULL,
  `privacy_policy_html` MEDIUMTEXT DEFAULT NULL,
  `privacy_policy_mode` VARCHAR(16) NOT NULL DEFAULT 'url',
  `about_us_html` MEDIUMTEXT DEFAULT NULL,
  `app_activation_url` VARCHAR(1200) DEFAULT NULL,
  `tmdb_api_key` VARCHAR(128) DEFAULT NULL,
  `subdl_api_key` VARCHAR(256) DEFAULT NULL,
  `opensubtitles_api_key` VARCHAR(256) DEFAULT NULL,
  `opensubtitles_username` VARCHAR(128) DEFAULT NULL,
  `opensubtitles_password` VARCHAR(256) DEFAULT NULL,
  `app_api_secret` VARCHAR(128) DEFAULT NULL COMMENT 'HMAC secret shared with Flutter kAppApiSecret',
  `credential_enc_key` VARCHAR(128) DEFAULT NULL COMMENT 'AES key for IPTV password encryption at rest',
  `onesignal_enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `onesignal_app_id` VARCHAR(64) DEFAULT NULL,
  `onesignal_rest_api_key` VARCHAR(256) DEFAULT NULL,
  `live_tv_promo_enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `live_tv_promo_image_url` VARCHAR(1200) DEFAULT NULL,
  `live_tv_promo_text` VARCHAR(500) DEFAULT NULL,
  `live_tv_promo_link_url` VARCHAR(1200) DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `settings` (
  `app_name`,
  `home_theme`,
  `default_expiry_days`,
  `max_devices_per_user`,
  `auto_block_expired`,
  `device_registration`,
  `block_vpn_global`,
  `ads_enabled`,
  `banner_home_only`,
  `show_add_change_button`,
  `show_username_login`,
  `sync_activation_with_server`,
  `app_version`,
  `activation_enforced`,
  `block_screenshots`,
  `privacy_policy_mode`,
  `onesignal_enabled`
) VALUES (
  'Nova IPTV Player',
  'original',
  30,
  1,
  0,
  1,
  0,
  1,
  1,
  1,
  1,
  0,
  '1.4.2',
  1,
  1,
  'url',
  0
);

-- -----------------------------------------------------------------------------
-- Activated devices
-- -----------------------------------------------------------------------------
CREATE TABLE `activated_devices` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(255) NOT NULL,
  `activation_date` DATETIME NOT NULL,
  `expiry_date` DATETIME NOT NULL,
  `status` ENUM('active', 'expired', 'blocked', 'deleted') DEFAULT 'active',
  `notes` TEXT DEFAULT NULL,
  `custom_domain` VARCHAR(1024) DEFAULT NULL,
  `account_key` VARCHAR(255) DEFAULT NULL,
  `device_name` VARCHAR(255) DEFAULT NULL,
  `block_vpn` TINYINT(1) NOT NULL DEFAULT 0,
  `ads_enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `last_seen_at` DATETIME DEFAULT NULL,
  `code_server_host` VARCHAR(500) DEFAULT NULL,
  `manual_login_username` VARCHAR(255) DEFAULT NULL,
  `manual_login_password` VARCHAR(1024) DEFAULT NULL COMMENT 'AES-GCM enc:v1:... (not plaintext)',
  `account_display_name` VARCHAR(255) DEFAULT NULL,
  `device_api_token_hash` VARCHAR(64) DEFAULT NULL,
  `web_manage_code` VARCHAR(12) DEFAULT NULL,
  `web_manage_code_updated_at` DATETIME DEFAULT NULL,
  `web_manage_unlocked_at` DATETIME DEFAULT NULL,
  `web_manage_unlocked_fp` VARCHAR(64) DEFAULT NULL,
  `web_manage_code_months` INT NULL DEFAULT NULL,
  `is_trial` TINYINT(1) NOT NULL DEFAULT 0,
  `mac_address` VARCHAR(64) DEFAULT NULL,
  `previous_device_id` VARCHAR(255) DEFAULT NULL,
  `hardware_fingerprint` VARCHAR(64) DEFAULT NULL,
  `watching_type` VARCHAR(16) DEFAULT NULL,
  `watching_title` VARCHAR(255) DEFAULT NULL,
  `watching_stream_id` VARCHAR(64) DEFAULT NULL,
  `watching_extra` VARCHAR(255) DEFAULT NULL,
  `watching_updated_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `device_id` (`device_id`),
  UNIQUE KEY `uq_activated_mac_address` (`mac_address`),
  UNIQUE KEY `uq_activated_hardware_fingerprint` (`hardware_fingerprint`),
  KEY `idx_account_key` (`account_key`),
  KEY `idx_status` (`status`),
  KEY `idx_expiry_date` (`expiry_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Device login sessions (history on Edit Device)
-- -----------------------------------------------------------------------------
CREATE TABLE `device_login_sessions` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(255) NOT NULL,
  `code_server_host` VARCHAR(500) DEFAULT NULL,
  `manual_login_username` VARCHAR(255) DEFAULT NULL,
  `manual_login_password` VARCHAR(1024) DEFAULT NULL,
  `account_key` VARCHAR(255) DEFAULT NULL,
  `account_display_name` VARCHAR(255) DEFAULT NULL,
  `is_current` TINYINT(1) NOT NULL DEFAULT 0,
  `source` VARCHAR(32) NOT NULL DEFAULT 'app',
  `last_login_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_dls_device` (`device_id`),
  KEY `idx_dls_device_current` (`device_id`, `is_current`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Web-managed M3U playlists per device
CREATE TABLE `device_web_playlists` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(255) NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `m3u_url` TEXT NOT NULL,
  `pin_hash` VARCHAR(255) NOT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_device_web_playlists_device` (`device_id`),
  UNIQUE KEY `uniq_device_m3u` (`device_id`, `m3u_url`(191))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Activity log
-- -----------------------------------------------------------------------------
CREATE TABLE `activity_log` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `action` VARCHAR(64) NOT NULL,
  `device_id` VARCHAR(255) DEFAULT NULL,
  `details` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_activity_created` (`created_at`),
  KEY `idx_activity_device` (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- API request nonces (HMAC replay protection)
-- -----------------------------------------------------------------------------
CREATE TABLE `api_request_nonces` (
  `nonce` VARCHAR(64) NOT NULL,
  `created_at` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`nonce`),
  KEY `idx_api_nonce_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Client feedback
-- -----------------------------------------------------------------------------
CREATE TABLE `client_feedback` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(255) DEFAULT NULL,
  `device_name` VARCHAR(255) DEFAULT NULL,
  `device_url` VARCHAR(1000) DEFAULT NULL,
  `note` TEXT NOT NULL,
  `is_read` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_feedback_read` (`is_read`),
  KEY `idx_feedback_device` (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Playlist access codes
-- -----------------------------------------------------------------------------
CREATE TABLE `playlist_access_codes` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `label` VARCHAR(255) NOT NULL,
  `m3u_url` TEXT NOT NULL,
  `code` VARCHAR(6) NOT NULL,
  `max_devices` INT NOT NULL DEFAULT 1,
  `bound_device_id` VARCHAR(255) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_playlist_code_device` (`code`, `bound_device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `playlist_code_devices` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `code_id` INT NOT NULL,
  `device_id` VARCHAR(255) NOT NULL,
  `device_label` VARCHAR(255) DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_playlist_code_device` (`code_id`, `device_id`),
  KEY `idx_pcd_code_id` (`code_id`),
  CONSTRAINT `fk_pcd_playlist_code`
    FOREIGN KEY (`code_id`) REFERENCES `playlist_access_codes` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Push notifications log (OneSignal)
-- -----------------------------------------------------------------------------
CREATE TABLE `push_notifications_log` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `link_url` VARCHAR(1200) DEFAULT NULL,
  `target_type` ENUM('all', 'device') NOT NULL DEFAULT 'all',
  `device_id` VARCHAR(255) DEFAULT NULL,
  `status` ENUM('sent', 'failed', 'scheduled', 'cancelled') NOT NULL DEFAULT 'sent',
  `onesignal_id` VARCHAR(64) DEFAULT NULL,
  `error_message` VARCHAR(500) DEFAULT NULL,
  `admin_user_id` INT DEFAULT NULL,
  `scheduled_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_push_log_created` (`created_at`),
  KEY `idx_push_log_device` (`device_id`),
  KEY `idx_push_log_scheduled` (`scheduled_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Admin users (EMPTY — create first super admin via setup.php)
-- -----------------------------------------------------------------------------
CREATE TABLE `admin_users` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(64) NOT NULL,
  `email` VARCHAR(255) DEFAULT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `role` VARCHAR(32) NOT NULL DEFAULT 'viewer',
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `last_login_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_admin_username` (`username`),
  UNIQUE KEY `uq_admin_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Role permissions (default matrix)
-- -----------------------------------------------------------------------------
CREATE TABLE `admin_role_permissions` (
  `role` VARCHAR(32) NOT NULL,
  `permission_key` VARCHAR(64) NOT NULL,
  PRIMARY KEY (`role`, `permission_key`),
  KEY `idx_role_perm_role` (`role`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `admin_role_permissions` (`role`, `permission_key`) VALUES
('admin', 'profile'),
('admin', 'dashboard'),
('admin', 'devices_view'),
('admin', 'devices_add'),
('admin', 'devices_edit'),
('admin', 'devices_delete'),
('admin', 'settings'),
('admin', 'feedbacks'),
('admin', 'feedbacks_delete'),
('admin', 'manage_activations'),
('admin', 'expiring'),
('admin', 'activity_log_clear'),
('admin', 'notifications_send'),
('moderator', 'profile'),
('moderator', 'dashboard'),
('moderator', 'devices_view'),
('moderator', 'devices_add'),
('moderator', 'devices_edit'),
('moderator', 'feedbacks'),
('moderator', 'feedbacks_delete'),
('moderator', 'expiring'),
('viewer', 'profile'),
('viewer', 'dashboard'),
('viewer', 'devices_view'),
('viewer', 'feedbacks'),
('viewer', 'expiring');

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- Done. Configure config/database.php then open the panel → setup.php
-- =============================================================================
