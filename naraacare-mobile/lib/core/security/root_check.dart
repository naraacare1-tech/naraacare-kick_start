import 'package:flutter/services.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';

/// Rooted / jailbroken device detection (doc 07 SEC-5.4, OQ-49): the app only
/// WARNS (a banner); it keeps working. Server-side attestation is optional in
/// Session 16.
abstract interface class RootCheck {
  Future<bool> isCompromised();
}

class PlatformRootCheck implements RootCheck {
  const new();

  @override
  Future<bool> isCompromised() async {
    try {
      return await FlutterJailbreakDetection.jailbroken;
    } on PlatformException {
      return false; // unknown: no banner rather than a false alarm
    } on MissingPluginException {
      return false; // tests, desktop
    }
  }
}
