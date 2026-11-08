import 'dart:convert';

import 'package:dart_mcp/server.dart';

import '../common/arb.dart';
import '../common/context.dart';
import '../common/project.dart';

final ToolSpec translateLocalizationSpec = ToolSpec(
  Tool(
    name: 'assetgenie_translate_localization',
    title: 'Auto-translate missing ARB keys with MCP LLM sampling',
    description:
        'Identifies missing translation keys in target ARB files and translates them '
        'from the primary locale using MCP client LLM sampling, strictly preserving '
        'ICU placeholders ({name}) and plural logic. Supports dry_run.',
    annotations: ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
        'target_locale': StringSchema(
          description: "Target language code to translate into (e.g. 'es', 'de', 'ja', 'id').",
        ),
        'primary_locale': StringSchema(
          description: "Source locale to translate from (default: 'en').",
        ),
        'dry_run': BooleanSchema(
          description:
              'If true, previews translations without saving to disk (default: false).',
        ),
      },
      required: ['project_path', 'target_locale'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'target_locale': StringSchema(),
        'keys_translated': IntegerSchema(),
        'translations': ObjectSchema(
          description: 'Key mapped to translated string.',
        ),
        'dry_run': BooleanSchema(),
      },
      required: [
        'target_locale',
        'keys_translated',
        'translations',
        'dry_run',
      ],
    ),
  ),
  translateLocalizationHandler,
);

Future<CallToolResult> translateLocalizationHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final targetLocale = args['target_locale'] as String?;
  if (targetLocale == null || targetLocale.trim().isEmpty) {
    return toolError('"target_locale" is required.');
  }

  final primaryLocale = args['primary_locale'] as String? ??
      (project.l10n.templateLocale.isNotEmpty ? project.l10n.templateLocale : 'en');
  final dryRun = argBool(args, 'dry_run', false);

  final arbMap = loadArbFiles(project);
  final primaryArb = arbMap[primaryLocale];
  if (primaryArb == null) {
    return toolError('Primary locale ARB file for "$primaryLocale" not found.');
  }

  final targetFile = locateArbFile(project, targetLocale);
  final targetData = readArb(targetFile);

  // Find missing keys
  final missingKeys = <String, String>{};
  for (final key in primaryArb.messageKeys) {
    if (!targetData.containsKey(key)) {
      final val = primaryArb.data[key];
      if (val is String) {
        missingKeys[key] = val;
      }
    }
  }

  if (missingKeys.isEmpty) {
    return toolOk(
      '# AssetGenie Translation Report\n\n'
      'All keys from `$primaryLocale` are already translated in `$targetLocale`. No action needed.',
      {
        'target_locale': targetLocale,
        'keys_translated': 0,
        'translations': <String, String>{},
        'dry_run': dryRun,
      },
    );
  }

  // Use MCP sampling if client supports it
  final translations = <String, String>{};

  if (context.canSample) {
    final systemPrompt =
        'You are a professional localization and translation engine for mobile Flutter applications. '
        'Translate the provided JSON map of translation strings from locale "$primaryLocale" to target locale "$targetLocale". '
        'CRITICAL RULES:\n'
        '1. Preserve all ICU placeholders like {name}, {count}, {date} exactly without modifying or translating them.\n'
        '2. Preserve any ICU plural syntax {count, plural, =1{...} other{...}} structure.\n'
        '3. Return ONLY a valid JSON object of key-value pairs matching the input keys.';

    final promptText = jsonEncode(missingKeys);
    final response = await context.sample(
      systemPrompt: systemPrompt,
      prompt: promptText,
    );

    if (response != null) {
      try {
        var cleanJson = response.trim();
        if (cleanJson.startsWith('```json')) {
          cleanJson = cleanJson.substring(7);
        }
        if (cleanJson.startsWith('```')) {
          cleanJson = cleanJson.substring(3);
        }
        if (cleanJson.endsWith('```')) {
          cleanJson = cleanJson.substring(0, cleanJson.length - 3);
        }
        cleanJson = cleanJson.trim();

        final parsed = jsonDecode(cleanJson);
        if (parsed is Map) {
          parsed.forEach((k, v) {
            if (v is String) translations[k.toString()] = v;
          });
        }
      } catch (_) {}
    }
  }

  // If sampling wasn't available or returned empty, return the missing keys as template
  final keysToApply = translations.isNotEmpty ? translations : missingKeys;

  if (!dryRun && translations.isNotEmpty) {
    final confirmed = await context.confirm(
      'Apply ${translations.length} translated keys to $targetLocale ARB file?',
    );
    if (confirmed) {
      targetData.addAll(translations);
      writeArb(targetFile, targetData);
    }
  }

  final report = StringBuffer()
    ..writeln('# AssetGenie Translation Report')
    ..writeln('Primary Locale: `$primaryLocale`')
    ..writeln('Target Locale: `$targetLocale`')
    ..writeln('Client Sampling Available: ${context.canSample ? 'Yes' : 'No'}')
    ..writeln('Mode: ${dryRun ? '`dry_run` (preview only)' : 'Applied'}')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Missing keys detected: ${missingKeys.length}')
    ..writeln('- Keys translated: ${translations.length}')
    ..writeln();

  if (translations.isNotEmpty) {
    report.writeln('### Applied Translations');
    for (final entry in translations.entries) {
      report.writeln('- `${entry.key}`: `"${entry.value}"`');
    }
  } else {
    report.writeln(
      'Client does not support MCP sampling or sampling did not complete. '
      'Here are the missing keys requiring translation:\n',
    );
    for (final entry in missingKeys.entries) {
      report.writeln('- `${entry.key}`: `"${entry.value}"`');
    }
  }

  final structured = <String, Object?>{
    'target_locale': targetLocale,
    'keys_translated': translations.length,
    'translations': keysToApply,
    'dry_run': dryRun,
  };

  return toolOk(report.toString(), structured);
}

