import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_user_certificates_android/flutter_user_certificates_android.dart';

class CertificateService {
  static Future<void> init() {
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        return AndroidCertificateService().load();
      }
    }

    return SynchronousFuture(null);
  }
}

class AndroidCertificateService {
  final FlutterUserCertificatesAndroid _userCerts = FlutterUserCertificatesAndroid();

  Future<void> load() async {
    try {
      Map<String, DERCertificate> certs = await _userCerts.getUserCertificates() ?? {};

      for (var c in certs.values) {
        SecurityContext.defaultContext.setTrustedCertificatesBytes(c.toPEM().bytes);
      }
    } on PlatformException catch (e, s) {
      debugPrint("Failed to use local CA certificates on Android");
      debugPrint(e.toString());
      debugPrintStack(stackTrace: s);
    }
  }
}
