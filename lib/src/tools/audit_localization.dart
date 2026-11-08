import 'package:dart_mcp/server.dart';

import '../common/arb.dart';
import '../common/context.dart';
import '../common/project.dart';

final ToolSpec auditLocalizationSpec = ToolSpec(
  Tool(
    name: 'assetgenie_audit_localization',
    title: 'Audit ARB localization files and translation keys',
    description:
        "Scans the target Flutter project's ARB localization files to identify "
        'missing translations, extra keys, ICU parameter/placeholder mismatches, '
        'and unused translation keys in Dart source code.',
    annotations: ToolAnnotations(
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
        'primary_locale': StringSchema(
          description:
              "The base locale code to compare other locales against (default: 'en').",
        ),
        'unused_keys_check': BooleanSchema(
          description:
              'Whether to check if translation keys are unused in the Dart source code (default: true).',
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'primary_locale': StringSchema(),
        'locales_detected': ListSchema(items: StringSchema()),
        'primary_keys_count': IntegerSchema(),
        'missing_keys': ObjectSchema(
          description: 'Locale mapped to list of missing keys.',
        ),
        'extra_keys': ObjectSchema(
          description: 'Locale mapped to list of extra keys not in primary.',
        ),
        'placeholder_mismatches': ObjectSchema(
          description: 'Locale mapped to list of placeholder mismatch objects.',
        ),
        'unused_keys': ListSchema(items: StringSchema()),
      },
      required: [
        'primary_locale',
        'locales_detected',
        'primary_keys_count',
        'missing_keys',
        'extra_keys',
        'placeholder_mismatches',
        'unused_keys',
      ],
    ),
  ),
  auditLocalizationHandler,
);

