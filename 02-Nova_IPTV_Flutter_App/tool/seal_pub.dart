import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

List<int> _seedBytes() {
  const p0 = <int>[0x6e, 0x30, 0x76, 0x40];
  const p1 = <int>[0x2d, 0x53, 0x4c, 0x43];
  const p2 = <int>[0x2d, 0x32, 0x30, 0x32, 0x36];
  const p3 = <int>[0x23, 0x67, 0x75, 0x61, 0x72, 0x64];
  return <int>[...p0, ...p1, ...p2, ...p3];
}

String formatBody(List<int> bytes) {
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

void main() {
  final pemPath = File(
    r'C:\Users\Me1hdi\Desktop\Nova_mehdi_iptv_codecanyon\panel iptv checker\keys\license_public.pem',
  );
  var pem = pemPath.readAsStringSync().replaceAll('\r\n', '\n').trimRight();
  if (!pem.endsWith('\n')) pem = '$pem\n';

  final pub = scramble(utf8.encode(pem));
  final iss = scramble(utf8.encode('nova.slc'));
  final aud = scramble(utf8.encode('mehdi.iptv.runtime'));

  stdout.writeln('const List<int> _sealedPub = <int>[');
  stdout.writeln(formatBody(pub));
  stdout.writeln('];');
  stdout.writeln('const List<int> _sealedIss = <int>[');
  stdout.writeln(formatBody(iss));
  stdout.writeln('];');
  stdout.writeln('const List<int> _sealedAud = <int>[');
  stdout.writeln(formatBody(aud));
  stdout.writeln('];');
  stdout.writeln('// pub bytes: ${pub.length}');
}
