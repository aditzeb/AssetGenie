import 'dart:io';

import 'package:dart_mcp/server.dart';

import '../common/arb.dart';
import '../common/context.dart';
import '../common/dart_scan.dart';
import '../common/project.dart';

final ToolSpec extractStringsSpec = ToolSpec(
  Tool(
    name: 'assetgenie_extract_strings',
    title: 'Extract hardcoded strings into ARB and localize Dart code',
    description:
        'Scans Dart UI code in lib/ for hardcoded Text() widgets and string literals, '
        'extracts them into the primary ARB localization file with clean camelCase keys '
        'and parameterized placeholders, and optionally rewrites the Dart source files '
        'to use AppLocalizations.of(context). Supports dry_run.',
    annotations: ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
        'apply_rewrites': BooleanSchema(
          description:
              'Whether to rewrite the Dart files in lib/ to reference the generated ARB keys (default: false).',
        ),
        'dry_run': BooleanSchema(
          description:
              'If true, previews extracted strings and edits without modifying disk (default: true).',
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'strings_found': IntegerSchema(),
        'files_affected': IntegerSchema(),
        'extracted_keys': ObjectSchema(
          description: 'Generated ARB key mapped to template message.',
        ),
        'dry_run': BooleanSchema(),
      },
      required: [
        'strings_found',
        'files_affected',
        'extracted_keys',
        'dry_run',
      ],
    ),
  ),
  extractStringsHandler,
);

class _ExtractedOccurrence {
  final File file;
  final int offset;
  final int length;
  final String rawLiteral;
  final String generatedKey;
  final String arbMessage;
  final List<String> paramNames;
  final List<String> paramExpressions;

  _ExtractedOccurrence({
    required this.file,
    required this.offset,
    required this.length,
    required this.rawLiteral,
    required this.generatedKey,
    required this.arbMessage,
    required this.paramNames,
    required this.paramExpressions,
  });
}

