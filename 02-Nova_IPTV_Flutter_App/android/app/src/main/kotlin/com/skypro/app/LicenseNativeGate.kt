package com.skypro.app

import android.util.Base64
import org.json.JSONObject
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.security.spec.X509EncodedKeySpec

/**
 */
internal object LicenseNativeGate {

    
    private val sealedPub = intArrayOf(
        23, 208, 171, 252, 104, 36, 219, 167, 91, 146, 163, 46,
        127, 142, 40, 183, 8, 11, 224, 99, 224, 251, 48, 205,
        240, 112, 34, 1, 195, 44, 242, 254, 207, 180, 148, 212,
        177, 117, 116, 34, 49, 0, 62, 177, 182, 213, 166, 153,
        176, 72, 95, 125, 16, 219, 2, 57, 46, 121, 56, 78,
        93, 142, 83, 19, 8, 23, 93, 16, 94, 107, 6, 187,
        214, 253, 124, 227, 218, 210, 71, 178, 63, 14, 239, 206,
        207, 95, 214, 43, 254, 165, 134, 132, 239, 96, 198, 10,
        58, 112, 210, 195, 52, 152, 217, 148, 148, 44, 10, 228,
        40, 33, 51, 188, 133, 108, 195, 17, 228, 231, 149, 52,
        0, 53, 13, 107, 194, 161, 196, 239, 92, 178, 81, 4,
        162, 46, 216, 239, 202, 41, 195, 206, 142, 62, 169, 103,
        35, 155, 136, 210, 27, 241, 66, 61, 195, 18, 90, 105,
        128, 237, 219, 206, 102, 117, 191, 54, 83, 22, 196, 41,
        56, 88, 244, 171, 68, 205, 38, 178, 17, 152, 205, 252,
        210, 219, 65, 96, 12, 1, 25, 222, 54, 46, 67, 128,
        40, 134, 229, 226, 14, 58, 55, 130, 22, 165, 215, 50,
        58, 243, 252, 162, 30, 22, 133, 223, 199, 221, 86, 11,
        36, 70, 255, 85, 62, 241, 239, 11, 211, 145, 75, 240,
        174, 27, 81, 253, 45, 158, 137, 4, 66, 249, 83, 180,
        86, 68, 243, 224, 172, 239, 149, 7, 185, 237, 140, 75,
        49, 11, 204, 53, 213, 8, 8, 4, 168, 198, 91, 158,
        146, 224, 122, 79, 172, 93, 27, 108, 43, 178, 185, 242,
        162, 203, 219, 54, 42, 27, 243, 192, 11, 13, 17, 47,
        102, 53, 109, 20, 144, 61, 71, 208, 136, 195, 12, 41,
        125, 165, 23, 112, 81, 248, 230, 245, 184, 91, 113, 251,
        221, 49, 243, 102, 197, 142, 128, 128, 80, 22, 236, 171,
        204, 130, 135, 146, 182, 197, 118, 11, 210, 91, 164, 115,
        196, 70, 7, 207, 212, 92, 150, 2, 246, 55, 191, 142,
        14, 176, 239, 1, 203, 192, 90, 32, 68, 33, 73, 223,
        76, 206, 120, 237, 89, 56, 27, 13, 220, 252, 187, 80,
        244, 175, 158, 39, 26, 68, 229, 146, 65, 10, 92, 188,
        93, 227, 249, 143, 19, 7, 91, 231, 11, 82, 51, 110,
        7, 230, 136, 63, 59, 3, 24, 67, 155, 19, 226, 109,
        163, 107, 107, 72, 194, 125, 235, 166, 55, 181, 151, 221,
        17, 5, 93, 225, 83, 248, 214, 11, 118, 247, 78, 25,
        81, 42, 142, 5, 233, 130, 241, 32, 158, 80, 120, 55,
        101, 54, 187, 219, 42, 212, 175,
    )

    private val sealedIss = intArrayOf(22, 44, 191, 163, 185, 240, 198, 181)

    private val sealedAud = intArrayOf(
        0, 255, 4, 40, 227, 240, 49, 238, 145, 145, 142, 4,
        85, 153, 145, 0, 150, 173,
    )

    private val sealedRequestMaterial = intArrayOf(
        54, 93, 109, 154, 206, 237, 58, 146, 16, 46, 152, 189,
        180, 22, 41, 33, 177, 110, 117, 193, 10, 161, 136, 5,
        80, 24, 23, 5, 70, 40, 184, 241, 199, 180,
    )

    @Volatile
    private var cachedPub: RSAPublicKey? = null

    @Volatile
    private var cachedIss: String? = null

    @Volatile
    private var cachedAud: String? = null

    @Volatile
    private var cachedSigSecret: String? = null

