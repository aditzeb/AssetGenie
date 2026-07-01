import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mcp_server/mcp_server.dart';

Future<CallToolResult> auditLocalization(Map<String, dynamic> arguments) async {
  final projectPath = arguments['project_path'] as String?;
  if (projectPath == null || projectPath.isEmpty) {
    return CallToolResult(
      [
        TextContent(
            text: 'Error: "project_path" is required and cannot be empty.')
      ],
      isError: true,
    );
  }

  final primaryLocale = arguments['primary_locale'] as String? ?? 'en';
  final unusedKeysCheck = arguments['unused_keys_check'] as bool? ?? true;

  try {
    final projectDir = Directory(projectPath);
    if (!projectDir.existsSync()) {
      return CallToolResult(
        [
          TextContent(
              text:
                  'Error: Project directory does not exist at "$projectPath".')
        ],
        isError: true,
      );
    }

    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return CallToolResult(
        [
          TextContent(
              text:
                  'Error: No "pubspec.yaml" found at "$projectPath". This does not appear to be a Flutter project.')
        ],
        isError: true,
      );
    }

    // 1. Locate all ARB files in lib/
    final arbFiles = <File>[];
    final libDir = Directory(p.join(projectPath, 'lib'));
    if (libDir.existsSync()) {
      try {
        final entities = libDir.listSync(recursive: true);
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.arb')) {
            arbFiles.add(entity);
          }
        }
      } catch (e) {
        // Fallback or skip listing errors
      }
    }

    if (arbFiles.isEmpty) {
      return CallToolResult([
        TextContent(
            text:
                'Warning: No ARB (.arb) localization files found in the project under `lib/`. No localization auditing was performed.')
      ]);
    }

    // 2. Parse ARB files and map to locales
    final localeMap = <String, Map<String, dynamic>>{};
    final fileToLocale = <String, String>{};
    final localeToFile = <String, String>{};

    for (final file in arbFiles) {
      try {
        final content = await file.readAsString();
        if (content.trim().isEmpty) continue;
        final parsed = jsonDecode(content);
        if (parsed is! Map<String, dynamic>) continue;

        String? locale = parsed['@@locale'] as String?;
        if (locale == null || locale.isEmpty) {
          // Parse from filename, e.g., app_en.arb -> en, es.arb -> es
          final filename = p.basenameWithoutExtension(file.path);
          if (filename.startsWith('app_')) {
            locale = filename.substring(4);
          } else if (filename.contains('_')) {
            final parts = filename.split('_');
            locale = parts.last;
          } else {
            locale = filename;
          }
        }

        localeMap[locale] = parsed;
        final relativePath =
            p.relative(file.path, from: projectPath).replaceAll('\\', '/');
        fileToLocale[relativePath] = locale;
        localeToFile[locale] = relativePath;
      } catch (e) {
        // Ignore unparseable files
      }
    }

    if (localeMap.isEmpty) {
      return CallToolResult([
        TextContent(
            text:
                'Warning: None of the ARB files could be parsed as valid JSON objects. No localization auditing was performed.')
      ]);
    }

    // 3. Determine the primary locale
    var primary = primaryLocale;
    if (!localeMap.containsKey(primary)) {
      // Fallback to first locale found
      primary = localeMap.keys.first;
    }

    final primaryData = localeMap[primary]!;
    final primaryKeys =
        primaryData.keys.where((k) => !k.startsWith('@')).toList();

    // 4. Gather missing, extra, and placeholder mismatches per locale
    final missingKeys = <String, List<String>>{};
    final extraKeys = <String, List<String>>{};
    final placeholderMismatches = <String,
        List<Map<String, dynamic>>>{}; // locale -> list of mismatch info

    Set<String> extractPlaceholders(String text) {
      final matches = RegExp(r'\{([a-zA-Z0-9_]+)\}').allMatches(text);
      return matches.map((m) => m.group(1)!).toSet();
    }

    localeMap.forEach((locale, data) {
      if (locale == primary) return;

      final currentKeys = data.keys.where((k) => !k.startsWith('@')).toSet();

      // Find missing keys
      final missing =
          primaryKeys.where((k) => !currentKeys.contains(k)).toList();
      if (missing.isNotEmpty) {
        missingKeys[locale] = missing;
      }

      // Find extra keys
      final extra = currentKeys.where((k) => !primaryKeys.contains(k)).toList();
      if (extra.isNotEmpty) {
        extraKeys[locale] = extra;
      }

      // Check placeholder mismatches
      final mismatches = <Map<String, dynamic>>[];
      for (final key in primaryKeys) {
        if (!currentKeys.contains(key)) continue;

        final primaryVal = primaryData[key];
        final currentVal = data[key];

        if (primaryVal is String && currentVal is String) {
          final pPlaceholders = extractPlaceholders(primaryVal);
          final cPlaceholders = extractPlaceholders(currentVal);

          // If sets are not equal, we have a mismatch
          if (pPlaceholders.length != cPlaceholders.length ||
              !pPlaceholders.containsAll(cPlaceholders)) {
            mismatches.add({
              'key': key,
              'primary_val': primaryVal,
              'primary_placeholders': pPlaceholders.toList(),
              'current_val': currentVal,
              'current_placeholders': cPlaceholders.toList(),
            });
          }
        }
      }

      if (mismatches.isNotEmpty) {
        placeholderMismatches[locale] = mismatches;
      }
    });

    // 5. Scan for unused translation keys in lib/
    final unusedKeys = <String>[];
    if (unusedKeysCheck && libDir.existsSync() && primaryKeys.isNotEmpty) {
      final dartFiles = <File>[];
      try {
        final entities = libDir.listSync(recursive: true);
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.dart')) {
            dartFiles.add(entity);
          }
        }
      } catch (e) {
        // Skip listing errors
      }

      final dartContents = <String>[];
      for (final file in dartFiles) {
        try {
          final text = await file.readAsString();
          dartContents.add(text);
        } catch (e) {
          // Skip unreadable files
        }
      }

      final keyRegexes = {
        for (final key in primaryKeys)
          key: RegExp('\\b${RegExp.escape(key)}\\b')
      };

      for (final key in primaryKeys) {
        final regex = keyRegexes[key]!;
        bool isUsed = false;
        for (final content in dartContents) {
          if (regex.hasMatch(content)) {
            isUsed = true;
            break;
          }
        }
        if (!isUsed) {
          unusedKeys.add(key);
        }
      }
    }

    // 6. Build Report
    final buffer = StringBuffer();
    buffer.writeln('# AssetGenie Localization Audit Report');
    buffer.writeln('Project Path: `$projectPath`');
    buffer.writeln(
        'Primary Locale: `$primary` (file: `${localeToFile[primary]}`)');
    buffer.writeln();

    buffer.writeln('## Summary');
    buffer.writeln('- Locales detected: ${localeMap.keys.join(', ')}');
    buffer.writeln('- Total keys in primary locale: ${primaryKeys.length}');
    buffer.writeln('- Locales with missing keys: ${missingKeys.length}');
    buffer.writeln(
        '- Locales with placeholder mismatches: ${placeholderMismatches.length}');
    if (unusedKeysCheck) {
      buffer.writeln('- Unused translation keys: ${unusedKeys.length}');
    }
    buffer.writeln();

    // Missing keys section
    if (missingKeys.isNotEmpty) {
      buffer.writeln(
          '## ❌ Missing Translations (Keys in primary but missing in target)');
      missingKeys.forEach((locale, keys) {
        buffer
            .writeln('### Locale `$locale` (file: `${localeToFile[locale]}`)');
        for (final key in keys) {
          buffer.writeln('- `$key`');
        }
        buffer.writeln();
      });
    } else {
      buffer.writeln('## ✅ Missing Translations');
      buffer
          .writeln('All locales have all keys defined in the primary locale.');
      buffer.writeln();
    }

    // Extra keys section
    if (extraKeys.isNotEmpty) {
      buffer.writeln(
          '## 📦 Extra Translations (Keys in target but missing in primary)');
      extraKeys.forEach((locale, keys) {
        buffer
            .writeln('### Locale `$locale` (file: `${localeToFile[locale]}`)');
        for (final key in keys) {
          buffer.writeln('- `$key`');
        }
        buffer.writeln();
      });
    }

    // Placeholder mismatches section
    if (placeholderMismatches.isNotEmpty) {
      buffer.writeln(
          '## ⚠️ Placeholder Mismatches (Placeholders must match between translations)');
      placeholderMismatches.forEach((locale, mismatches) {
        buffer
            .writeln('### Locale `$locale` (file: `${localeToFile[locale]}`)');
        for (final item in mismatches) {
          final key = item['key'] as String;
          final pVal = item['primary_val'] as String;
          final pPl = item['primary_placeholders'] as List;
          final cVal = item['current_val'] as String;
          final cPl = item['current_placeholders'] as List;

          buffer.writeln('- Key: `$key`');
          buffer.writeln(
              '  - `$primary`: `"$pVal"` (Placeholders: ${pPl.isEmpty ? 'none' : pPl.map((x) => '`{$x}`').join(', ')})');
          buffer.writeln(
              '  - `$locale`: `"$cVal"` (Placeholders: ${cPl.isEmpty ? 'none' : cPl.map((x) => '`{$x}`').join(', ')})');
        }
        buffer.writeln();
      });
    } else {
      buffer.writeln('## ✅ Placeholder Mismatches');
      buffer.writeln(
          'No placeholder mismatches detected across translation files.');
      buffer.writeln();
    }

    // Unused keys section
    if (unusedKeysCheck) {
      if (unusedKeys.isNotEmpty) {
        buffer.writeln(
            '## 🔍 Unused Translation Keys (Not referenced in lib/ files)');
        for (final key in unusedKeys) {
          buffer.writeln('- `$key`');
        }
        buffer.writeln();
      } else {
        buffer.writeln('## ✅ Unused Translation Keys');
        buffer.writeln(
            'All translation keys from the primary locale are referenced in the Dart code.');
        buffer.writeln();
      }
    }

    return CallToolResult([TextContent(text: buffer.toString())]);
  } catch (e) {
    return CallToolResult(
      [
        TextContent(
            text: 'Error auditing project localization: ${e.toString()}')
      ],
      isError: true,
    );
  }
}