Future<CallToolResult> auditLocalizationHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final requestedPrimary = args['primary_locale'] as String?;
  final unusedKeysCheck = argBool(args, 'unused_keys_check', true);

  // 1. Locate and parse ARB files
  final arbMap = loadArbFiles(project);
  if (arbMap.isEmpty) {
    return toolError(
      'No valid ARB (.arb) localization files found in the project under `lib/` or `${project.l10n.arbDir}`.',
    );
  }

  // 2. Determine primary locale
  final primary = (requestedPrimary != null && arbMap.containsKey(requestedPrimary))
      ? requestedPrimary
      : (arbMap.containsKey(project.l10n.templateLocale)
          ? project.l10n.templateLocale
          : (arbMap.containsKey('en') ? 'en' : arbMap.keys.first));

  final primaryArb = arbMap[primary]!;
  final primaryKeys = primaryArb.messageKeys.toList()..sort();

  // 3. Compare other locales against primary
  final missingKeys = <String, List<String>>{};
  final extraKeys = <String, List<String>>{};
  final placeholderMismatches = <String, List<Map<String, Object?>>>{};

  for (final entry in arbMap.entries) {
    final locale = entry.key;
    if (locale == primary) continue;

    final data = entry.value.data;
    final currentKeys = entry.value.messageKeys.toSet();

    // Missing keys
    final missing = primaryKeys.where((k) => !currentKeys.contains(k)).toList();
    if (missing.isNotEmpty) missingKeys[locale] = missing;

    // Extra keys
    final extra = currentKeys.where((k) => !primaryArb.data.containsKey(k)).toList()..sort();
    if (extra.isNotEmpty) extraKeys[locale] = extra;

    // Placeholder mismatches (using ICU placeholder extractor)
    final mismatches = <Map<String, Object?>>[];
    for (final key in primaryKeys) {
      if (!currentKeys.contains(key)) continue;

      final primaryVal = primaryArb.data[key];
      final currentVal = data[key];

      if (primaryVal is String && currentVal is String) {
        final pPlaceholders = placeholdersOf(primaryVal);
        final cPlaceholders = placeholdersOf(currentVal);

        if (pPlaceholders.length != cPlaceholders.length ||
            !pPlaceholders.containsAll(cPlaceholders)) {
          mismatches.add({
            'key': key,
            'primary_val': primaryVal,
            'primary_placeholders': pPlaceholders.toList()..sort(),
            'current_val': currentVal,
            'current_placeholders': cPlaceholders.toList()..sort(),
          });
        }
      }
    }

    if (mismatches.isNotEmpty) {
      placeholderMismatches[locale] = mismatches;
    }
  }

  // 4. Check for unused translation keys in Dart source code
  final unusedKeys = <String>[];
  if (unusedKeysCheck && primaryKeys.isNotEmpty) {
    final dartSources = project.readDartSources(excludeGenerated: true).values.toList();
    final keyRegexes = {
      for (final key in primaryKeys) key: RegExp('\\b${RegExp.escape(key)}\\b')
    };

    for (final key in primaryKeys) {
      final regex = keyRegexes[key]!;
      final isUsed = dartSources.any((src) => regex.hasMatch(src));
      if (!isUsed) {
        unusedKeys.add(key);
      }
    }
    unusedKeys.sort();
  }

  // 5. Construct Report
  final buf = StringBuffer()
    ..writeln('# AssetGenie Localization Audit Report')
    ..writeln('Project Path: `${project.root}`')
    ..writeln('Primary Locale: `$primary` (file: `${project.rel(primaryArb.file.path)}`)')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Locales detected: ${arbMap.keys.join(', ')}')
    ..writeln('- Total keys in primary locale: ${primaryKeys.length}')
    ..writeln('- Locales with missing keys: ${missingKeys.length}')
    ..writeln('- Locales with placeholder mismatches: ${placeholderMismatches.length}');

  if (unusedKeysCheck) {
    buf.writeln('- Unused translation keys: ${unusedKeys.length}');
  }
  buf.writeln();

  if (missingKeys.isNotEmpty) {
    buf.writeln('## ❌ Missing Translations (Keys in primary but missing in target)');
    missingKeys.forEach((locale, keys) {
      buf.writeln('### Locale `$locale` (file: `${project.rel(arbMap[locale]!.file.path)}`)');
      for (final key in keys) {
        buf.writeln('- `$key`');
      }
      buf.writeln();
    });
  } else {
    buf
      ..writeln('## ✅ Missing Translations')
      ..writeln('All locales have all keys defined in the primary locale.')
      ..writeln();
  }

  if (extraKeys.isNotEmpty) {
    buf.writeln('## 📦 Extra Translations (Keys in target but missing in primary)');
    extraKeys.forEach((locale, keys) {
      buf.writeln('### Locale `$locale` (file: `${project.rel(arbMap[locale]!.file.path)}`)');
      for (final key in keys) {
        buf.writeln('- `$key`');
      }
      buf.writeln();
    });
  }

  if (placeholderMismatches.isNotEmpty) {
    buf.writeln('## ⚠️ Placeholder Mismatches (Placeholders must match between translations)');
    placeholderMismatches.forEach((locale, mismatches) {
      buf.writeln('### Locale `$locale` (file: `${project.rel(arbMap[locale]!.file.path)}`)');
      for (final item in mismatches) {
        final key = item['key'] as String;
        final pVal = item['primary_val'] as String;
        final pPl = (item['primary_placeholders'] as List).cast<String>();
        final cVal = item['current_val'] as String;
        final cPl = (item['current_placeholders'] as List).cast<String>();

        buf
          ..writeln('- Key: `$key`')
          ..writeln('  - `$primary`: `"$pVal"` (Placeholders: ${pPl.isEmpty ? 'none' : pPl.map((x) => '`{$x}`').join(', ')})')
          ..writeln('  - `$locale`: `"$cVal"` (Placeholders: ${cPl.isEmpty ? 'none' : cPl.map((x) => '`{$x}`').join(', ')})');
      }
      buf.writeln();
    });
  } else {
    buf
      ..writeln('## ✅ Placeholder Mismatches')
      ..writeln('No placeholder mismatches detected across translation files.')
      ..writeln();
  }

  if (unusedKeysCheck) {
    if (unusedKeys.isNotEmpty) {
      buf.writeln('## 🔍 Unused Translation Keys (Not referenced in lib/ files)');
      for (final key in unusedKeys) {
        buf.writeln('- `$key`');
      }
      buf.writeln();
    } else {
      buf
        ..writeln('## ✅ Unused Translation Keys')
        ..writeln('All translation keys from the primary locale are referenced in the Dart code.')
        ..writeln();
    }
  }

  final structured = <String, Object?>{
    'primary_locale': primary,
    'locales_detected': arbMap.keys.toList()..sort(),
    'primary_keys_count': primaryKeys.length,
    'missing_keys': missingKeys,
    'extra_keys': extraKeys,
    'placeholder_mismatches': placeholderMismatches,
    'unused_keys': unusedKeys,
  };

  return toolOk(buf.toString(), structured);
}