Future<CallToolResult> extractStringsHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final applyRewrites = argBool(args, 'apply_rewrites', false);
  final dryRun = argBool(args, 'dry_run', true);

  final dartFiles = project.dartFiles(excludeGenerated: true);
  final occurrences = <_ExtractedOccurrence>[];
  final generatedKeys = <String, String>{}; // key -> arbMessage
  final keyCounts = <String, int>{};

  String cleanKeyName(String text) {
    var clean = text
        .replaceAll(RegExp(r'\{[a-zA-Z0-9_]+\}'), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ')
        .trim();
    if (clean.isEmpty) return 'text';
    final words = clean.split(RegExp(r'\s+'));
    final buf = StringBuffer(words[0].toLowerCase());
    for (var i = 1; i < words.length && i < 5; i++) {
      final w = words[i];
      if (w.isNotEmpty) {
        buf.write(w[0].toUpperCase() + w.substring(1).toLowerCase());
      }
    }
    var key = buf.toString();
    if (RegExp(r'^[0-9]').hasMatch(key)) key = 'msg$key';
    return key;
  }

  // Scan Text('...') calls
  final textCallPattern = RegExp(r'\bText\s*\(\s*');

  for (final file in dartFiles) {
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      continue;
    }

    final mask = codeMask(content);
    for (final match in textCallPattern.allMatches(content)) {
      final parenEnd = match.end; // index where string literal starts
      if (!mask[match.start]) continue;

      final lit = parseStringLiteral(content, parenEnd);
      if (lit == null) continue;

      // Extract ARB message & placeholders
      final arbBuf = StringBuffer();
      final paramNames = <String>[];
      final paramExprs = <String>[];
      var placeholderIdx = 1;

      for (final part in lit.parts) {
        if (!part.isExpression) {
          arbBuf.write(part.text ?? '');
        } else {
          final expr = part.expression!;
          var pName = expr.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
          if (pName.isEmpty || RegExp(r'^[0-9]').hasMatch(pName)) {
            pName = 'arg$placeholderIdx';
            placeholderIdx++;
          }
          arbBuf.write('{$pName}');
          paramNames.add(pName);
          paramExprs.add(expr);
        }
      }

      final message = arbBuf.toString().trim();
      // Skip empty or non-translatable strings
      if (message.isEmpty ||
          message.startsWith('http://') ||
          message.startsWith('https://') ||
          message.startsWith('/') ||
          message.length <= 1) {
        continue;
      }

      var key = cleanKeyName(message);
      if (keyCounts.containsKey(key)) {
        keyCounts[key] = keyCounts[key]! + 1;
        key = '$key${keyCounts[key]}';
      } else {
        keyCounts[key] = 1;
      }

      generatedKeys[key] = message;

      occurrences.add(_ExtractedOccurrence(
        file: file,
        offset: lit.start,
        length: lit.end - lit.start,
        rawLiteral: content.substring(lit.start, lit.end),
        generatedKey: key,
        arbMessage: message,
        paramNames: paramNames,
        paramExpressions: paramExprs,
      ));
    }
  }

  final affectedFiles = occurrences.map((o) => o.file.path).toSet();

  // If not dry_run, apply to ARB and Dart files
  if (!dryRun) {
    final primaryLocale = project.l10n.templateLocale;
    final primaryFile = locateArbFile(project, primaryLocale);
    final arbData = readArb(primaryFile);

    for (final entry in generatedKeys.entries) {
      arbData[entry.key] = entry.value;
    }
    writeArb(primaryFile, arbData);

    // If apply_rewrites is requested, rewrite Dart files
    if (applyRewrites) {
      final byFile = <String, List<_ExtractedOccurrence>>{};
      for (final occ in occurrences) {
        byFile.putIfAbsent(occ.file.path, () => []).add(occ);
      }

      final importLine = project.l10n.importFor(project.name);

      for (final entry in byFile.entries) {
        final filePath = entry.key;
        final fileOccs = entry.value;
        // Sort descending by offset so we replace from back to front safely
        fileOccs.sort((a, b) => b.offset.compareTo(a.offset));

        final file = File(filePath);
        var src = await file.readAsString();

        for (final occ in fileOccs) {
          final accessor = project.l10n.accessor;
          String callCode;
          if (occ.paramExpressions.isEmpty) {
            callCode = '$accessor.${occ.generatedKey}';
          } else {
            callCode = '$accessor.${occ.generatedKey}(${occ.paramExpressions.join(', ')})';
          }

          src = src.substring(0, occ.offset) +
              callCode +
              src.substring(occ.offset + occ.length);
        }

        // Add import if not present
        if (!src.contains(importLine)) {
          src = '$importLine\n$src';
        }

        await file.writeAsString(src);
      }
    }
  }

  final report = StringBuffer()
    ..writeln('# AssetGenie String Extraction Report')
    ..writeln('Project: `${project.name}`')
    ..writeln('Mode: ${dryRun ? '`dry_run` (preview only)' : 'Applied'}')
    ..writeln('Rewrites Applied to Dart: ${applyRewrites ? 'Yes' : 'No'}')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Hardcoded strings extracted: ${occurrences.length}')
    ..writeln('- Files affected: ${affectedFiles.length}')
    ..writeln();

  if (generatedKeys.isNotEmpty) {
    report.writeln('### Extracted ARB Keys');
    for (final entry in generatedKeys.entries.take(15)) {
      report.writeln('- `"${entry.key}": "${entry.value}"`');
    }
    if (generatedKeys.length > 15) {
      report.writeln('- ... and ${generatedKeys.length - 15} more keys.');
    }
  }

  final structured = <String, Object?>{
    'strings_found': occurrences.length,
    'files_affected': affectedFiles.length,
    'extracted_keys': generatedKeys,
    'dry_run': dryRun,
  };

  return toolOk(report.toString(), structured);
}

