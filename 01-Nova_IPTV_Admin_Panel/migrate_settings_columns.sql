-- Run once in phpMyAdmin (ignore "Duplicate column" errors).
ALTER TABLE settings ADD COLUMN block_screenshots TINYINT(1) NOT NULL DEFAULT 1;
ALTER TABLE settings ADD COLUMN admob_app_id_android VARCHAR(120) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN admob_app_id_ios VARCHAR(120) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN tv_banner_image_url VARCHAR(1200) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN tv_banner_click_url VARCHAR(1200) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN tv_banner_html_url VARCHAR(1200) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN onesignal_enabled TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE settings ADD COLUMN onesignal_app_id VARCHAR(64) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN onesignal_rest_api_key VARCHAR(256) DEFAULT NULL;

-- Hero (use TEXT — VARCHAR(1200) often fails on shared hosting row-size limits)
ALTER TABLE settings ADD COLUMN hero_promo_enabled TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE settings ADD COLUMN hero_promo_image_url TEXT DEFAULT NULL;
ALTER TABLE settings ADD COLUMN hero_promo_title VARCHAR(255) DEFAULT NULL;
ALTER TABLE settings ADD COLUMN hero_promo_text TEXT DEFAULT NULL;
ALTER TABLE settings ADD COLUMN hero_promo_link_url TEXT DEFAULT NULL;
ALTER TABLE settings ADD COLUMN hero_banner_count INT NOT NULL DEFAULT 5;
ALTER TABLE settings ADD COLUMN hero_content_mode VARCHAR(20) NOT NULL DEFAULT 'auto';

-- If columns already exist as short VARCHAR, widen them:
ALTER TABLE settings MODIFY COLUMN hero_promo_image_url TEXT DEFAULT NULL;
ALTER TABLE settings MODIFY COLUMN hero_promo_link_url TEXT DEFAULT NULL;
ALTER TABLE settings MODIFY COLUMN hero_promo_text TEXT DEFAULT NULL;
