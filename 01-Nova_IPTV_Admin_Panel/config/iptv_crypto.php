<?php
/**
 * Intentionally empty - do NOT put AES / IPTV encryption keys in this file.
 *
 * At-rest credential encryption is configured per installation in:
 *   Admin Panel -> Settings -> Credential Encryption Key
 *
 * Key material is stored in the database (settings.credential_enc_key), never
 * committed to source. The panel refuses credential encrypt/decrypt operations
 * until the buyer generates their own key.
 *
 * Implementation: ../includes/credential_crypto.php
 */
