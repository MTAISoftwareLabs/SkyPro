import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Seller-only helper: seal license endpoint / request material for embedding
/// in [seller_license_service.dart]. Do not ship plaintext URLs in the app.
///
/// Usage:
///   dart run tool/encode_urls.dart --license-url "https://YOUR_HOST/api.php"
///   dart run tool/encode_urls.dart --license-url "..." --sig-secret "..."
Uint8List scramble(List<int> plain) {
  final seed = sha256.convert(_seedBytes()).bytes;
  final out = Uint8List.fromList(plain);
  for (var i = 0; i < out.length; i++) {
    var x = out[i] ^ seed[i % 32] ^ ((i * 0x9e + 0x5a) & 0xff);
    x = ((x << 3) | (x >> 5)) & 0xff;
    out[i] = x;
  }
  return Uint8List.fromList(out.reversed.toList());
}

Uint8List unscramble(List<int> scrambled) {
  final seed = sha256.convert(_seedBytes()).bytes;
  final out = Uint8List.fromList(scrambled.reversed.toList());
  for (var i = 0; i < out.length; i++) {
    var x = out[i];
    x = ((x >> 3) | (x << 5)) & 0xff;
    x = x ^ seed[i % 32] ^ ((i * 0x9e + 0x5a) & 0xff);
    out[i] = x;
  }
  return out;
}

List<int> _seedBytes() {
  const p0 = <int>[0x6e, 0x30, 0x76, 0x40];
  const p1 = <int>[0x2d, 0x53, 0x4c, 0x43];
  const p2 = <int>[0x2d, 0x32, 0x30, 0x32, 0x36];
  const p3 = <int>[0x23, 0x67, 0x75, 0x61, 0x72, 0x64];
  return <int>[...p0, ...p1, ...p2, ...p3];
}

void main(List<String> args) {
  final licenseUrl = _arg(args, '--license-url') ?? _arg(args, '--license');
  if (licenseUrl == null || licenseUrl.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/encode_urls.dart --license-url "<full url to api.php>"',
    );
    exit(64);
  }
  final secret =
      _arg(args, '--sig-secret') ?? 'NOVA_LICENSE_SIG_SECRET_2026_03_31';

  final urlBytes = scramble(utf8.encode(licenseUrl.trim()));
  final secretBytes = scramble(utf8.encode(secret.trim()));

  final decodedUrl = utf8.decode(unscramble(urlBytes));
  final decodedSecret = utf8.decode(unscramble(secretBytes));
  if (decodedUrl != licenseUrl.trim() || decodedSecret != secret.trim()) {
    throw StateError('round-trip failed');
  }

  stdout.writeln('// Paste into seller_license_service.dart');
  stdout.writeln('const List<int> _sealedLicenseEndpoint = <int>[');
  stdout.writeln(_formatBody(urlBytes));
  stdout.writeln('];');
  stdout.writeln('const List<int> _sealedRequestMaterial = <int>[');
  stdout.writeln(_formatBody(secretBytes));
  stdout.writeln('];');
}

String _formatBody(List<int> bytes) {
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    if (i % 12 == 0) buf.write('  ');
    buf.write('${bytes[i]}');
    if (i != bytes.length - 1) buf.write(', ');
    if (i % 12 == 11) buf.write('\n');
  }
  if (bytes.length % 12 != 0) buf.write('\n');
  return buf.toString().trimRight();
}

String? _arg(List<String> args, String flag) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == flag && i + 1 < args.length) return args[i + 1];
  }
  return null;
}
