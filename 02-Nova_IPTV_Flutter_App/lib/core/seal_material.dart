import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// مواد الختم المشتركة (مفتاح عام + مطالبات) — بدون نصوص واضحة في strings dump.
class SealMaterial {
  SealMaterial._();

  static const List<int> _sealedPub = <int>[
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
  ];

  static const List<int> _sealedIss = <int>[
    22, 44, 191, 163, 185, 240, 198, 181,
  ];

  static const List<int> _sealedAud = <int>[
    0, 255, 4, 40, 227, 240, 49, 238, 145, 145, 142, 4,
    85, 153, 145, 0, 150, 173,
  ];

  static String? _pubCache;
  static String? _issCache;
  static String? _audCache;

  static String publicPem() => _pubCache ??= utf8.decode(_unseal(_sealedPub));

  static String expectedIss() => _issCache ??= utf8.decode(_unseal(_sealedIss));

  static String expectedAud() => _audCache ??= utf8.decode(_unseal(_sealedAud));

  /// مطالبات إضافية: التذاكر القديمة بدونها تُقبل حتى تنتهي؛ الجديدة تُفحص بدقة.
  static bool extraClaimsOk(Map<String, dynamic> map) {
    final iss = map['iss']?.toString();
    final aud = map['aud']?.toString();
    final v = map['v'];
    if (iss == null && aud == null && v == null) {
      return true; // legacy ticket
    }
    if (iss != expectedIss()) return false;
    if (aud != expectedAud()) return false;
    if (v != null && v != 2 && '$v' != '2') return false;
    final jti = map['jti']?.toString() ?? '';
    if (jti.isEmpty) return false;
    return true;
  }

  static String ticketFingerprint(String ticket, String packageName) {
    final dig = sha256.convert(utf8.encode('$ticket|$packageName'));
    return dig.toString().substring(0, 24);
  }

  static List<int> _seedBytes() {
    const p0 = <int>[0x6e, 0x30, 0x76, 0x40];
    const p1 = <int>[0x2d, 0x53, 0x4c, 0x43];
    const p2 = <int>[0x2d, 0x32, 0x30, 0x32, 0x36];
    const p3 = <int>[0x23, 0x67, 0x75, 0x61, 0x72, 0x64];
    return <int>[...p0, ...p1, ...p2, ...p3];
  }

  static Uint8List _unseal(List<int> sealed) {
    final seed = sha256.convert(_seedBytes()).bytes;
    final out = Uint8List.fromList(sealed.reversed.toList());
    for (var i = 0; i < out.length; i++) {
      var x = out[i];
      x = ((x >> 3) | (x << 5)) & 0xff;
      x = x ^ seed[i % 32] ^ ((i * 0x9e + 0x5a) & 0xff);
      out[i] = x;
    }
    return out;
  }
}
