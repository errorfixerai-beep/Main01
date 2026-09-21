import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app strings should not contain duplicate localization keys', () {
    final file = File('lib/l10n/app_strings.dart');
    final content = file.readAsStringSync();
    final matches = RegExp(r"'([A-Za-z0-9_]+)'\s*:\s*\{").allMatches(content);
    final keys = matches.map((match) => match.group(1)!).toList();
    final duplicates = <String>{};
    final seen = <String>{};

    for (final key in keys) {
      if (!seen.add(key)) {
        duplicates.add(key);
      }
    }

    expect(duplicates, isEmpty, reason: 'Duplicate localization keys found: ${duplicates.toList()}');
  });
}
