// ignore_for_file: avoid_print

import 'package:mehdi_iptv/core/seal_material.dart';

void main() {
  final p = SealMaterial.publicPem();
  print(p.split('\n').first);
  print('iss=${SealMaterial.expectedIss()}');
  print('aud=${SealMaterial.expectedAud()}');
  print('ok=${p.contains('BEGIN PUBLIC KEY') && p.contains('END PUBLIC KEY')}');
}
