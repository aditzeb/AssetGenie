import 'package:dart_mcp/server.dart';

import '../common/arb.dart';
import '../common/context.dart';
import '../common/project.dart';

final ToolSpec syncLocalizationSpec = ToolSpec(
  Tool(
    name: 'assetgenie_sync_localization',
    title: 'Sync keys into an ARB localization file',
    description:
        'Directly updates or injects missing translation keys into local '
        'Application Resource Bundle (.arb) files, sorted alphabetically '
        'with metadata keys (@key) placed alongside their messages. '
        'Supports dry_run to preview additions without writing.',
    annotations: ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
        'locale': StringSchema(
          description: "Target language code (e.g., 'en', 'id', 'de').",
        ),
        'kv_pairs': ObjectSchema(
          description:
              'A JSON map of key-value translation strings to merge.',
        ),
        'dry_run': BooleanSchema(
          description:
              'If true, previews the merged output without touching disk.',
        ),
      },
      required: ['project_path', 'locale', 'kv_pairs'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'locale': StringSchema(),
        'file_path': StringSchema(),
        'keys_added': IntegerSchema(),
        'keys_updated': IntegerSchema(),
        'total_keys': IntegerSchema(),
        'dry_run': BooleanSchema(),
      },
      required: [
        'locale',
        'file_path',
        'keys_added',
        'keys_updated',
        'total_keys',
        'dry_run',
      ],
    ),
  ),
  syncLocalizationHandler,
);

Future<CallToolResult> syncLocalizationHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final locale = args['locale'] as String?;
  if (locale == null || locale.trim().isEmpty) {
    return toolError('"locale" is required and cannot be empty.');
  }

  final kvPairs = args['kv_pairs'];
  if (kvPairs == null || kvPairs is! Map) {
    return toolError(
        '"kv_pairs" must be a JSON object containing key-value translation pairs.');
  }

  final dryRun = argBool(args, 'dry_run', false);

  final targetFile = locateArbFile(project, locale);
  Map<String, dynamic> existing;
  try {
    existing = readArb(targetFile);
  } catch (e) {
    return toolError('Parsing existing ARB at "${targetFile.path}": $e');
  }

  var added = 0;
  var updated = 0;
  final merged = Map<String, dynamic>.from(existing);
  if (!merged.containsKey('@@locale')) {
    merged['@@locale'] = locale;
  }

  kvPairs.forEach((rawKey, value) {
    final key = rawKey.toString();
    if (merged.containsKey(key)) {
      if (merged[key] != value) updated++;
    } else {
      added++;
    }
    merged[key] = value;
  });

  final relPath = project.rel(targetFile.path);

  if (!dryRun) {
    final confirmed = await context.confirm(
      'Sync $locale localization in $relPath: add $added keys, update $updated keys.',
    );
    if (!confirmed) {
      return toolError('User declined to update $relPath.');
    }
    writeArb(targetFile, merged);
  }

  final action = dryRun
      ? 'Would update'
      : (existing.isEmpty ? 'Created' : 'Updated');
  final markdown = StringBuffer()
    ..writeln('# AssetGenie Localization Sync Report')
    ..writeln('Locale: `$locale`')
    ..writeln('File: `$relPath`')
    ..writeln('Mode: ${dryRun ? '`dry_run` (no disk changes)' : 'Applied'}')
    ..writeln()
    ..writeln('- Keys added: $added')
    ..writeln('- Keys updated: $updated')
    ..writeln('- Total keys in file: ${merged.length}')
    ..writeln()
    ..writeln('Success: $action localization file `$relPath` for locale `$locale`.');

  final structured = <String, Object?>{
    'locale': locale,
    'file_path': relPath,
    'keys_added': added,
    'keys_updated': updated,
    'total_keys': merged.length,
    'dry_run': dryRun,
  };

  return toolOk(markdown.toString(), structured);
}