    fun confirmTicket(
        ticket: String,
        purchaseCode: String,
        envatoUsername: String,
        packageName: String,
        baseUrl: String,
    ): Boolean {
        return try {
            val parts = ticket.trim().split('.')
            if (parts.size != 3) return false

            val headerJson = String(b64UrlDecode(parts[0]), Charsets.UTF_8)
            val header = JSONObject(headerJson)
            if (header.optString("alg") != "RS256") return false

            val signingInput = "${parts[0]}.${parts[1]}".toByteArray(Charsets.UTF_8)
            val signatureBytes = b64UrlDecode(parts[2])
            val verifier = Signature.getInstance("SHA256withRSA")
            verifier.initVerify(publicKey())
            verifier.update(signingInput)
            if (!verifier.verify(signatureBytes)) return false

            val payload = JSONObject(String(b64UrlDecode(parts[1]), Charsets.UTF_8))
            if (!extraClaimsOk(payload)) return false

            val st = payload.optString("st", "").lowercase()
            if (st != "active") return false

            val pc = payload.optString("pc", "")
            val eu = payload.optString("eu", "")
            val pkg = payload.optString("pkg", "")

            val bu = payload.optString("bu", "").lowercase()

            if (pc != purchaseCode) return false
            if (eu.lowercase() != envatoUsername.lowercase()) return false
            if (pkg != packageName) return false

            val expectedBu = baseUrl.trim().lowercase()
            if (bu.isNotEmpty() &&
                bu != "pending-auto" &&
                expectedBu.isNotEmpty() &&
                bu != expectedBu
            ) {
                return false
            }

            val expSeconds = when (val exp = payload.opt("exp")) {
                is Number -> exp.toLong()
                is String -> exp.toLongOrNull() ?: 0L
                else -> 0L
            }
            if (expSeconds <= 0L) return false
            val now = System.currentTimeMillis() / 1000L
            if (now >= expSeconds) return false

            true
        } catch (_: Exception) {
            false
        }
    }

    fun signRequest(
        purchaseCode: String,
        envatoUsername: String,
        baseUrl: String,
        timestampSeconds: Long,
    ): String {
        val secret = sigSecret()
        val input = "$purchaseCode|$envatoUsername|$baseUrl|$timestampSeconds|$secret"
        return sha256Hex(input.toByteArray(Charsets.UTF_8))
    }

    private fun extraClaimsOk(map: JSONObject): Boolean {
        val hasIss = map.has("iss") && !map.isNull("iss")
        val hasAud = map.has("aud") && !map.isNull("aud")
        val hasV = map.has("v") && !map.isNull("v")
        if (!hasIss && !hasAud && !hasV) {
            return true // legacy ticket
        }
        if (map.optString("iss") != expectedIss()) return false
        if (map.optString("aud") != expectedAud()) return false
        if (hasV) {
            val v = map.opt("v")
            val ok = when (v) {
                is Number -> v.toInt() == 2
                is String -> v == "2"
                else -> false
            }
            if (!ok) return false
        }
        val jti = map.optString("jti", "")
        return jti.isNotEmpty()
    }

    private fun publicKey(): RSAPublicKey {
        cachedPub?.let { return it }
        val pem = String(unseal(sealedPub), Charsets.UTF_8)
        val body = pem
            .replace("-----BEGIN PUBLIC KEY-----", "")
            .replace("-----END PUBLIC KEY-----", "")
            .replace("\\s".toRegex(), "")
        val der = Base64.decode(body, Base64.DEFAULT)
        val key = KeyFactory.getInstance("RSA")
            .generatePublic(X509EncodedKeySpec(der)) as RSAPublicKey
        cachedPub = key
        return key
    }

    private fun expectedIss(): String {
        cachedIss?.let { return it }
        val v = String(unseal(sealedIss), Charsets.UTF_8)
        cachedIss = v
        return v
    }

    private fun expectedAud(): String {
        cachedAud?.let { return it }
        val v = String(unseal(sealedAud), Charsets.UTF_8)
        cachedAud = v
        return v
    }

    private fun sigSecret(): String {
        cachedSigSecret?.let { return it }
        val v = String(unseal(sealedRequestMaterial), Charsets.UTF_8)
        cachedSigSecret = v
        return v
    }

    private fun seedBytes(): ByteArray {
        // n0v@-SLC-2026#guard
        return byteArrayOf(
            0x6e, 0x30, 0x76, 0x40,
            0x2d, 0x53, 0x4c, 0x43,
            0x2d, 0x32, 0x30, 0x32, 0x36,
            0x23, 0x67, 0x75, 0x61, 0x72, 0x64,
        )
    }

    private fun unseal(sealed: IntArray): ByteArray {
        val seed = MessageDigest.getInstance("SHA-256").digest(seedBytes())
        val out = ByteArray(sealed.size)
        for (i in sealed.indices) {
            out[i] = sealed[sealed.size - 1 - i].toByte()
        }
        for (i in out.indices) {
            var x = out[i].toInt() and 0xff
            x = ((x ushr 3) or (x shl 5)) and 0xff
            x = x xor (seed[i % 32].toInt() and 0xff) xor ((i * 0x9e + 0x5a) and 0xff)
            out[i] = x.toByte()
        }
        return out
    }

    private fun b64UrlDecode(input: String): ByteArray {
        var t = input.replace('-', '+').replace('_', '/')
        when (t.length % 4) {
            2 -> t += "=="
            3 -> t += "="
        }
        return Base64.decode(t, Base64.DEFAULT)
    }

    private fun sha256Hex(data: ByteArray): String {
        val dig = MessageDigest.getInstance("SHA-256").digest(data)
        return dig.joinToString("") { b ->
            val v = b.toInt() and 0xff
            if (v < 16) "0${v.toString(16)}" else v.toString(16)
        }
    }
}
