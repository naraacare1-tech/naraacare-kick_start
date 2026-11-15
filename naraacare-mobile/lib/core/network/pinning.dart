import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Certificate pinning (doc 07 SEC-5.2).
///
/// dart:io hands the app only the server's leaf certificate, so the pin is the
/// SHA-256 of the leaf's SubjectPublicKeyInfo (`sha256/<base64>`, the format
/// of `CERT_PINS`). The normal chain and host-name validation still runs
/// first; the pin is an additional check. `CERT_PINS` carries the current key
/// plus at least one backup key (and the next one during rotation, 60-day
/// overlap), so a certificate renewal that keeps or pre-announces its key
/// never locks users out.
abstract final class CertificatePinning {
  /// `sha256/<base64>` of the certificate's SubjectPublicKeyInfo.
  static String spkiPin(Uint8List certificateDer) {
    final spki = subjectPublicKeyInfo(certificateDer);
    return 'sha256/${base64.encode(sha256.convert(spki).bytes)}';
  }

  /// True when [pins] is empty (dev builds only; the config refuses it
  /// elsewhere) or the certificate's key matches one of them.
  static bool isPinned(X509Certificate? certificate, List<String> pins) {
    if (pins.isEmpty) return true;
    if (certificate == null) return false;
    try {
      return pins.contains(spkiPin(certificate.der));
    } on FormatException {
      return false;
    }
  }

  /// The DER bytes of the SubjectPublicKeyInfo inside an X.509 certificate:
  /// Certificate -> tbsCertificate -> (version) serial signature issuer
  /// validity subject subjectPublicKeyInfo.
  static Uint8List subjectPublicKeyInfo(Uint8List der) {
    final certificate = _Der.read(der, 0);
    final tbs = _Der.read(der, certificate.contentStart);
    var offset = tbs.contentStart;
    final first = _Der.read(der, offset);
    if (first.tag == 0xA0) offset = first.end; // explicit [0] version
    for (var i = 0; i < 5; i++) {
      offset = _Der.read(der, offset).end; // serial .. subject
    }
    final spki = _Der.read(der, offset);
    if (spki.tag != 0x30) throw const FormatException('no SPKI sequence');
    return Uint8List.sublistView(der, offset, spki.end);
  }
}

class _Der {
  const new(this.tag, this.contentStart, this.end);

  final int tag;
  final int contentStart;
  final int end;

  // A parser helper, not a constructor: it validates before building.
  // ignore: prefer_constructors_over_static_methods
  static _Der read(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) throw const FormatException('truncated');
    final tag = bytes[offset];
    var length = bytes[offset + 1];
    var header = 2;
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4 || offset + 2 + count > bytes.length) {
        throw const FormatException('bad length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[offset + 2 + i];
      }
      header += count;
    }
    final end = offset + header + length;
    if (end > bytes.length) throw const FormatException('truncated');
    return _Der(tag, offset + header, end);
  }
}
