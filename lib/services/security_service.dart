import 'dart:io';
import 'package:flutter/foundation.dart';

class SecurityCheckResult {
  final bool isBlocked;
  final List<String> issues;

  const SecurityCheckResult({required this.isBlocked, required this.issues});
}

class SecurityService {
  static Future<SecurityCheckResult> evaluate() async {
    final issues = <String>[];

    if (kDebugMode) {
      issues.add('Debug build is not a production release.');
    }

    if (Platform.isAndroid) {
      final rootIndicators = <String>[
        '/system/bin/su',
        '/system/xbin/su',
        '/sbin/su',
        '/system/app/Superuser.apk',
      ];
      for (final path in rootIndicators) {
        final file = File(path);
        if (file.existsSync()) {
          issues.add('Device appears rooted or modified.');
          break;
        }
      }
    }

    final blocked = issues.isNotEmpty;
    return SecurityCheckResult(isBlocked: blocked, issues: issues);
  }
}
